package main

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// MatchHistoryEntry represents one completed or active match summary for a player.
type MatchHistoryEntry struct {
	MatchID        string  `json:"match_id"`
	RoomCode       string  `json:"room_code"`
	Seed           int64   `json:"seed"`
	Status         string  `json:"status"`
	WinnerNationID int     `json:"winner_nation_id"`
	WinnerTeamID   int     `json:"winner_team_id"`
	TerritoryPct   float64 `json:"territory_pct"`
	Won            bool    `json:"won"`
	PlayerCount    int     `json:"player_count"`
	AICount        int     `json:"ai_count"`
	CreatedAtUnix  int64   `json:"created_at_unix"`
}

// MatchReplayDTO contains deterministic match parameters and batches for replays.
type MatchReplayDTO struct {
	MatchID        string         `json:"match_id"`
	RoomCode       string         `json:"room_code"`
	Seed           int64          `json:"seed"`
	Status         string         `json:"status"`
	WinnerNationID int            `json:"winner_nation_id"`
	WinnerTeamID   int            `json:"winner_team_id"`
	AICount        int            `json:"ai_count"`
	Players        []any          `json:"players"`
	Options        map[string]any `json:"options"`
	Batches        []BatchRecord  `json:"batches"`
	CreatedAtUnix  int64          `json:"created_at_unix"`
}

// MatchStore optionally persists match headers and tick command batches to PostgreSQL,
// with an in-memory replay and match-history ring buffer fallback when DB is disabled.
type MatchStore struct {
	pool        *pgxpool.Pool
	memMu       sync.RWMutex
	memMatches  map[string]*MatchReplayDTO
	memOrder    []string
	memUserHist map[string][]MatchHistoryEntry
}

// NewMatchStore connects to PostgreSQL when databaseURL is non-empty and runs idempotent migrations.
func NewMatchStore(ctx context.Context, databaseURL string) (*MatchStore, error) {
	if databaseURL == "" {
		return &MatchStore{
			memMatches:  make(map[string]*MatchReplayDTO),
			memUserHist: make(map[string][]MatchHistoryEntry),
		}, nil
	}
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	pCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := pool.Ping(pCtx); err != nil {
		pool.Close()
		return nil, err
	}
	ddl := `
	CREATE TABLE IF NOT EXISTS matches (
		id TEXT PRIMARY KEY,
		room_code TEXT NOT NULL,
		seed BIGINT NOT NULL,
		status TEXT NOT NULL,
		winner_nation_id INT NOT NULL DEFAULT 0,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);
	CREATE TABLE IF NOT EXISTS match_batches (
		match_id TEXT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
		from_tick INT NOT NULL,
		to_tick INT NOT NULL,
		commands_json JSONB NOT NULL,
		PRIMARY KEY (match_id, from_tick)
	);
	CREATE TABLE IF NOT EXISTS accounts (
		username TEXT PRIMARY KEY,
		username_lower TEXT NOT NULL UNIQUE,
		password_hash TEXT NOT NULL,
		session_token TEXT NOT NULL DEFAULT '',
		avatar_png BYTEA,
		avatar_frames INT NOT NULL DEFAULT 1,
		avatar_delay_ms INT NOT NULL DEFAULT 100,
		avatar_hash TEXT NOT NULL DEFAULT '',
		last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);
	CREATE INDEX IF NOT EXISTS idx_accounts_token ON accounts(session_token) WHERE session_token <> '';
	CREATE TABLE IF NOT EXISTS friendships (
		requester TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
		addressee TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
		status TEXT NOT NULL,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		PRIMARY KEY (requester, addressee)
	);
	ALTER TABLE accounts ADD COLUMN IF NOT EXISTS games_played INT NOT NULL DEFAULT 0;
	ALTER TABLE accounts ADD COLUMN IF NOT EXISTS wins INT NOT NULL DEFAULT 0;
	ALTER TABLE accounts ADD COLUMN IF NOT EXISTS elo INT NOT NULL DEFAULT 1000;
	ALTER TABLE accounts ADD COLUMN IF NOT EXISTS best_territory_pct REAL NOT NULL DEFAULT 0;
	ALTER TABLE matches ADD COLUMN IF NOT EXISTS players_json JSONB NOT NULL DEFAULT '[]'::jsonb;
	ALTER TABLE matches ADD COLUMN IF NOT EXISTS ai_count INT NOT NULL DEFAULT 4;
	ALTER TABLE matches ADD COLUMN IF NOT EXISTS options_json JSONB NOT NULL DEFAULT '{}'::jsonb;
	ALTER TABLE matches ADD COLUMN IF NOT EXISTS winner_team_id INT NOT NULL DEFAULT 0;
	CREATE TABLE IF NOT EXISTS match_participants (
		match_id TEXT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
		username_lower TEXT NOT NULL,
		nation_id INT NOT NULL,
		team_id INT NOT NULL DEFAULT 0,
		territory_pct REAL NOT NULL DEFAULT 0,
		won BOOLEAN NOT NULL DEFAULT FALSE,
		PRIMARY KEY (match_id, username_lower)
	);`
	if _, err := pool.Exec(pCtx, ddl); err != nil {
		pool.Close()
		return nil, err
	}
	return &MatchStore{
		pool:        pool,
		memMatches:  make(map[string]*MatchReplayDTO),
		memUserHist: make(map[string][]MatchHistoryEntry),
	}, nil
}

