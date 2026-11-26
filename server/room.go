package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"strings"
	"sync"
	"time"
)

const (
	PhaseLobby    = "LOBBY"
	PhaseSpawning = "SPAWNING"
	PhasePlaying  = "PLAYING"
	PhaseFinished = "FINISHED"

	TickHz            = 24
	TicksPerBatch     = 3
	MaxPlayersPerRoom = 16
	MaxRooms          = 256
	SpawnTimeoutSec   = 10
)

const roomAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

// PlayerSlot represents one human player slot in a match room.
type PlayerSlot struct {
	NationID       int          `json:"nation_id"`
	Name           string       `json:"name"`
	TeamID         int          `json:"team_id"`
	AccountUser    string       `json:"account_username,omitempty"`
	AvatarHash     string       `json:"avatar_hash,omitempty"`
	ReconnectToken string       `json:"-"`
	SpawnX         int          `json:"x"`
	SpawnY         int          `json:"y"`
	HasSpawn       bool         `json:"has_spawn"`
	Connected      bool         `json:"connected"`
	IsHost         bool         `json:"is_host"`
	IsSpectator    bool         `json:"-"`
	LastSeq        int64        `json:"-"`
	Limiter        *RateLimiter `json:"-"`
	sendMu         sync.Mutex   `json:"-"`
	sendFn         func([]byte) `json:"-"`
}

// Send delivers a serialized message safely if connected.
func (p *PlayerSlot) Send(data []byte) {
	p.sendMu.Lock()
	fn := p.sendFn
	connected := p.Connected
	p.sendMu.Unlock()
	if connected && fn != nil {
		fn(data)
	}
}

// BatchRecord holds one deterministic command batch for broadcast and reconnect replay.
type BatchRecord struct {
	FromTick int              `json:"from_tick"`
	ToTick   int              `json:"to_tick"`
	Commands []map[string]any `json:"commands"`
}

// Room owns the authoritative lobby, spawn timer, and 24 Hz command batch loop for one match.
type Room struct {
	mu            sync.Mutex
	Code          string
	MatchID       string
	Phase         string
	Seed          int64
	AICount       int
	IsPublic      bool
	TeamMode      bool
	GameSpeed     float64
	NoNukes       bool
	AIDifficulty  string
	StartPreset   string
	CurrentTick   int
	Players       []*PlayerSlot
	Spectators    []*PlayerSlot
	PendingCmds   []map[string]any
	Batches       []BatchRecord
	SyncHashes    map[int]map[int]int64 // tick -> nationID -> hash
	SpawnDeadline time.Time
	LastActivity  time.Time
	Store         *MatchStore
	AcctSvc       *AccountService
	stopCh        chan struct{}
	persistCh     chan BatchRecord
	tickerRunning bool
	closed        bool
}

// NewRoom creates an initialized lobby room with a random match seed.
func NewRoom(code string, store *MatchStore, acct ...*AccountService) *Room {
	var acctSvc *AccountService
	if len(acct) > 0 {
		acctSvc = acct[0]
	}
	return &Room{
		Code:         code,
		MatchID:      code + "-" + randHex(6),
		Phase:        PhaseLobby,
		Seed:         randSeed(),
		AICount:      4,
		IsPublic:     true,
		GameSpeed:    1.0,
		AIDifficulty: "normal",
		StartPreset:  "standard",
		SyncHashes:   make(map[int]map[int]int64),
		LastActivity: time.Now(),
		Store:        store,
		AcctSvc:      acctSvc,
		stopCh:       make(chan struct{}),
		persistCh:    make(chan BatchRecord, 256),
	}
}

func randHex(nBytes int) string {
	b := make([]byte, nBytes)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func randSeed() int64 {
	n, err := rand.Int(rand.Reader, big.NewInt(2147483640))
	if err != nil {
		return time.Now().UnixNano() & 0x7FFFFFFF
	}
	return n.Int64() + 1
}

func generateRoomCode() string {
	var b strings.Builder
	for i := 0; i < 6; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(roomAlphabet))))
		idx := 0
		if err == nil {
			idx = int(n.Int64())
		}
		b.WriteByte(roomAlphabet[idx])
	}
	return b.String()
}

