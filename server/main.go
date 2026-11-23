package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 8192,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func newServerMux(rm *RoomManager, store *MatchStore) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":       "ok",
			"rooms":        rm.RoomCount(),
			"db_connected": store != nil && store.IsDBConnected(),
			"tick_hz":      TickHz,
		})
	})

	mux.HandleFunc("GET /api/rooms", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"rooms": rm.ListRooms(),
		})
	})

	mux.HandleFunc("POST /api/rooms", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			RoomCode string `json:"room_code"`
		}
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024)).Decode(&body)
		room, err := rm.CreateOrGetRoom(body.RoomCode)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{
			"room_code": room.Code,
		})
	})

	mux.HandleFunc("GET /ws", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		roomCode := q.Get("room")
		playerName := q.Get("name")
		token := q.Get("token")

		room, err := rm.CreateOrGetRoom(roomCode)
		if err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}

		conn, err := wsUpgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		conn.SetReadLimit(16 * 1024)

		sendCh := make(chan []byte, 64)
		doneCh := make(chan struct{})
		sendFn := func(data []byte) {
			select {
			case sendCh <- data:
			case <-doneCh:
			default:
			}
		}

		slot, reconnected, err := room.Join(playerName, token, sendFn)
		if err != nil {
			_ = conn.WriteMessage(websocket.TextMessage, mustJSON(map[string]any{"type": "error", "message": err.Error()}))
			_ = conn.Close()
			return
		}

		// Writer pump with 20s ping keepalive
		go func() {
			pingTicker := time.NewTicker(20 * time.Second)
			defer func() {
				pingTicker.Stop()
				_ = conn.Close()
			}()
			for {
				select {
				case msg, ok := <-sendCh:
					if !ok {
						return
					}
					_ = conn.SetWriteDeadline(time.Now().Add(8 * time.Second))
					if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
						return
					}
				case <-pingTicker.C:
					_ = conn.SetWriteDeadline(time.Now().Add(8 * time.Second))
					if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
						return
					}
				case <-doneCh:
					return
				}
			}
		}()

		room.SendWelcomeAndState(slot, reconnected)

		_ = conn.SetReadDeadline(time.Now().Add(65 * time.Second))
		conn.SetPongHandler(func(string) error {
			_ = conn.SetReadDeadline(time.Now().Add(65 * time.Second))
			return nil
		})

		for {
			_, rawMsg, err := conn.ReadMessage()
			if err != nil {
				break
			}
			_ = conn.SetReadDeadline(time.Now().Add(65 * time.Second))
			room.HandleClientMessage(slot, rawMsg)
		}

		close(doneCh)
		room.Detach(slot.NationID, func(p *PlayerSlot) bool {
			return p == slot
		})
	})

	return mux
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	dbURL := os.Getenv("DATABASE_URL")

	ctx := context.Background()
	store, err := NewMatchStore(ctx, dbURL)
	if err != nil {
		log.Fatalf("[WWP-SERVER] PostgreSQL initialization failed: %v", err)
	}
	defer store.Close()

	rm := NewRoomManager(store)
	stopJanitor := make(chan struct{})
	go rm.StartJanitor(stopJanitor)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           newServerMux(rm, store),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("[WWP-SERVER] Listening on :%s (db_connected=%v, tick_hz=%d)", port, store.IsDBConnected(), TickHz)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[WWP-SERVER] ListenAndServe error: %v", err)
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	log.Println("[WWP-SERVER] Shutting down...")
	close(stopJanitor)
	shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutCtx)
}