// Pool exposes the underlying PostgreSQL pool (nil in memory-only mode).
func (s *MatchStore) Pool() *pgxpool.Pool {
	if s == nil {
		return nil
	}
	return s.pool
}

// IsDBConnected reports whether PostgreSQL backing is active.
func (s *MatchStore) IsDBConnected() bool {
	return s != nil && s.pool != nil
}

// Close releases the database pool.
func (s *MatchStore) Close() {
	if s != nil && s.pool != nil {
		s.pool.Close()
	}
}

// SaveMatch inserts or updates a match record.
func (s *MatchStore) SaveMatch(ctx context.Context, matchID, roomCode string, seed int64, status string) error {
	return s.SaveMatchMeta(ctx, matchID, roomCode, seed, 4, nil, nil, status)
}

// SaveMatchMeta stores full match parameters (players, AI count, modifiers) for deterministic replays.
func (s *MatchStore) SaveMatchMeta(ctx context.Context, matchID, roomCode string, seed int64, aiCount int, players, options any, status string) error {
	if s == nil {
		return nil
	}
	playersRaw, _ := json.Marshal(players)
	if len(playersRaw) == 0 {
		playersRaw = []byte("[]")
	}
	optsRaw, _ := json.Marshal(options)
	if len(optsRaw) == 0 {
		optsRaw = []byte("{}")
	}

	var plsSlice []any
	_ = json.Unmarshal(playersRaw, &plsSlice)
	var optsMap map[string]any
	_ = json.Unmarshal(optsRaw, &optsMap)
	if optsMap == nil {
		optsMap = map[string]any{}
	}

	s.memMu.Lock()
	if s.memMatches == nil {
		s.memMatches = make(map[string]*MatchReplayDTO)
	}
	rep, exists := s.memMatches[matchID]
	if !exists {
		rep = &MatchReplayDTO{
			MatchID:       matchID,
			RoomCode:      roomCode,
			Seed:          seed,
			Status:        status,
			AICount:       aiCount,
			Players:       plsSlice,
			Options:       optsMap,
			CreatedAtUnix: time.Now().UTC().Unix(),
		}
		s.memMatches[matchID] = rep
		s.memOrder = append(s.memOrder, matchID)
		if len(s.memOrder) > 64 {
			evict := s.memOrder[0]
			s.memOrder = s.memOrder[1:]
			delete(s.memMatches, evict)
		}
	} else {
		rep.Status = status
		rep.AICount = aiCount
		if len(plsSlice) > 0 {
			rep.Players = plsSlice
		}
		if len(optsMap) > 0 {
			rep.Options = optsMap
		}
	}
	s.memMu.Unlock()

	if !s.IsDBConnected() {
		return nil
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO matches (id, room_code, seed, status, ai_count, players_json, options_json)
		VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb)
		ON CONFLICT (id) DO UPDATE SET
			status = EXCLUDED.status,
			ai_count = EXCLUDED.ai_count,
			players_json = EXCLUDED.players_json,
			options_json = EXCLUDED.options_json,
			updated_at = NOW()`,
		matchID, roomCode, seed, status, aiCount, string(playersRaw), string(optsRaw),
	)
	return err
}

// AppendBatch stores a command batch in match_batches cleanly.
func (s *MatchStore) AppendBatch(ctx context.Context, matchID string, fromTick, toTick int, cmds []map[string]any) error {
	if s == nil {
		return nil
	}
	if cmds == nil {
		cmds = []map[string]any{}
	}
	s.memMu.Lock()
	if rep, ok := s.memMatches[matchID]; ok {
		rep.Batches = append(rep.Batches, BatchRecord{FromTick: fromTick, ToTick: toTick, Commands: cmds})
	}
	s.memMu.Unlock()

	if !s.IsDBConnected() {
		return nil
	}
	raw, err := json.Marshal(cmds)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO match_batches (match_id, from_tick, to_tick, commands_json)
		VALUES ($1, $2, $3, $4::jsonb)
		ON CONFLICT (match_id, from_tick) DO NOTHING`,
		matchID, fromTick, toTick, string(raw),
	)
	return err
}