func (r *Room) optionsMapLocked() map[string]any {
	spd := r.GameSpeed
	if spd <= 0 {
		spd = 1.0
	}
	diff := r.AIDifficulty
	if diff == "" {
		diff = "normal"
	}
	preset := r.StartPreset
	if preset == "" {
		preset = "standard"
	}
	return map[string]any{
		"is_public":     r.IsPublic,
		"team_mode":     r.TeamMode,
		"game_speed":    spd,
		"no_nukes":      r.NoNukes,
		"ai_difficulty": diff,
		"start_preset":  preset,
	}
}

// Summary returns public metadata for GET /api/rooms.
func (r *Room) Summary() map[string]any {
	r.mu.Lock()
	defer r.mu.Unlock()
	connectedCount := 0
	hostName := ""
	for _, p := range r.Players {
		if p.Connected {
			connectedCount++
			if p.IsHost || hostName == "" {
				hostName = p.Name
			}
		}
	}
	return map[string]any{
		"code":             r.Code,
		"match_id":         r.MatchID,
		"phase":            r.Phase,
		"players":          connectedCount,
		"total_slots":      len(r.Players),
		"max_players":      MaxPlayersPerRoom,
		"ai_count":         r.AICount,
		"tick":             r.CurrentTick,
		"is_public":        r.IsPublic,
		"team_mode":        r.TeamMode,
		"options":          r.optionsMapLocked(),
		"host_name":        hostName,
		"joinable":         r.IsPublic && r.Phase == PhaseLobby && len(r.Players) < MaxPlayersPerRoom,
		"spectatable":      r.IsPublic && r.Phase == PhasePlaying,
		"spectator_count":  len(r.Spectators),
	}
}

func sanitizeName(name string) string {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return "Commander"
	}
	if len(trimmed) > 24 {
		return trimmed[:24]
	}
	return trimmed
}

// Join attaches or reconnects a player to the room and attaches sendFn.
func (r *Room) Join(name, token string, sendFn func([]byte)) (*PlayerSlot, bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.closed {
		return nil, false, errRoomClosed
	}
	r.LastActivity = time.Now()
	cleanName := sanitizeName(name)

	if token != "" {
		for _, p := range r.Players {
			if p.ReconnectToken == token {
				p.sendMu.Lock()
				p.sendFn = sendFn
				p.Connected = true
				p.sendMu.Unlock()
				if cleanName != "Commander" {
					p.Name = cleanName
				}
				return p, true, nil
			}
		}
	}

	if r.Phase != PhaseLobby {
		return nil, false, errMatchInProgress
	}
	if len(r.Players) >= MaxPlayersPerRoom {
		return nil, false, errRoomFull
	}

	slot := &PlayerSlot{
		NationID:       len(r.Players) + 1,
		Name:           cleanName,
		ReconnectToken: randHex(16),
		SpawnX:         -1,
		SpawnY:         -1,
		Connected:      true,
		IsHost:         len(r.Players) == 0,
		Limiter:        NewRateLimiter(12.0, 20.0),
		sendFn:         sendFn,
	}
	r.Players = append(r.Players, slot)
	return slot, false, nil
}

// Detach marks a player disconnected and transfers host role if needed in lobby.
func (r *Room) Detach(nationID int, sendFnMatches func(*PlayerSlot) bool) {
	r.mu.Lock()
	var needBroadcast bool
	for _, p := range r.Players {
		if p.NationID == nationID && sendFnMatches(p) {
			p.sendMu.Lock()
			p.Connected = false
			p.sendFn = nil
			p.sendMu.Unlock()
			needBroadcast = true
			if p.IsHost && r.Phase == PhaseLobby {
				p.IsHost = false
				for _, cand := range r.Players {
					if cand.Connected {
						cand.IsHost = true
						break
					}
				}
			}
			break
		}
	}
	r.LastActivity = time.Now()
	snap := r.buildLobbyLocked()
	r.mu.Unlock()

	if needBroadcast {
		r.broadcastBytes(mustJSON(snap))
	}
}

