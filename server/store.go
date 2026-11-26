package main

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// MatchStore optionally persists match headers and tick command batches to PostgreSQL.
type MatchStore struct {
	pool *pgxpool.Pool
}

// NewMatchStore connects to PostgreSQL when databaseURL is non-empty and runs idempotent migrations.
func NewMatchStore(ctx context.Context, databaseURL string) (*MatchStore, error) {
	if databaseURL == "" {
		return &MatchStore{}, nil
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
	);`
	if _, err := pool.Exec(pCtx, ddl); err != nil {
		pool.Close()
		return nil, err
	}
	return &MatchStore{pool: pool}, nil
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
	if !s.IsDBConnected() {
		return nil
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO matches (id, room_code, seed, status)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, updated_at = NOW()`,
		matchID, roomCode, seed, status,
	)
	return err
}

// AppendBatch stores a command batch in match_batches cleanly.
func (s *MatchStore) AppendBatch(ctx context.Context, matchID string, fromTick, toTick int, cmds []map[string]any) error {
	if !s.IsDBConnected() {
		return nil
	}
	if cmds == nil {
		cmds = []map[string]any{}
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
	if !s.IsDBConnected() {
		return nil
	}
	_, err := s.pool.Exec(ctx, `
		UPDATE matches SET status = $2, winner_nation_id = $3, updated_at = NOW()
		WHERE id = $1`,
		matchID, status, winnerNationID,
	)
	return err
}