// UpdateMatchWinner marks a match finished with its winning nation ID.
func (s *MatchStore) UpdateMatchWinner(ctx context.Context, matchID, status string, winnerNationID int) error {
	return s.SaveMatchOutcome(ctx, matchID, status, winnerNationID, 0, nil)
}

// SaveMatchOutcome records match winner and per-account history entries for DB and in-memory replays.
func (s *MatchStore) SaveMatchOutcome(ctx context.Context, matchID, status string, winnerNationID, winnerTeamID int, participants []MatchParticipantResult) error {
	if s == nil {
		return nil
	}
	s.memMu.Lock()
	if s.memUserHist == nil {
		s.memUserHist = make(map[string][]MatchHistoryEntry)
	}
	rep := s.memMatches[matchID]
	if rep != nil {
		rep.Status = status
		rep.WinnerNationID = winnerNationID
		rep.WinnerTeamID = winnerTeamID
	}
	for _, p := range participants {
		if p.AccountUser == "" {
			continue
		}
		lower := normalizeKey(p.AccountUser)
		won := (p.NationID == winnerNationID) || (winnerTeamID > 0 && p.TeamID == winnerTeamID)
		entry := MatchHistoryEntry{
			MatchID:        matchID,
			WinnerNationID: winnerNationID,
			WinnerTeamID:   winnerTeamID,
			Status:         status,
			TerritoryPct:   p.TerritoryPct,
			Won:            won,
			CreatedAtUnix:  time.Now().UTC().Unix(),
		}
		if rep != nil {
			entry.RoomCode = rep.RoomCode
			entry.Seed = rep.Seed
			entry.PlayerCount = len(rep.Players)
			entry.AICount = rep.AICount
			entry.CreatedAtUnix = rep.CreatedAtUnix
		}
		list := append([]MatchHistoryEntry{entry}, s.memUserHist[lower]...)
		if len(list) > 30 {
			list = list[:30]
		}
		s.memUserHist[lower] = list
	}
	s.memMu.Unlock()

	if !s.IsDBConnected() {
		return nil
	}
	if _, err := s.pool.Exec(ctx, `
		UPDATE matches SET status = $2, winner_nation_id = $3, winner_team_id = $4, updated_at = NOW()
		WHERE id = $1`,
		matchID, status, winnerNationID, winnerTeamID,
	); err != nil {
		return err
	}
	for _, p := range participants {
		if p.AccountUser == "" {
			continue
		}
		won := (p.NationID == winnerNationID) || (winnerTeamID > 0 && p.TeamID == winnerTeamID)
		_, _ = s.pool.Exec(ctx, `
			INSERT INTO match_participants (match_id, username_lower, nation_id, team_id, territory_pct, won)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (match_id, username_lower) DO UPDATE SET
				territory_pct = EXCLUDED.territory_pct,
				won = EXCLUDED.won`,
			matchID, normalizeKey(p.AccountUser), p.NationID, p.TeamID, p.TerritoryPct, won,
		)
	}
	return nil
}