// SendWelcomeAndState delivers initial join confirmation plus lobby state or active match snapshot.
func (r *Room) SendWelcomeAndState(slot *PlayerSlot, reconnected bool) {
	r.mu.Lock()
	welcome := mustJSON(map[string]any{
		"type":            "connected",
		"room_code":       r.Code,
		"nation_id":       slot.NationID,
		"reconnect_token": slot.ReconnectToken,
		"is_host":         slot.IsHost,
		"reconnected":     reconnected,
	})
	lobbyMsg := mustJSON(r.buildLobbyLocked())
	var snapMsg []byte
	if (r.Phase == PhasePlaying || r.Phase == PhaseFinished) && reconnected {
		snapMsg = mustJSON(map[string]any{
			"type":            "match_snapshot",
			"seed":            r.Seed,
			"local_nation_id": slot.NationID,
			"ai_count":        r.AICount,
			"options":         r.optionsMapLocked(),
			"players":         r.snapshotPlayersLocked(),
			"current_tick":    r.CurrentTick,
			"batches":         append([]BatchRecord(nil), r.Batches...),
		})
	} else if r.Phase == PhaseSpawning {
		secLeft := r.SpawnDeadline.Sub(time.Now()).Seconds()
		if secLeft < 0 {
			secLeft = 0
		}
		snapMsg = mustJSON(map[string]any{
			"type":         "spawn_phase",
			"seconds_left": secLeft,
			"players":      r.snapshotPlayersLocked(),
		})
	}
	r.mu.Unlock()

	slot.Send(welcome)
	if snapMsg != nil {
		slot.Send(snapMsg)
	}
	r.broadcastBytes(lobbyMsg)
}

// JoinSpectator attaches a read-only live spectator to an active or lobby room.
func (r *Room) JoinSpectator(name string, sendFn func([]byte)) (*PlayerSlot, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		return nil, errRoomClosed
	}
	if len(r.Spectators) >= 32 {
		return nil, errRoomFull
	}
	slot := &PlayerSlot{
		NationID:    0,
		Name:        sanitizeName(name),
		Connected:   true,
		IsSpectator: true,
		Limiter:     NewRateLimiter(4.0, 8.0),
		sendFn:      sendFn,
	}
	r.Spectators = append(r.Spectators, slot)
	r.LastActivity = time.Now()
	return slot, nil
}

// DetachSpectator removes a disconnected spectator cleanly.
func (r *Room) DetachSpectator(slot *PlayerSlot) {
	if slot == nil {
		return
	}
	slot.sendMu.Lock()
	slot.Connected = false
	slot.sendFn = nil
	slot.sendMu.Unlock()
	r.mu.Lock()
	kept := r.Spectators[:0]
	for _, sp := range r.Spectators {
		if sp != slot {
			kept = append(kept, sp)
		}
	}
	r.Spectators = kept
	r.mu.Unlock()
}

// SendSpectatorWelcome delivers initial spectator handshake + full match snapshot.
func (r *Room) SendSpectatorWelcome(slot *PlayerSlot) {
	r.mu.Lock()
	welcome := mustJSON(map[string]any{
		"type":            "connected",
		"room_code":       r.Code,
		"nation_id":       0,
		"reconnect_token": "",
		"is_host":         false,
		"spectator":       true,
	})
	lobbyMsg := mustJSON(r.buildLobbyLocked())
	var snapMsg []byte
	if r.Phase == PhasePlaying || r.Phase == PhaseFinished {
		snapMsg = mustJSON(map[string]any{
			"type":            "match_snapshot",
			"seed":            r.Seed,
			"local_nation_id": 0,
			"spectator":       true,
			"ai_count":        r.AICount,
			"options":         r.optionsMapLocked(),
			"players":         r.snapshotPlayersLocked(),
			"current_tick":    r.CurrentTick,
			"batches":         append([]BatchRecord(nil), r.Batches...),
		})
	}
	r.mu.Unlock()
	slot.Send(welcome)
	slot.Send(lobbyMsg)
	if snapMsg != nil {
		slot.Send(snapMsg)
	}
}

