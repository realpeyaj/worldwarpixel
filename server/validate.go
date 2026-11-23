package main

import (
	"errors"
	"fmt"
	"math"
	"time"
)

const (
	SimWidth  = 1024
	SimHeight = 512
)

var allowedStructures = map[string]bool{
	"town":         true,
	"port":         true,
	"factory":      true,
	"defense_post": true,
	"missile_silo": true,
	"sam_launcher": true,
}

var allowedMissiles = map[string]bool{
	"atom":     true,
	"hydrogen": true,
	"mirv":     true,
}

// RateLimiter implements a per-client token bucket (12 cmd/s, burst 20).
type RateLimiter struct {
	tokens float64
	max    float64
	rate   float64
	last   time.Time
}

// NewRateLimiter creates a token bucket limiter.
func NewRateLimiter(ratePerSec, burst float64) *RateLimiter {
	return &RateLimiter{
		tokens: burst,
		max:    burst,
		rate:   ratePerSec,
		last:   time.Now(),
	}
}

// Allow consumes one command token if available.
func (r *RateLimiter) Allow() bool {
	now := time.Now()
	elapsed := now.Sub(r.last).Seconds()
	r.last = now
	r.tokens = math.Min(r.max, r.tokens+elapsed*r.rate)
	if r.tokens < 1.0 {
		return false
	}
	r.tokens -= 1.0
	return true
}

func asInt(v any) (int, bool) {
	switch t := v.(type) {
	case float64:
		if math.IsNaN(t) || math.IsInf(t, 0) {
			return 0, false
		}
		return int(t), true
	case int:
		return t, true
	case int64:
		return int(t), true
	}
	return 0, false
}

func asFloat(v any) (float64, bool) {
	switch t := v.(type) {
	case float64:
		if math.IsNaN(t) || math.IsInf(t, 0) {
			return 0, false
		}
		return t, true
	case int:
		return float64(t), true
	}
	return 0, false
}

func asString(v any) (string, bool) {
	s, ok := v.(string)
	return s, ok
}

func asBool(v any) (bool, bool) {
	b, ok := v.(bool)
	return b, ok
}

func validSimCoord(raw map[string]any) (int, int, error) {
	x, okX := asInt(raw["x"])
	y, okY := asInt(raw["y"])
	if !okX || !okY || x < 0 || x >= SimWidth || y < 0 || y >= SimHeight {
		return 0, 0, errors.New("coordinates out of world map bounds")
	}
	return x, y, nil
}

// ValidateAndSanitizeCommand enforces command schema bounds and pins nation_id to the sender.
func ValidateAndSanitizeCommand(nationID int, raw map[string]any) (map[string]any, error) {
	if nationID <= 0 || raw == nil {
		return nil, errors.New("invalid sender or payload")
	}
	cmdType, ok := asString(raw["type"])
	if !ok || cmdType == "" {
		return nil, errors.New("missing command type")
	}

	out := map[string]any{
		"type":      cmdType,
		"nation_id": nationID,
	}

	switch cmdType {
	case "expand_to":
		x, y, err := validSimCoord(raw)
		if err != nil {
			return nil, err
		}
		ratio := 0.35
		if rVal, hasR := raw["commit_ratio"]; hasR {
			rf, okR := asFloat(rVal)
			if !okR {
				return nil, errors.New("invalid commit_ratio")
			}
			ratio = math.Max(0.15, math.Min(0.80, rf))
		}
		out["x"] = x
		out["y"] = y
		out["commit_ratio"] = ratio

	case "cancel_expansion":
		eid, okE := asInt(raw["expansion_id"])
		if !okE || eid <= 0 {
			return nil, errors.New("invalid expansion_id")
		}
		out["expansion_id"] = eid

	case "cancel_ship":
		sid, okS := asInt(raw["ship_id"])
		if !okS || sid <= 0 {
			return nil, errors.New("invalid ship_id")
		}
		out["ship_id"] = sid

	case "build_structure":
		sType, okT := asString(raw["structure_type"])
		if !okT || !allowedStructures[sType] {
			return nil, errors.New("unsupported structure_type")
		}
		x, y, err := validSimCoord(raw)
		if err != nil {
			return nil, err
		}
		out["structure_type"] = sType
		out["x"] = x
		out["y"] = y

	case "upgrade_structure":
		sid, okS := asInt(raw["structure_id"])
		if !okS || sid <= 0 {
			return nil, errors.New("invalid structure_id")
		}
		out["structure_id"] = sid

	case "build_warship":
		pid, okP := asInt(raw["port_id"])
		if !okP || pid <= 0 {
			return nil, errors.New("invalid port_id")
		}
		out["port_id"] = pid
		if _, hasX := raw["x"]; hasX {
			x, y, err := validSimCoord(raw)
			if err != nil {
				return nil, err
			}
			out["x"] = x
			out["y"] = y
		}

	case "command_warship":
		sid, okS := asInt(raw["ship_id"])
		if !okS || sid <= 0 {
			return nil, errors.New("invalid ship_id")
		}
		x, y, err := validSimCoord(raw)
		if err != nil {
			return nil, err
		}
		out["ship_id"] = sid
		out["x"] = x
		out["y"] = y

	case "launch_missile":
		mk, okM := asString(raw["missile_kind"])
		if !okM || !allowedMissiles[mk] {
			return nil, errors.New("unsupported missile_kind")
		}
		x, y, err := validSimCoord(raw)
		if err != nil {
			return nil, err
		}
		out["missile_kind"] = mk
		out["x"] = x
		out["y"] = y
		if siloRaw, hasSilo := raw["silo_id"]; hasSilo {
			siloID, okSilo := asInt(siloRaw)
			if !okSilo || siloID < 0 {
				return nil, errors.New("invalid silo_id")
			}
			out["silo_id"] = siloID
		}

	case "request_alliance", "break_alliance", "toggle_embargo":
		tgt, okT := asInt(raw["target_nation_id"])
		if !okT || tgt <= 0 || tgt == nationID {
			return nil, errors.New("invalid target_nation_id")
		}
		out["target_nation_id"] = tgt

	case "respond_alliance":
		fromID, okF := asInt(raw["from_nation_id"])
		acc, okA := asBool(raw["accept"])
		if !okF || !okA || fromID <= 0 || fromID == nationID {
			return nil, errors.New("invalid respond_alliance payload")
		}
		out["from_nation_id"] = fromID
		out["accept"] = acc

	case "donate_gold":
		tgt, okT := asInt(raw["target_nation_id"])
		amt, okAmt := asFloat(raw["amount"])
		if !okT || !okAmt || tgt <= 0 || tgt == nationID || amt < 1000.0 || amt > 50000000.0 {
			return nil, errors.New("invalid peso donation")
		}
		out["target_nation_id"] = tgt
		out["amount"] = amt

	case "donate_troops":
		tgt, okT := asInt(raw["target_nation_id"])
		ratio, okR := asFloat(raw["ratio"])
		if !okT || !okR || tgt <= 0 || tgt == nationID {
			return nil, errors.New("invalid troop donation")
		}
		out["target_nation_id"] = tgt
		out["ratio"] = math.Max(0.10, math.Min(0.50, ratio))

	default:
		return nil, fmt.Errorf("disallowed command type: %s", cmdType)
	}

	return out, nil
}
