package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestValidateAntiSpoofingAndBounds(t *testing.T) {
	// Client tries to spoof nation_id = 99
	cmd, err := ValidateAndSanitizeCommand(2, map[string]any{
		"type":         "expand_to",
		"nation_id":    99,
		"x":            240,
		"y":            150,
		"commit_ratio": 0.50,
	})
	if err != nil {
		t.Fatalf("expected valid command, got err: %v", err)
	}
	if cmd["nation_id"] != 2 {
		t.Fatalf("expected nation_id forced to 2, got %v", cmd["nation_id"])
	}

	// Out of bounds coordinate rejection
	if _, err := ValidateAndSanitizeCommand(1, map[string]any{
		"type": "expand_to", "x": 1500, "y": 100,
	}); err == nil {
		t.Fatal("expected out-of-bounds error")
	}

	// Disallowed command rejection
	if _, err := ValidateAndSanitizeCommand(1, map[string]any{
		"type": "deploy_army", "x": 10, "y": 10,
	}); err == nil {
		t.Fatal("expected disallowed command error")
	}
}

func TestRateLimiterAndDuplicateSeq(t *testing.T) {
	rl := NewRateLimiter(12.0, 20.0)
	for i := 0; i < 20; i++ {
		if !rl.Allow() {
			t.Fatalf("expected burst token %d to pass", i)
		}
	}
	if rl.Allow() {
		t.Fatal("expected 21st immediate call to be rate-limited")
	}

	rm := NewRoomManager(nil)
	defer rm.StopAll()
	room, _ := rm.CreateOrGetRoom("SEQ1")
	s1, _, _ := room.Join("Host", "", func([]byte) {})
	room.HandleClientMessage(s1, mustJSON(map[string]any{"type": "start_match", "ai_count": 2}))
	room.HandleClientMessage(s1, mustJSON(map[string]any{"type": "pick_spawn", "x": 200, "y": 150}))

	// Duplicate seq = 1 submitted twice should enqueue only once
	msg := mustJSON(map[string]any{"type": "command", "seq": 1, "cmd": map[string]any{"type": "expand_to", "x": 210, "y": 150}})
	room.HandleClientMessage(s1, msg)
	room.HandleClientMessage(s1, msg)

	room.mu.Lock()
	pending := len(room.PendingCmds)
	room.mu.Unlock()
	if pending != 1 {
		t.Fatalf("expected 1 queued command after duplicate seq, got %d", pending)
	}
}

func readMsgType(t *testing.T, conn *websocket.Conn, wantType string) map[string]any {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(4 * time.Second))
	for i := 0; i < 25; i++ {
		_, data, err := conn.ReadMessage()
		if err != nil {
			t.Fatalf("read error waiting for %s: %v", wantType, err)
		}
		var m map[string]any
		if err := json.Unmarshal(data, &m); err != nil {
			t.Fatalf("json unmarshal error: %v", err)
		}
		if m["type"] == wantType {
			return m
		}
	}
	t.Fatalf("did not receive message type %s", wantType)
	return nil
}

func TestTwoPlayerMatchAndReconnectFlow(t *testing.T) {
	store, err := NewMatchStore(t.Context(), "")
	if err != nil {
		t.Fatalf("NewMatchStore failed: %v", err)
	}
	rm := NewRoomManager(store)
	defer rm.StopAll()

	srv := httptest.NewServer(newServerMux(rm, store))
	defer srv.Close()

	// Check /health & POST /api/rooms
	resp, err := http.Get(srv.URL + "/health")
	if err != nil || resp.StatusCode != 200 {
		t.Fatalf("health failed: %v", err)
	}
	_ = resp.Body.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws?room=WWPTEST&name="
	c1, _, err := websocket.DefaultDialer.Dial(wsURL+"Alpha", nil)
	if err != nil {
		t.Fatalf("dial p1 failed: %v", err)
	}
	defer c1.Close()
	w1 := readMsgType(t, c1, "connected")
	token1 := w1["reconnect_token"].(string)

	c2, _, err := websocket.DefaultDialer.Dial(wsURL+"Beta", nil)
	if err != nil {
		t.Fatalf("dial p2 failed: %v", err)
	}
	defer c2.Close()
	_ = readMsgType(t, c2, "connected")

	// Verify low-latency ping/pong latency probe echoes client timestamp cleanly
	_ = c1.WriteJSON(map[string]any{"type": "ping", "t": 123456})
	pongMsg := readMsgType(t, c1, "pong")
	if int(pongMsg["t"].(float64)) != 123456 {
		t.Fatalf("expected pong t=123456, got %v", pongMsg["t"])
	}

	// Host starts match -> spawn_phase -> both pick spawn -> match_begin -> tick_batch
	_ = c1.WriteJSON(map[string]any{"type": "start_match", "ai_count": 2})
	_ = readMsgType(t, c1, "spawn_phase")
	_ = readMsgType(t, c2, "spawn_phase")

	_ = c1.WriteJSON(map[string]any{"type": "pick_spawn", "x": 230, "y": 145})
	_ = c2.WriteJSON(map[string]any{"type": "pick_spawn", "x": 520, "y": 120})

	_ = readMsgType(t, c1, "match_begin")
	_ = readMsgType(t, c2, "match_begin")

	// Send spoofed nation_id command from P2; verify tick_batch carries nation_id = 2
	_ = c2.WriteJSON(map[string]any{
		"type": "command",
		"seq":  1,
		"cmd":  map[string]any{"type": "expand_to", "nation_id": 1, "x": 525, "y": 122, "commit_ratio": 0.35},
	})

	var sawSpoofFixed bool
	_ = c1.SetReadDeadline(time.Now().Add(3 * time.Second))
	for i := 0; i < 12; i++ {
		_, data, err := c1.ReadMessage()
		if err != nil {
			t.Fatalf("failed reading tick_batch: %v", err)
		}
		var m map[string]any
		_ = json.Unmarshal(data, &m)
		if m["type"] == "tick_batch" {
			cmds, _ := m["commands"].([]any)
			for _, rawC := range cmds {
				cm, _ := rawC.(map[string]any)
				if cm["type"] == "expand_to" {
					if int(cm["nation_id"].(float64)) != 2 {
						t.Fatalf("expected server-stamped nation_id=2, got %v", cm["nation_id"])
					}
					sawSpoofFixed = true
					break
				}
			}
			if sawSpoofFixed {
				break
			}
		}
	}
	if !sawSpoofFixed {
		t.Fatal("never saw sanitized expand_to command in tick_batch")
	}

	// Simulate P1 disconnect & reconnect using reconnect_token -> verify match_snapshot arrives
	_ = c1.Close()
	c1Re, _, err := websocket.DefaultDialer.Dial(wsURL+"Alpha&token="+token1, nil)
	if err != nil {
		t.Fatalf("reconnect dial failed: %v", err)
	}
	defer c1Re.Close()
	_ = readMsgType(t, c1Re, "connected")
	snap := readMsgType(t, c1Re, "match_snapshot")
	batches, _ := snap["batches"].([]any)
	if len(batches) == 0 {
		t.Fatal("expected historical batches in match_snapshot on reconnect")
	}
}