func (r *Room) snapshotPlayersLocked() []map[string]any {
	out := make([]map[string]any, 0, len(r.Players))
	for _, p := range r.Players {
		out = append(out, map[string]any{
			"nation_id":        p.NationID,
			"name":             p.Name,
			"team_id":          p.TeamID,
			"account_username": p.AccountUser,
			"avatar_hash":      p.AvatarHash,
			"x":                p.SpawnX,
			"y":                p.SpawnY,
			"has_spawn":        p.HasSpawn,
			"connected":        p.Connected,
			"is_host":          p.IsHost,
		})
	}
	return out
}

func (r *Room) buildLobbyLocked() map[string]any {
	return map[string]any{
		"type":      "lobby_state",
		"room_code": r.Code,
		"match_id":  r.MatchID,
		"phase":     r.Phase,
		"ai_count":  r.AICount,
		"is_public": r.IsPublic,
		"team_mode": r.TeamMode,
		"options":   r.optionsMapLocked(),
		"players":   r.snapshotPlayersLocked(),
	}
}

// HandleClientMessage processes incoming WebSocket JSON envelopes from a player slot.
func (r *Room) HandleClientMessage(slot *PlayerSlot, raw []byte) {
	var env map[string]any
	if err := json.Unmarshal(raw, &env); err != nil {
		slot.Send(mustJSON(map[string]any{"type": "error", "message": "Invalid JSON message."}))
		return
	}
	msgType, _ := asString(env["type"])
	if msgType == "ping" {
		slot.Send(mustJSON(map[string]any{"type": "pong", "t": env["t"]}))
		return
	}
	if slot.IsSpectator {
		if msgType == "chat_msg" {
			// Spectators may only post in All chat at a limited rate.
		} else {
			return
		}
	}

	r.mu.Lock()
	r.LastActivity = time.Now()

	switch msgType {
	case "start_match":
		if r.Phase != PhaseLobby {
			r.mu.Unlock()
			return
		}
		if !slot.IsHost {
			r.mu.Unlock()
			slot.Send(mustJSON(map[string]any{"type": "error", "message": "Only the host can start the match."}))
			return
		}
		if aiVal, ok := asInt(env["ai_count"]); ok {
			if aiVal < 0 {
				aiVal = 0
			} else if aiVal > 23 {
				aiVal = 23
			}
			r.AICount = aiVal
		}
		r.Phase = PhaseSpawning
		r.SpawnDeadline = time.Now().Add(SpawnTimeoutSec * time.Second)
		spawnMsg := mustJSON(map[string]any{
			"type":         "spawn_phase",
			"seconds_left": float64(SpawnTimeoutSec),
			"players":      r.snapshotPlayersLocked(),
		})
		lobbyMsg := mustJSON(r.buildLobbyLocked())
		r.mu.Unlock()

		r.broadcastBytes(spawnMsg)
		r.broadcastBytes(lobbyMsg)
		go r.waitSpawnTimer()

	case "pick_spawn":
		if r.Phase != PhaseSpawning {
			r.mu.Unlock()
			slot.Send(mustJSON(map[string]any{"type": "error", "message": "Match is not in spawn phase."}))
			return
		}
		x, y, err := validSimCoord(env)
		if err != nil {
			r.mu.Unlock()
			slot.Send(mustJSON(map[string]any{"type": "error", "message": err.Error()}))
			return
		}
		slot.SpawnX = x
		slot.SpawnY = y
		slot.HasSpawn = true

		allReady := true
		for _, p := range r.Players {
			if p.Connected && !p.HasSpawn {
				allReady = false
				break
			}
		}
		lobbyMsg := mustJSON(r.buildLobbyLocked())
		r.mu.Unlock()

		r.broadcastBytes(lobbyMsg)
		if allReady {
			r.beginPlayingIfSpawning()
		}

	case "command":
		if r.Phase != PhasePlaying {
			r.mu.Unlock()
			return
		}
		if seqFloat, ok := asFloat(env["seq"]); ok {
			seq := int64(seqFloat)
			if seq <= slot.LastSeq {
				r.mu.Unlock()
				return
			}
			slot.LastSeq = seq
		}
		if !slot.Limiter.Allow() {
			r.mu.Unlock()
			slot.Send(mustJSON(map[string]any{"type": "error", "message": "Command rate limit exceeded."}))
			return
		}
		rawCmd, _ := env["cmd"].(map[string]any)
		sanitized, err := ValidateAndSanitizeCommand(slot.NationID, rawCmd)
		if err != nil {
			r.mu.Unlock()
			slot.Send(mustJSON(map[string]any{"type": "error", "message": err.Error()}))
			return
		}
		r.PendingCmds = append(r.PendingCmds, sanitized)
		r.mu.Unlock()

	case "sync_check":
		tick, okT := asInt(env["tick"])
		hashVal, okH := asFloat(env["hash"])
		if okT && okH {
			h := int64(hashVal)
			m, ok := r.SyncHashes[tick]
			if !ok {
				m = make(map[int]int64)
				r.SyncHashes[tick] = m
			}
			m[slot.NationID] = h
			for otherID, otherH := range m {
				if otherID != slot.NationID && otherH != h {
					log.Printf("[SYNC_DRIFT] room=%s tick=%d nation_%d=%d nation_%d=%d", r.Code, tick, slot.NationID, h, otherID, otherH)
				}
			}
			if len(r.SyncHashes) > 64 {
				for k := range r.SyncHashes {
					if k < tick-480 {
						delete(r.SyncHashes, k)
					}
				}
			}
		}
		r.mu.Unlock()

	case "set_team":
		if r.Phase != PhaseLobby {
			r.mu.Unlock()
			return
		}
		if teamVal, ok := asInt(env["team_id"]); ok {
			if teamVal < 0 {
				teamVal = 0
			} else if teamVal > 4 {
				teamVal = 4
			}
			slot.TeamID = teamVal
		}
		lobbyMsg := mustJSON(r.buildLobbyLocked())
		r.mu.Unlock()
		r.broadcastBytes(lobbyMsg)

	case "set_room_options":
		if r.Phase != PhaseLobby {
			r.mu.Unlock()
			return
		}
		if !slot.IsHost {
			r.mu.Unlock()
			slot.Send(mustJSON(map[string]any{"type": "error", "message": "Only the host can change room options."}))
			return
		}
		if pub, ok := asBool(env["is_public"]); ok {
			r.IsPublic = pub
		}
		if tm, ok := asBool(env["team_mode"]); ok {
			r.TeamMode = tm
			if !tm {
				for _, p := range r.Players {
					p.TeamID = 0
				}
			}
		}
		if spd, ok := asFloat(env["game_speed"]); ok {
			if spd == 1.0 || spd == 1.5 || spd == 2.0 {
				r.GameSpeed = spd
			}
		}
		if nn, ok := asBool(env["no_nukes"]); ok {
			r.NoNukes = nn
		}
		if diff, ok := asString(env["ai_difficulty"]); ok {
			if diff == "normal" || diff == "hard" || diff == "brutal" {
				r.AIDifficulty = diff
			}
		}
		if preset, ok := asString(env["start_preset"]); ok {
			if preset == "standard" || preset == "fast" || preset == "sandbox" {
				r.StartPreset = preset
			}
		}
		lobbyMsg := mustJSON(r.buildLobbyLocked())
		r.mu.Unlock()
		r.broadcastBytes(lobbyMsg)

	case "chat_msg":
		if !slot.Limiter.Allow() {
			r.mu.Unlock()
			return
		}
		rawTxt, _ := asString(env["text"])
		txt := strings.TrimSpace(rawTxt)
		if txt == "" {
			r.mu.Unlock()
			return
		}
		if len(txt) > 160 {
			txt = txt[:160]
		}
		ch, _ := asString(env["channel"])
		if ch != "team" || slot.IsSpectator || !r.TeamMode || slot.TeamID <= 0 {
			ch = "all"
		}
		senderTeam := slot.TeamID
		chatBytes := mustJSON(map[string]any{
			"type":           "chat_msg",
			"from_nation_id": slot.NationID,
			"from_name":      slot.Name,
			"team_id":        senderTeam,
			"channel":        ch,
			"text":           txt,
		})
		if ch == "team" {
			targets := make([]*PlayerSlot, 0, len(r.Players))
			for _, p := range r.Players {
				if p.TeamID == senderTeam {
					targets = append(targets, p)
				}
			}
			r.mu.Unlock()
			for _, p := range targets {
				p.Send(chatBytes)
			}
			return
		}
		r.mu.Unlock()
		r.broadcastBytes(chatBytes)

	case "map_ping":
		if r.Phase != PhasePlaying && r.Phase != PhaseSpawning {
			r.mu.Unlock()
			return
		}
		if !slot.Limiter.Allow() {
			r.mu.Unlock()
			return
		}
		px, py, err := validSimCoord(env)
		if err != nil {
			r.mu.Unlock()
			return
		}
		kind, _ := asString(env["kind"])
		if kind != "attack" && kind != "defend" && kind != "nuke" {
			kind = "attack"
		}
		pingMsg := mustJSON(map[string]any{
			"type":           "map_ping",
			"from_nation_id": slot.NationID,
			"from_name":      slot.Name,
			"team_id":        slot.TeamID,
			"x":              px,
			"y":              py,
			"kind":           kind,
		})
		r.mu.Unlock()
		r.broadcastBytes(pingMsg)

	case "match_over":
		if r.Phase == PhasePlaying {
			winID, _ := asInt(env["winner_nation_id"])
			winTeamID, _ := asInt(env["winner_team_id"])
			pctMap, _ := env["territory_pcts"].(map[string]any)
			var participants []MatchParticipantResult
			for _, p := range r.Players {
				if p.AccountUser == "" {
					continue
				}
				pct := 0.0
				if pctMap != nil {
					if v, ok := asFloat(pctMap[fmt.Sprintf("%d", p.NationID)]); ok {
						pct = v
					}
				}
				participants = append(participants, MatchParticipantResult{
					AccountUser:  p.AccountUser,
					NationID:     p.NationID,
					TeamID:       p.TeamID,
					TerritoryPct: pct,
				})
			}
			r.Phase = PhaseFinished
			matchID := r.MatchID
			store := r.Store
			acctSvc := r.AcctSvc
			r.mu.Unlock()
			if acctSvc != nil && len(participants) > 0 {
				go func() {
					ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
					defer cancel()
					acctSvc.RecordMatchResult(ctx, participants, winID, winTeamID)
				}()
			}
			if store != nil {
				go func() {
					ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
					defer cancel()
					_ = store.SaveMatchOutcome(ctx, matchID, PhaseFinished, winID, winTeamID, participants)
				}()
			}
			return
		}
		r.mu.Unlock()

	default:
		r.mu.Unlock()
	}
}