// GetUserMatches returns recent matches for a username ordered newest first.
func (s *MatchStore) GetUserMatches(ctx context.Context, usernameLower string, limit int) ([]MatchHistoryEntry, error) {
	if s == nil {
		return []MatchHistoryEntry{}, nil
	}
	if limit <= 0 || limit > 40 {
		limit = 20
	}
	if !s.IsDBConnected() {
		s.memMu.RLock()
		src := s.memUserHist[usernameLower]
		if len(src) > limit {
			src = src[:limit]
		}
		out := append([]MatchHistoryEntry(nil), src...)
		s.memMu.RUnlock()
		if out == nil {
			out = []MatchHistoryEntry{}
		}
		return out, nil
	}

	rows, err := s.pool.Query(ctx, `
		SELECT m.id, m.room_code, m.seed, m.status, m.winner_nation_id, m.winner_team_id,
		       mp.territory_pct, mp.won, jsonb_array_length(m.players_json), m.ai_count,
		       EXTRACT(EPOCH FROM m.created_at)::bigint
		FROM match_participants mp
		JOIN matches m ON m.id = mp.match_id
		WHERE mp.username_lower = $1
		ORDER BY m.created_at DESC
		LIMIT $2`, usernameLower, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]MatchHistoryEntry, 0, limit)
	for rows.Next() {
		var e MatchHistoryEntry
		if err := rows.Scan(&e.MatchID, &e.RoomCode, &e.Seed, &e.Status, &e.WinnerNationID, &e.WinnerTeamID, &e.TerritoryPct, &e.Won, &e.PlayerCount, &e.AICount, &e.CreatedAtUnix); err == nil {
			out = append(out, e)
		}
	}
	return out, nil
}

// GetMatchReplay retrieves a stored deterministic match replay (seed, players, modifiers, batches).
func (s *MatchStore) GetMatchReplay(ctx context.Context, matchID string) (*MatchReplayDTO, error) {
	if s == nil || matchID == "" {
		return nil, errNotFound
	}
	if !s.IsDBConnected() {
		s.memMu.RLock()
		rep := s.memMatches[matchID]
		var cp *MatchReplayDTO
		if rep != nil {
			tmp := *rep
			tmp.Batches = append([]BatchRecord(nil), rep.Batches...)
			tmp.Players = append([]any(nil), rep.Players...)
			cp = &tmp
		}
		s.memMu.RUnlock()
		if cp == nil {
			return nil, errNotFound
		}
		return cp, nil
	}

	var rep MatchReplayDTO
	var plsRaw, optsRaw []byte
	err := s.pool.QueryRow(ctx, `
		SELECT id, room_code, seed, status, winner_nation_id, winner_team_id, ai_count, players_json, options_json, EXTRACT(EPOCH FROM created_at)::bigint
		FROM matches WHERE id = $1`, matchID,
	).Scan(&rep.MatchID, &rep.RoomCode, &rep.Seed, &rep.Status, &rep.WinnerNationID, &rep.WinnerTeamID, &rep.AICount, &plsRaw, &optsRaw, &rep.CreatedAtUnix)
	if err != nil {
		return nil, errNotFound
	}
	_ = json.Unmarshal(plsRaw, &rep.Players)
	_ = json.Unmarshal(optsRaw, &rep.Options)

	bRows, err := s.pool.Query(ctx, `SELECT from_tick, to_tick, commands_json FROM match_batches WHERE match_id = $1 ORDER BY from_tick ASC`, matchID)
	if err == nil {
		defer bRows.Close()
		for bRows.Next() {
			var br BatchRecord
			var cmdRaw []byte
			if err := bRows.Scan(&br.FromTick, &br.ToTick, &cmdRaw); err == nil {
				_ = json.Unmarshal(cmdRaw, &br.Commands)
				rep.Batches = append(rep.Batches, br)
			}
		}
	}
	return &rep, nil
}