func (r *Room) waitSpawnTimer() {
	timer := time.NewTimer(SpawnTimeoutSec * time.Second)
	defer timer.Stop()
	select {
	case <-timer.C:
		r.beginPlayingIfSpawning()
	case <-r.stopCh:
	}
}

func (r *Room) beginPlayingIfSpawning() {
	r.mu.Lock()
	if r.Phase != PhaseSpawning || r.closed {
		r.mu.Unlock()
		return
	}
	r.Phase = PhasePlaying
	snapPlayers := r.snapshotPlayersLocked()
	opts := r.optionsMapLocked()
	beginMsg := mustJSON(map[string]any{
		"type":     "match_begin",
		"seed":     r.Seed,
		"ai_count": r.AICount,
		"options":  opts,
		"players":  snapPlayers,
	})
	lobbyMsg := mustJSON(r.buildLobbyLocked())
	matchID := r.MatchID
	code := r.Code
	seed := r.Seed
	aiCount := r.AICount
	store := r.Store
	if !r.tickerRunning {
		r.tickerRunning = true
		go r.runPersistWorker()
		go r.runTickLoop()
	}
	r.mu.Unlock()

	if store != nil {
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
			defer cancel()
			_ = store.SaveMatchMeta(ctx, matchID, code, seed, aiCount, snapPlayers, opts, PhasePlaying)
		}()
	}

	r.broadcastBytes(beginMsg)
	r.broadcastBytes(lobbyMsg)
}

func (r *Room) runPersistWorker() {
	for {
		select {
		case batch := <-r.persistCh:
			if r.Store != nil && r.Store.IsDBConnected() {
				ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
				if err := r.Store.AppendBatch(ctx, r.MatchID, batch.FromTick, batch.ToTick, batch.Commands); err != nil {
					log.Printf("[DB] AppendBatch room=%s ticks=%d..%d err=%v", r.Code, batch.FromTick, batch.ToTick, err)
				}
				cancel()
			}
		case <-r.stopCh:
			return
		}
	}
}

func (r *Room) runTickLoop() {
	r.mu.Lock()
	spd := r.GameSpeed
	r.mu.Unlock()
	if spd <= 0 {
		spd = 1.0
	}
	intervalMs := (float64(TicksPerBatch) * 1000.0 / float64(TickHz)) / spd
	if intervalMs < 20.0 {
		intervalMs = 20.0
	}
	batchInterval := time.Duration(intervalMs * float64(time.Millisecond))
	ticker := time.NewTicker(batchInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			r.mu.Lock()
			if r.closed || (r.Phase != PhasePlaying) {
				r.mu.Unlock()
				if r.closed || r.Phase == PhaseFinished {
					return
				}
				continue
			}
			fromTick := r.CurrentTick + 1
			toTick := r.CurrentTick + TicksPerBatch
			r.CurrentTick = toTick

			cmds := r.PendingCmds
			if cmds == nil {
				cmds = []map[string]any{}
			}
			r.PendingCmds = nil

			rec := BatchRecord{
				FromTick: fromTick,
				ToTick:   toTick,
				Commands: cmds,
			}
			r.Batches = append(r.Batches, rec)
			payload := mustJSON(map[string]any{
				"type":      "tick_batch",
				"from_tick": fromTick,
				"to_tick":   toTick,
				"commands":  cmds,
			})
			persistable := len(cmds) > 0 || (toTick%120 == 0)
			r.mu.Unlock()

			if persistable {
				select {
				case r.persistCh <- rec:
				default:
				}
			}
			r.broadcastBytes(payload)

		case <-r.stopCh:
			return
		}
	}
}

func (r *Room) broadcastBytes(data []byte) {
	r.mu.Lock()
	targets := make([]*PlayerSlot, 0, len(r.Players)+len(r.Spectators))
	targets = append(targets, r.Players...)
	targets = append(targets, r.Spectators...)
	r.mu.Unlock()
	for _, p := range targets {
		p.Send(data)
	}
}

// Stop terminates background goroutines cleanly.
func (r *Room) Stop() {
	r.mu.Lock()
	if !r.closed {
		r.closed = true
		close(r.stopCh)
	}
	r.mu.Unlock()
}

// RoomManager coordinates active multiplayer rooms and idle cleanup.
type RoomManager struct {
	mu      sync.Mutex
	rooms   map[string]*Room
	store   *MatchStore
	acctSvc *AccountService
}

// NewRoomManager initializes a RoomManager.
func NewRoomManager(store *MatchStore) *RoomManager {
	return &RoomManager{
		rooms: make(map[string]*Room),
		store: store,
	}
}

// SetAccountService links an AccountService to newly created rooms for post-match stats.
func (rm *RoomManager) SetAccountService(acct *AccountService) {
	rm.mu.Lock()
	rm.acctSvc = acct
	rm.mu.Unlock()
}

// CreateOrGetRoom returns an existing room by normalized code or allocates a fresh one.
func (rm *RoomManager) CreateOrGetRoom(requestedCode string) (*Room, error) {
	rm.mu.Lock()
	defer rm.mu.Unlock()

	code := strings.ToUpper(strings.TrimSpace(requestedCode))
	if code == "" {
		for i := 0; i < 8; i++ {
			cand := generateRoomCode()
			if _, exists := rm.rooms[cand]; !exists {
				code = cand
				break
			}
		}
	}
	if len(code) > 12 {
		code = code[:12]
	}
	if existing, ok := rm.rooms[code]; ok {
		return existing, nil
	}
	if len(rm.rooms) >= MaxRooms {
		return nil, errServerFull
	}
	room := NewRoom(code, rm.store, rm.acctSvc)
	rm.rooms[code] = room
	return room, nil
}

// QuickPlayRoom returns the fullest joinable public LOBBY room or creates a new public room.
func (rm *RoomManager) QuickPlayRoom() (*Room, error) {
	rm.mu.Lock()
	var best *Room
	bestCount := -1
	for _, r := range rm.rooms {
		r.mu.Lock()
		joinable := !r.closed && r.IsPublic && r.Phase == PhaseLobby && len(r.Players) < MaxPlayersPerRoom
		cnt := len(r.Players)
		r.mu.Unlock()
		if joinable && cnt > bestCount {
			best = r
			bestCount = cnt
		}
	}
	rm.mu.Unlock()
	if best != nil {
		return best, nil
	}
	return rm.CreateOrGetRoom("")
}

// FindJoinableRoomForUser returns the room code if username is currently connected to a LOBBY room.
func (rm *RoomManager) FindJoinableRoomForUser(username string) string {
	target := strings.ToLower(strings.TrimSpace(username))
	if target == "" {
		return ""
	}
	rm.mu.Lock()
	defer rm.mu.Unlock()
	for _, r := range rm.rooms {
		r.mu.Lock()
		found := false
		if !r.closed && r.Phase == PhaseLobby && len(r.Players) < MaxPlayersPerRoom {
			for _, p := range r.Players {
				if p.Connected && strings.EqualFold(p.AccountUser, target) {
					found = true
					break
				}
			}
		}
		code := r.Code
		r.mu.Unlock()
		if found {
			return code
		}
	}
	return ""
}

// ListRooms returns public summaries for active rooms.
func (rm *RoomManager) ListRooms() []map[string]any {
	rm.mu.Lock()
	list := make([]*Room, 0, len(rm.rooms))
	for _, r := range rm.rooms {
		list = append(list, r)
	}
	rm.mu.Unlock()

	out := make([]map[string]any, 0, len(list))
	for _, r := range list {
		out = append(out, r.Summary())
	}
	return out
}

// RoomCount returns total active room count.
func (rm *RoomManager) RoomCount() int {
	rm.mu.Lock()
	defer rm.mu.Unlock()
	return len(rm.rooms)
}

// StartJanitor periodically closes rooms that have had zero connected players for over 2 minutes.
func (rm *RoomManager) StartJanitor(stopCh <-chan struct{}) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			rm.mu.Lock()
			cutoff := time.Now().Add(-2 * time.Minute)
			var expired []*Room
			for code, r := range rm.rooms {
				r.mu.Lock()
				anyConn := false
				for _, p := range r.Players {
					if p.Connected {
						anyConn = true
						break
					}
				}
				stale := !anyConn && r.LastActivity.Before(cutoff)
				r.mu.Unlock()
				if stale {
					expired = append(expired, r)
					delete(rm.rooms, code)
				}
			}
			rm.mu.Unlock()
			for _, r := range expired {
				r.Stop()
			}
		case <-stopCh:
			rm.StopAll()
			return
		}
	}
}

// StopAll closes all active rooms cleanly on server shutdown.
func (rm *RoomManager) StopAll() {
	rm.mu.Lock()
	list := make([]*Room, 0, len(rm.rooms))
	for _, r := range rm.rooms {
		list = append(list, r)
	}
	rm.rooms = make(map[string]*Room)
	rm.mu.Unlock()
	for _, r := range list {
		r.Stop()
	}
}

func mustJSON(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

var (
	errRoomClosed      = errorString("room is closed")
	errMatchInProgress = errorString("match already started")
	errRoomFull        = errorString("room is full")
	errServerFull      = errorString("server room capacity reached")
)

type errorString string

func (e errorString) Error() string { return string(e) }
