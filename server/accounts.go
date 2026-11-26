package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/gif"
	_ "image/jpeg"
	"image/png"
	"io"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	OnlineThreshold = 45 * time.Second
	MaxAvatarBytes  = 1572864 // 1.5 MB upload limit
	AvatarSizePx    = 64
	MaxAvatarFrames = 16
	MaxInvitesAge   = 5 * time.Minute
)

// AccountRecord represents a persistent player account.
type AccountRecord struct {
	Username         string
	UsernameLower    string
	PasswordHash     string
	SessionToken     string
	AvatarPNG        []byte
	AvatarFrames     int
	AvatarDelayMs    int
	AvatarHash       string
	GamesPlayed      int
	Wins             int
	Elo              int
	BestTerritoryPct float64
	LastSeenAt       time.Time
	CreatedAt        time.Time
}

// UserProfileDTO is the public representation of an account returned to clients.
type UserProfileDTO struct {
	Username         string  `json:"username"`
	Online           bool    `json:"online"`
	LastSeenUnix     int64   `json:"last_seen_unix"`
	LastSeenText     string  `json:"last_seen_text"`
	Relation         string  `json:"relation,omitempty"`
	AvatarHash       string  `json:"avatar_hash"`
	AvatarFrames     int     `json:"avatar_frames"`
	AvatarDelayMs    int     `json:"avatar_delay_ms"`
	AvatarB64        string  `json:"avatar_b64,omitempty"`
	GamesPlayed      int     `json:"games_played"`
	Wins             int     `json:"wins"`
	Elo              int     `json:"elo"`
	RankTitle        string  `json:"rank_title"`
	BestTerritoryPct float64 `json:"best_territory_pct"`
	CurrentRoom      string  `json:"current_room,omitempty"`
}

// MatchParticipantResult records end-of-match stats for an account player.
type MatchParticipantResult struct {
	AccountUser  string
	NationID     int
	TeamID       int
	TerritoryPct float64
}

// RoomInviteDTO represents an ephemeral live room invite from a friend.
type RoomInviteDTO struct {
	FromUsername string    `json:"from_username"`
	RoomCode     string    `json:"room_code"`
	CreatedAt    time.Time `json:"-"`
}

type memFriendship struct {
	Requester string
	Addressee string
	Status    string // "pending" or "accepted"
	UpdatedAt time.Time
}

// AccountService handles permanent accounts, DB user search, friend requests, presence sorting, and Photo/GIF PFPs.
type AccountService struct {
	mu          sync.RWMutex
	store       *MatchStore
	accounts    map[string]*AccountRecord // username_lower -> record (in-memory fallback)
	tokens      map[string]string         // session_token -> username_lower
	friendships map[string]*memFriendship // canonical key "a|b" -> friendship
	invites     map[string][]RoomInviteDTO // target username_lower -> invites
	roomLookup  func(username string) string
}

// SetRoomLookup attaches a callback returning an active joinable room code for an account username.
func (a *AccountService) SetRoomLookup(fn func(username string) string) {
	if a == nil {
		return
	}
	a.mu.Lock()
	a.roomLookup = fn
	a.mu.Unlock()
}

// NewAccountService initializes AccountService backed by MatchStore (or thread-safe memory if DB is nil).
func NewAccountService(store *MatchStore) *AccountService {
	return &AccountService{
		store:       store,
		accounts:    make(map[string]*AccountRecord),
		tokens:      make(map[string]string),
		friendships: make(map[string]*memFriendship),
		invites:     make(map[string][]RoomInviteDTO),
	}
}

func validateUsername(raw string) (string, error) {
	u := strings.TrimSpace(raw)
	if len(u) < 3 || len(u) > 20 {
		return "", errors.New("username must be 3-20 characters")
	}
	for i := 0; i < len(u); i++ {
		c := u[i]
		ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-'
		if !ok {
			return "", errors.New("username may only use letters, numbers, '_' and '-'")
		}
	}
	return u, nil
}

func pbkdf2SHA256(password, salt []byte, iter, keyLen int) []byte {
	prf := func(key, data []byte) []byte {
		h := hmac.New(sha256.New, key)
		h.Write(data)
		return h.Sum(nil)
	}
	numBlocks := (keyLen + sha256.Size - 1) / sha256.Size
	var dk []byte
	for block := 1; block <= numBlocks; block++ {
		buf := make([]byte, len(salt)+4)
		copy(buf, salt)
		buf[len(salt)] = byte(block >> 24)
		buf[len(salt)+1] = byte(block >> 16)
		buf[len(salt)+2] = byte(block >> 8)
		buf[len(salt)+3] = byte(block)
		u := prf(password, buf)
		t := make([]byte, len(u))
		copy(t, u)
		for i := 2; i <= iter; i++ {
			u = prf(password, u)
			for j := range t {
				t[j] ^= u[j]
			}
		}
		dk = append(dk, t...)
	}
	return dk[:keyLen]
}

func hashPassword(pw string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	dk := pbkdf2SHA256([]byte(pw), salt, 60000, 32)
	return fmt.Sprintf("pbkdf2$%s$%s", hex.EncodeToString(salt), hex.EncodeToString(dk)), nil
}

func verifyPassword(pw, stored string) bool {
	parts := strings.Split(stored, "$")
	if len(parts) != 3 || parts[0] != "pbkdf2" {
		return false
	}
	salt, err1 := hex.DecodeString(parts[1])
	expected, err2 := hex.DecodeString(parts[2])
	if err1 != nil || err2 != nil || len(expected) == 0 {
		return false
	}
	actual := pbkdf2SHA256([]byte(pw), salt, 60000, len(expected))
	return subtle.ConstantTimeCompare(actual, expected) == 1
}

func newSessionToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func formatLastSeen(lastSeen time.Time, online bool) string {
	if online {
		return "Online"
	}
	d := time.Since(lastSeen)
	if d < 0 {
		d = 0
	}
	if d < time.Minute {
		return "Just now"
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm ago", int(d.Minutes()))
	}
	if d < 24*time.Hour {
		return fmt.Sprintf("%dh ago", int(d.Hours()))
	}
	return fmt.Sprintf("%dd ago", int(d.Hours()/24))
}

func computeRankTitle(elo int) string {
	switch {
	case elo >= 1650:
		return "Marshal"
	case elo >= 1400:
		return "General"
	case elo >= 1200:
		return "Commander"
	case elo >= 1050:
		return "Captain"
	default:
		return "Recruit"
	}
}

func toProfileDTO(rec *AccountRecord, includeAvatarBytes bool, relation string) UserProfileDTO {
	online := time.Since(rec.LastSeenAt) <= OnlineThreshold
	frames := rec.AvatarFrames
	if frames < 1 {
		frames = 1
	}
	delay := rec.AvatarDelayMs
	if delay < 40 {
		delay = 100
	}
	elo := rec.Elo
	if elo <= 0 {
		elo = 1000
	}
	dto := UserProfileDTO{
		Username:         rec.Username,
		Online:           online,
		LastSeenUnix:     rec.LastSeenAt.Unix(),
		LastSeenText:     formatLastSeen(rec.LastSeenAt, online),
		Relation:         relation,
		AvatarHash:       rec.AvatarHash,
		AvatarFrames:     frames,
		AvatarDelayMs:    delay,
		GamesPlayed:      rec.GamesPlayed,
		Wins:             rec.Wins,
		Elo:              elo,
		RankTitle:        computeRankTitle(elo),
		BestTerritoryPct: rec.BestTerritoryPct,
	}
	if includeAvatarBytes && len(rec.AvatarPNG) > 0 {
		dto.AvatarB64 = base64.StdEncoding.EncodeToString(rec.AvatarPNG)
	}
	return dto
}

func (a *AccountService) makeDTO(rec *AccountRecord, includeAvatarBytes bool, relation string) UserProfileDTO {
	dto := toProfileDTO(rec, includeAvatarBytes, relation)
	if a != nil && dto.Online {
		a.mu.RLock()
		lookup := a.roomLookup
		a.mu.RUnlock()
		if lookup != nil {
			dto.CurrentRoom = lookup(rec.Username)
		}
	}
	return dto
}

func resizeSquare64(src image.Image) *image.NRGBA {
	b := src.Bounds()
	sw, sh := b.Dx(), b.Dy()
	side := sw
	if sh < side {
		side = sh
	}
	if side <= 0 {
		return image.NewNRGBA(image.Rect(0, 0, AvatarSizePx, AvatarSizePx))
	}
	ox := b.Min.X + (sw-side)/2
	oy := b.Min.Y + (sh-side)/2

	dst := image.NewNRGBA(image.Rect(0, 0, AvatarSizePx, AvatarSizePx))
	for y := 0; y < AvatarSizePx; y++ {
		fy := float64(oy) + (float64(y)+0.5)*float64(side)/float64(AvatarSizePx) - 0.5
		y0 := int(fy)
		y1 := y0 + 1
		wy := fy - float64(y0)
		if y0 < b.Min.Y {
			y0 = b.Min.Y
		}
		if y1 >= b.Max.Y {
			y1 = b.Max.Y - 1
		}
		for x := 0; x < AvatarSizePx; x++ {
			fx := float64(ox) + (float64(x)+0.5)*float64(side)/float64(AvatarSizePx) - 0.5
			x0 := int(fx)
			x1 := x0 + 1
			wx := fx - float64(x0)
			if x0 < b.Min.X {
				x0 = b.Min.X
			}
			if x1 >= b.Max.X {
				x1 = b.Max.X - 1
			}
			c00 := color.NRGBAModel.Convert(src.At(x0, y0)).(color.NRGBA)
			c10 := color.NRGBAModel.Convert(src.At(x1, y0)).(color.NRGBA)
			c01 := color.NRGBAModel.Convert(src.At(x0, y1)).(color.NRGBA)
			c11 := color.NRGBAModel.Convert(src.At(x1, y1)).(color.NRGBA)

			interp := func(v00, v10, v01, v11 uint8) uint8 {
				top := float64(v00)*(1-wx) + float64(v10)*wx
				bot := float64(v01)*(1-wx) + float64(v11)*wx
				v := int(top*(1-wy) + bot*wy + 0.5)
				if v < 0 {
					return 0
				}
				if v > 255 {
					return 255
				}
				return uint8(v)
			}
			dst.SetNRGBA(x, y, color.NRGBA{
				R: interp(c00.R, c10.R, c01.R, c11.R),
				G: interp(c00.G, c10.G, c01.G, c11.G),
				B: interp(c00.B, c10.B, c01.B, c11.B),
				A: interp(c00.A, c10.A, c01.A, c11.A),
			})
		}
	}
	return dst
}

// processAvatarBytes normalizes PNG, JPEG, or animated GIF uploads into a 64*N x 64 PNG frame strip.
func processAvatarBytes(raw []byte) ([]byte, int, int, string, error) {
	if len(raw) == 0 {
		return nil, 0, 0, "", errors.New("empty avatar file")
	}
	if len(raw) > MaxAvatarBytes {
		return nil, 0, 0, "", errors.New("avatar exceeds 1.5 MB limit")
	}

	var frameImgs []*image.NRGBA
	delayMs := 100

	if len(raw) >= 6 && (string(raw[:6]) == "GIF87a" || string(raw[:6]) == "GIF89a") {
		g, err := gif.DecodeAll(bytes.NewReader(raw))
		if err != nil || len(g.Image) == 0 {
			return nil, 0, 0, "", errors.New("invalid GIF image")
		}
		cw := g.Config.Width
		ch := g.Config.Height
		if cw <= 0 || ch <= 0 {
			cw = g.Image[0].Bounds().Dx()
			ch = g.Image[0].Bounds().Dy()
		}
		canvas := image.NewNRGBA(image.Rect(0, 0, cw, ch))
		prevCanvas := image.NewNRGBA(image.Rect(0, 0, cw, ch))
		composed := make([]*image.NRGBA, 0, len(g.Image))

		for i, palImg := range g.Image {
			disposal := byte(gif.DisposalNone)
			if i < len(g.Disposal) {
				disposal = g.Disposal[i]
			}
			if disposal == gif.DisposalPrevious {
				copy(prevCanvas.Pix, canvas.Pix)
			}
			draw.Draw(canvas, palImg.Bounds(), palImg, palImg.Bounds().Min, draw.Over)
			composed = append(composed, resizeSquare64(canvas))

			switch disposal {
			case gif.DisposalBackground:
				draw.Draw(canvas, palImg.Bounds(), image.Transparent, image.Point{}, draw.Src)
			case gif.DisposalPrevious:
				copy(canvas.Pix, prevCanvas.Pix)
			}
		}

		total := len(composed)
		delaySum := 0
		if total <= MaxAvatarFrames {
			frameImgs = composed
			for i := 0; i < total; i++ {
				d := 100
				if i < len(g.Delay) && g.Delay[i] > 0 {
					d = g.Delay[i] * 10
				}
				delaySum += d
			}
			delayMs = delaySum / total
		} else {
			frameImgs = make([]*image.NRGBA, MaxAvatarFrames)
			for i := 0; i < MaxAvatarFrames; i++ {
				srcIdx := i * (total - 1) / (MaxAvatarFrames - 1)
				frameImgs[i] = composed[srcIdx]
				d := 100
				if srcIdx < len(g.Delay) && g.Delay[srcIdx] > 0 {
					d = g.Delay[srcIdx] * 10
				}
				delaySum += d
			}
			delayMs = (delaySum / MaxAvatarFrames) * total / MaxAvatarFrames
		}
		if delayMs < 40 {
			delayMs = 40
		} else if delayMs > 1000 {
			delayMs = 1000
		}
	} else {
		img, _, err := image.Decode(bytes.NewReader(raw))
		if err != nil {
			return nil, 0, 0, "", errors.New("unsupported image format (use PNG, JPG, or GIF)")
		}
		frameImgs = []*image.NRGBA{resizeSquare64(img)}
		delayMs = 100
	}

	frames := len(frameImgs)
	strip := image.NewNRGBA(image.Rect(0, 0, AvatarSizePx*frames, AvatarSizePx))
	for i, fr := range frameImgs {
		r := image.Rect(i*AvatarSizePx, 0, (i+1)*AvatarSizePx, AvatarSizePx)
		draw.Draw(strip, r, fr, image.Point{}, draw.Src)
	}
	var out bytes.Buffer
	if err := png.Encode(&out, strip); err != nil {
		return nil, 0, 0, "", err
	}
	sum := sha256.Sum256(out.Bytes())
	return out.Bytes(), frames, delayMs, hex.EncodeToString(sum[:8]), nil
}

func canonicalPair(a, b string) string {
	la := normalizeKey(a)
	lb := normalizeKey(b)
	if la < lb {
		return la + "|" + lb
	}
	return lb + "|" + la
}

func normalizeKey(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

func (a *AccountService) dbPool() bool {
	return a != nil && a.store != nil && a.store.IsDBConnected()
}

// Register creates a permanent unique username & password account and issues a session token.
func (a *AccountService) Register(ctx context.Context, rawUser, password string) (string, UserProfileDTO, error) {
	username, err := validateUsername(rawUser)
	if err != nil {
		return "", UserProfileDTO{}, err
	}
	if len(password) < 4 || len(password) > 128 {
		return "", UserProfileDTO{}, errors.New("password must be 4-128 characters")
	}
	pwHash, err := hashPassword(password)
	if err != nil {
		return "", UserProfileDTO{}, err
	}
	token := newSessionToken()
	now := time.Now().UTC()
	lower := strings.ToLower(username)

	if a.dbPool() {
		tag, err := a.store.Pool().Exec(ctx, `
			INSERT INTO accounts (username, username_lower, password_hash, session_token, last_seen_at, created_at)
			VALUES ($1, $2, $3, $4, $5, $5)
			ON CONFLICT DO NOTHING`,
			username, lower, pwHash, token, now,
		)
		if err != nil {
			return "", UserProfileDTO{}, err
		}
		if tag.RowsAffected() == 0 {
			return "", UserProfileDTO{}, errUsernameTaken
		}
		rec := &AccountRecord{Username: username, UsernameLower: lower, LastSeenAt: now, AvatarFrames: 1, AvatarDelayMs: 100}
		return token, toProfileDTO(rec, false, ""), nil
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	if _, exists := a.accounts[lower]; exists {
		return "", UserProfileDTO{}, errUsernameTaken
	}
	rec := &AccountRecord{
		Username:      username,
		UsernameLower: lower,
		PasswordHash:  pwHash,
		SessionToken:  token,
		AvatarFrames:  1,
		AvatarDelayMs: 100,
		Elo:           1000,
		LastSeenAt:    now,
		CreatedAt:     now,
	}
	a.accounts[lower] = rec
	a.tokens[token] = lower
	return token, toProfileDTO(rec, false, ""), nil
}

// Login validates credentials and returns a fresh session token + full profile (including avatar).
func (a *AccountService) Login(ctx context.Context, rawUser, password string) (string, UserProfileDTO, error) {
	lower := normalizeKey(rawUser)
	if lower == "" || password == "" {
		return "", UserProfileDTO{}, errInvalidCredentials
	}
	token := newSessionToken()
	now := time.Now().UTC()

	if a.dbPool() {
		var rec AccountRecord
		err := a.store.Pool().QueryRow(ctx, `
			SELECT username, username_lower, password_hash, COALESCE(avatar_png, ''::bytea),
			       avatar_frames, avatar_delay_ms, avatar_hash, games_played, wins, elo, best_territory_pct
			FROM accounts WHERE username_lower = $1`, lower,
		).Scan(&rec.Username, &rec.UsernameLower, &rec.PasswordHash, &rec.AvatarPNG, &rec.AvatarFrames, &rec.AvatarDelayMs, &rec.AvatarHash, &rec.GamesPlayed, &rec.Wins, &rec.Elo, &rec.BestTerritoryPct)
		if err != nil || !verifyPassword(password, rec.PasswordHash) {
			return "", UserProfileDTO{}, errInvalidCredentials
		}
		_, err = a.store.Pool().Exec(ctx, `UPDATE accounts SET session_token = $2, last_seen_at = $3 WHERE username_lower = $1`, lower, token, now)
		if err != nil {
			return "", UserProfileDTO{}, err
		}
		rec.LastSeenAt = now
		return token, toProfileDTO(&rec, true, ""), nil
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	rec, ok := a.accounts[lower]
	if !ok || !verifyPassword(password, rec.PasswordHash) {
		return "", UserProfileDTO{}, errInvalidCredentials
	}
	if rec.SessionToken != "" {
		delete(a.tokens, rec.SessionToken)
	}
	rec.SessionToken = token
	rec.LastSeenAt = now
	a.tokens[token] = lower
	return token, toProfileDTO(rec, true, ""), nil
}

// Authenticate resolves a Bearer session token and optionally updates presence.
func (a *AccountService) Authenticate(ctx context.Context, token string, touchPresence bool) (*AccountRecord, error) {
	tok := strings.TrimSpace(token)
	if tok == "" {
		return nil, errUnauthorized
	}
	now := time.Now().UTC()

	if a.dbPool() {
		var rec AccountRecord
		err := a.store.Pool().QueryRow(ctx, `
			SELECT username, username_lower, COALESCE(avatar_png, ''::bytea),
			       avatar_frames, avatar_delay_ms, avatar_hash, games_played, wins, elo, best_territory_pct, last_seen_at
			FROM accounts WHERE session_token = $1`, tok,
		).Scan(&rec.Username, &rec.UsernameLower, &rec.AvatarPNG, &rec.AvatarFrames, &rec.AvatarDelayMs, &rec.AvatarHash, &rec.GamesPlayed, &rec.Wins, &rec.Elo, &rec.BestTerritoryPct, &rec.LastSeenAt)
		if err != nil {
			return nil, errUnauthorized
		}
		if touchPresence {
			_, _ = a.store.Pool().Exec(ctx, `UPDATE accounts SET last_seen_at = $2 WHERE username_lower = $1`, rec.UsernameLower, now)
			rec.LastSeenAt = now
		}
		return &rec, nil
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	lower, ok := a.tokens[tok]
	if !ok {
		return nil, errUnauthorized
	}
	rec, ok := a.accounts[lower]
	if !ok {
		return nil, errUnauthorized
	}
	if touchPresence {
		rec.LastSeenAt = now
	}
	cp := *rec
	return &cp, nil
}

// Logout invalidates the current session token.
func (a *AccountService) Logout(ctx context.Context, token string) {
	tok := strings.TrimSpace(token)
	if tok == "" {
		return
	}
	if a.dbPool() {
		_, _ = a.store.Pool().Exec(ctx, `UPDATE accounts SET session_token = '', last_seen_at = NOW() - INTERVAL '60 seconds' WHERE session_token = $1`, tok)
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if lower, ok := a.tokens[tok]; ok {
		if rec, exists := a.accounts[lower]; exists {
			rec.SessionToken = ""
			rec.LastSeenAt = time.Now().UTC().Add(-60 * time.Second)
		}
		delete(a.tokens, tok)
	}
}

// UploadAvatar processes & persists a user's Photo or Animated GIF avatar.
func (a *AccountService) UploadAvatar(ctx context.Context, username string, raw []byte) (UserProfileDTO, error) {
	pngBytes, frames, delayMs, hashHex, err := processAvatarBytes(raw)
	if err != nil {
		return UserProfileDTO{}, err
	}
	lower := normalizeKey(username)

	if a.dbPool() {
		var rec AccountRecord
		err := a.store.Pool().QueryRow(ctx, `
			UPDATE accounts
			SET avatar_png = $2, avatar_frames = $3, avatar_delay_ms = $4, avatar_hash = $5, last_seen_at = NOW()
			WHERE username_lower = $1
			RETURNING username, username_lower, COALESCE(avatar_png, ''::bytea), avatar_frames, avatar_delay_ms, avatar_hash, games_played, wins, elo, best_territory_pct, last_seen_at`,
			lower, pngBytes, frames, delayMs, hashHex,
		).Scan(&rec.Username, &rec.UsernameLower, &rec.AvatarPNG, &rec.AvatarFrames, &rec.AvatarDelayMs, &rec.AvatarHash, &rec.GamesPlayed, &rec.Wins, &rec.Elo, &rec.BestTerritoryPct, &rec.LastSeenAt)
		if err != nil {
			return UserProfileDTO{}, errNotFound
		}
		return toProfileDTO(&rec, true, ""), nil
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	rec, ok := a.accounts[lower]
	if !ok {
		return UserProfileDTO{}, errNotFound
	}
	rec.AvatarPNG = pngBytes
	rec.AvatarFrames = frames
	rec.AvatarDelayMs = delayMs
	rec.AvatarHash = hashHex
	rec.LastSeenAt = time.Now().UTC()
	return toProfileDTO(rec, true, ""), nil
}

// GetAvatar fetches any player's public avatar + presence info by username.
func (a *AccountService) GetAvatar(ctx context.Context, username string) (UserProfileDTO, error) {
	lower := normalizeKey(username)
	if lower == "" {
		return UserProfileDTO{}, errNotFound
	}
	if a.dbPool() {
		var rec AccountRecord
		err := a.store.Pool().QueryRow(ctx, `
			SELECT username, username_lower, COALESCE(avatar_png, ''::bytea), avatar_frames, avatar_delay_ms, avatar_hash, games_played, wins, elo, best_territory_pct, last_seen_at
			FROM accounts WHERE username_lower = $1`, lower,
		).Scan(&rec.Username, &rec.UsernameLower, &rec.AvatarPNG, &rec.AvatarFrames, &rec.AvatarDelayMs, &rec.AvatarHash, &rec.GamesPlayed, &rec.Wins, &rec.Elo, &rec.BestTerritoryPct, &rec.LastSeenAt)
		if err != nil {
			return UserProfileDTO{}, errNotFound
		}
		return a.makeDTO(&rec, true, ""), nil
	}
	a.mu.RLock()
	defer a.mu.RUnlock()
	rec, ok := a.accounts[lower]
	if !ok {
		return UserProfileDTO{}, errNotFound
	}
	return a.makeDTO(rec, true, ""), nil
}

// SearchUsers searches the DB/account store by case-insensitive substring/prefix to verify player existence.
func (a *AccountService) SearchUsers(ctx context.Context, selfUsername, rawQuery string) ([]UserProfileDTO, error) {
	q := normalizeKey(rawQuery)
	if q == "" {
		return []UserProfileDTO{}, nil
	}
	selfLower := normalizeKey(selfUsername)

	if a.dbPool() {
		rows, err := a.store.Pool().Query(ctx, `
			SELECT a.username, a.username_lower, COALESCE(a.avatar_png, ''::bytea),
			       a.avatar_frames, a.avatar_delay_ms, a.avatar_hash, a.games_played, a.wins, a.elo, a.best_territory_pct, a.last_seen_at,
			       COALESCE((
			           SELECT CASE
			               WHEN f.status = 'accepted' THEN 'friend'
			               WHEN LOWER(f.requester) = $1 THEN 'outgoing'
			               ELSE 'incoming'
			           END
			           FROM friendships f
			           WHERE (LOWER(f.requester) = $1 AND LOWER(f.addressee) = a.username_lower)
			              OR (LOWER(f.addressee) = $1 AND LOWER(f.requester) = a.username_lower)
			           LIMIT 1
			       ), 'none') AS rel
			FROM accounts a
			WHERE a.username_lower <> $1
			  AND a.username_lower LIKE '%' || $2 || '%'
			ORDER BY (a.username_lower = $2) DESC, (a.username_lower LIKE $2 || '%') DESC, a.username_lower ASC
			LIMIT 15`,
			selfLower, q,
		)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		out := []UserProfileDTO{}
		for rows.Next() {
			var rec AccountRecord
			var rel string
			if err := rows.Scan(&rec.Username, &rec.UsernameLower, &rec.AvatarPNG, &rec.AvatarFrames, &rec.AvatarDelayMs, &rec.AvatarHash, &rec.GamesPlayed, &rec.Wins, &rec.Elo, &rec.BestTerritoryPct, &rec.LastSeenAt, &rel); err != nil {
				return nil, err
			}
			out = append(out, a.makeDTO(&rec, true, rel))
		}
		return out, nil
	}

	a.mu.RLock()
	defer a.mu.RUnlock()
	type matchItem struct {
		rec *AccountRecord
		rel string
	}
	var matches []matchItem
	for lower, rec := range a.accounts {
		if lower == selfLower || !strings.Contains(lower, q) {
			continue
		}
		rel := "none"
		if fs, ok := a.friendships[canonicalPair(selfLower, lower)]; ok {
			if fs.Status == "accepted" {
				rel = "friend"
			} else if strings.EqualFold(fs.Requester, selfUsername) {
				rel = "outgoing"
			} else {
				rel = "incoming"
			}
		}
		matches = append(matches, matchItem{rec: rec, rel: rel})
	}
	sort.Slice(matches, func(i, j int) bool {
		li, lj := matches[i].rec.UsernameLower, matches[j].rec.UsernameLower
		ei, ej := li == q, lj == q
		if ei != ej {
			return ei
		}
		pi, pj := strings.HasPrefix(li, q), strings.HasPrefix(lj, q)
		if pi != pj {
			return pi
		}
		return li < lj
	})
	if len(matches) > 15 {
		matches = matches[:15]
	}
	out := make([]UserProfileDTO, 0, len(matches))
	for _, m := range matches {
		out = append(out, toProfileDTO(m.rec, true, m.rel))
	}
	return out, nil
}

// SendFriendRequest verifies target exists in DB and creates/auto-accepts a friendship request.
func (a *AccountService) SendFriendRequest(ctx context.Context, selfUsername, targetRaw string) (string, error) {
	targetLower := normalizeKey(targetRaw)
	selfLower := normalizeKey(selfUsername)
	if targetLower == "" || targetLower == selfLower {
		return "", errors.New("invalid target username")
	}

	if a.dbPool() {
		var targetName string
		if err := a.store.Pool().QueryRow(ctx, `SELECT username FROM accounts WHERE username_lower = $1`, targetLower).Scan(&targetName); err != nil {
			return "", errNotFound
		}
		var req, addr, st string
		err := a.store.Pool().QueryRow(ctx, `
			SELECT requester, addressee, status FROM friendships
			WHERE (LOWER(requester) = $1 AND LOWER(addressee) = $2)
			   OR (LOWER(requester) = $2 AND LOWER(addressee) = $1)
			LIMIT 1`, selfLower, targetLower,
		).Scan(&req, &addr, &st)
		if err == nil {
			if st == "accepted" {
				return "Already friends with " + targetName, nil
			}
			if strings.EqualFold(req, selfUsername) {
				return "Friend request already sent to " + targetName, nil
			}
			_, err = a.store.Pool().Exec(ctx, `
				UPDATE friendships SET status = 'accepted', updated_at = NOW()
				WHERE requester = $1 AND addressee = $2`, req, addr)
			return "Accepted friend request from " + targetName, err
		}
		_, err = a.store.Pool().Exec(ctx, `
			INSERT INTO friendships (requester, addressee, status) VALUES ($1, $2, 'pending')`,
			selfUsername, targetName,
		)
		return "Friend request sent to " + targetName, err
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	tgt, ok := a.accounts[targetLower]
	if !ok {
		return "", errNotFound
	}
	key := canonicalPair(selfLower, targetLower)
	if fs, exists := a.friendships[key]; exists {
		if fs.Status == "accepted" {
			return "Already friends with " + tgt.Username, nil
		}
		if strings.EqualFold(fs.Requester, selfUsername) {
			return "Friend request already sent to " + tgt.Username, nil
		}
		fs.Status = "accepted"
		fs.UpdatedAt = time.Now().UTC()
		return "Accepted friend request from " + tgt.Username, nil
	}
	a.friendships[key] = &memFriendship{
		Requester: selfUsername,
		Addressee: tgt.Username,
		Status:    "pending",
		UpdatedAt: time.Now().UTC(),
	}
	return "Friend request sent to " + tgt.Username, nil
}

// RespondFriendRequest accepts or declines an incoming request.
func (a *AccountService) RespondFriendRequest(ctx context.Context, selfUsername, fromRaw string, accept bool) (string, error) {
	fromLower := normalizeKey(fromRaw)
	selfLower := normalizeKey(selfUsername)
	if fromLower == "" || fromLower == selfLower {
		return "", errors.New("invalid username")
	}

	if a.dbPool() {
		if accept {
			tag, err := a.store.Pool().Exec(ctx, `
				UPDATE friendships SET status = 'accepted', updated_at = NOW()
				WHERE LOWER(requester) = $1 AND LOWER(addressee) = $2 AND status = 'pending'`,
				fromLower, selfLower,
			)
			if err != nil {
				return "", err
			}
			if tag.RowsAffected() == 0 {
				return "", errNotFound
			}
			return "Friend request accepted", nil
		}
		_, err := a.store.Pool().Exec(ctx, `
			DELETE FROM friendships WHERE LOWER(requester) = $1 AND LOWER(addressee) = $2 AND status = 'pending'`,
			fromLower, selfLower,
		)
		return "Friend request declined", err
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	key := canonicalPair(selfLower, fromLower)
	fs, ok := a.friendships[key]
	if !ok || fs.Status != "pending" || !strings.EqualFold(fs.Addressee, selfUsername) {
		return "", errNotFound
	}
	if accept {
		fs.Status = "accepted"
		fs.UpdatedAt = time.Now().UTC()
		return "Friend request accepted", nil
	}
	delete(a.friendships, key)
	return "Friend request declined", nil
}

// RemoveFriend deletes a friendship or pending request in either direction.
func (a *AccountService) RemoveFriend(ctx context.Context, selfUsername, targetRaw string) error {
	targetLower := normalizeKey(targetRaw)
	selfLower := normalizeKey(selfUsername)
	if targetLower == "" {
		return errors.New("invalid username")
	}
	if a.dbPool() {
		_, err := a.store.Pool().Exec(ctx, `
			DELETE FROM friendships
			WHERE (LOWER(requester) = $1 AND LOWER(addressee) = $2)
			   OR (LOWER(requester) = $2 AND LOWER(addressee) = $1)`,
			selfLower, targetLower,
		)
		return err
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	delete(a.friendships, canonicalPair(selfLower, targetLower))
	return nil
}

// SendRoomInvite queues a live room code invitation for an account user.
func (a *AccountService) SendRoomInvite(fromUser, targetUser, roomCode string) {
	tLower := normalizeKey(targetUser)
	code := strings.ToUpper(strings.TrimSpace(roomCode))
	if tLower == "" || code == "" {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	list := a.filterFreshInvitesLocked(tLower)
	for _, iv := range list {
		if strings.EqualFold(iv.FromUsername, fromUser) && iv.RoomCode == code {
			a.invites[tLower] = list
			return
		}
	}
	list = append(list, RoomInviteDTO{
		FromUsername: fromUser,
		RoomCode:     code,
		CreatedAt:    time.Now().UTC(),
	})
	a.invites[tLower] = list
}

func (a *AccountService) filterFreshInvitesLocked(userLower string) []RoomInviteDTO {
	raw := a.invites[userLower]
	if len(raw) == 0 {
		return []RoomInviteDTO{}
	}
	cutoff := time.Now().UTC().Add(-MaxInvitesAge)
	fresh := make([]RoomInviteDTO, 0, len(raw))
	for _, iv := range raw {
		if iv.CreatedAt.After(cutoff) {
			fresh = append(fresh, iv)
		}
	}
	a.invites[userLower] = fresh
	return fresh
}

// SortFriendsList orders ALL friends strictly: Online first (A-Z), then Offline from most recently seen down to longest offline.
func SortFriendsList(friends []UserProfileDTO) {
	sort.Slice(friends, func(i, j int) bool {
		if friends[i].Online != friends[j].Online {
			return friends[i].Online
		}
		if friends[i].Online && friends[j].Online {
			return strings.ToLower(friends[i].Username) < strings.ToLower(friends[j].Username)
		}
		if friends[i].LastSeenUnix != friends[j].LastSeenUnix {
			return friends[i].LastSeenUnix > friends[j].LastSeenUnix
		}
		return strings.ToLower(friends[i].Username) < strings.ToLower(friends[j].Username)
	})
}

// GetFriendsOverview returns sorted friends, incoming requests, outgoing requests, and room invites.
func (a *AccountService) GetFriendsOverview(ctx context.Context, selfUsername string) ([]UserProfileDTO, []UserProfileDTO, []UserProfileDTO, []RoomInviteDTO, error) {
	selfLower := normalizeKey(selfUsername)
	friends := []UserProfileDTO{}
	incoming := []UserProfileDTO{}
	outgoing := []UserProfileDTO{}

	if a.dbPool() {
		rows, err := a.store.Pool().Query(ctx, `
			SELECT f.requester, f.addressee, f.status,
			       other.username, other.username_lower, COALESCE(other.avatar_png, ''::bytea),
			       other.avatar_frames, other.avatar_delay_ms, other.avatar_hash, other.games_played, other.wins, other.elo, other.best_territory_pct, other.last_seen_at
			FROM friendships f
			JOIN accounts other ON other.username_lower = CASE
				WHEN LOWER(f.requester) = $1 THEN LOWER(f.addressee)
				ELSE LOWER(f.requester)
			END
			WHERE LOWER(f.requester) = $1 OR LOWER(f.addressee) = $1`,
			selfLower,
		)
		if err != nil {
			return nil, nil, nil, nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var req, addr, st string
			var rec AccountRecord
			if err := rows.Scan(&req, &addr, &st, &rec.Username, &rec.UsernameLower, &rec.AvatarPNG, &rec.AvatarFrames, &rec.AvatarDelayMs, &rec.AvatarHash, &rec.GamesPlayed, &rec.Wins, &rec.Elo, &rec.BestTerritoryPct, &rec.LastSeenAt); err != nil {
				return nil, nil, nil, nil, err
			}
			if st == "accepted" {
				friends = append(friends, a.makeDTO(&rec, true, "friend"))
			} else if strings.EqualFold(req, selfUsername) {
				outgoing = append(outgoing, a.makeDTO(&rec, true, "outgoing"))
			} else {
				incoming = append(incoming, a.makeDTO(&rec, true, "incoming"))
			}
		}
	} else {
		var friendRecs []*AccountRecord
		var incomingRecs []*AccountRecord
		var outgoingRecs []*AccountRecord
		a.mu.RLock()
		for _, fs := range a.friendships {
			var otherLower string
			var rel string
			if strings.EqualFold(fs.Requester, selfUsername) {
				otherLower = normalizeKey(fs.Addressee)
				if fs.Status == "accepted" {
					rel = "friend"
				} else {
					rel = "outgoing"
				}
			} else if strings.EqualFold(fs.Addressee, selfUsername) {
				otherLower = normalizeKey(fs.Requester)
				if fs.Status == "accepted" {
					rel = "friend"
				} else {
					rel = "incoming"
				}
			} else {
				continue
			}
			rec, ok := a.accounts[otherLower]
			if !ok {
				continue
			}
			cp := *rec
			switch rel {
			case "friend":
				friendRecs = append(friendRecs, &cp)
			case "incoming":
				incomingRecs = append(incomingRecs, &cp)
			case "outgoing":
				outgoingRecs = append(outgoingRecs, &cp)
			}
		}
		a.mu.RUnlock()
		for _, r := range friendRecs {
			friends = append(friends, a.makeDTO(r, true, "friend"))
		}
		for _, r := range incomingRecs {
			incoming = append(incoming, a.makeDTO(r, true, "incoming"))
		}
		for _, r := range outgoingRecs {
			outgoing = append(outgoing, a.makeDTO(r, true, "outgoing"))
		}
	}

	SortFriendsList(friends)
	a.mu.Lock()
	invites := append([]RoomInviteDTO(nil), a.filterFreshInvitesLocked(selfLower)...)
	a.mu.Unlock()
	return friends, incoming, outgoing, invites, nil
}

// RecordMatchResult updates games_played, wins, ELO, and best_territory_pct for authenticated participants.
func (a *AccountService) RecordMatchResult(ctx context.Context, players []MatchParticipantResult, winnerNationID, winnerTeamID int) {
	if a == nil || len(players) == 0 {
		return
	}
	for _, p := range players {
		lower := normalizeKey(p.AccountUser)
		if lower == "" {
			continue
		}
		won := (winnerNationID > 0 && p.NationID == winnerNationID) || (winnerTeamID > 0 && p.TeamID == winnerTeamID)
		winInc := 0
		eloDelta := -15
		if won {
			winInc = 1
			eloDelta = 25
		}
		if a.dbPool() {
			_, _ = a.store.Pool().Exec(ctx, `
				UPDATE accounts
				SET games_played = games_played + 1,
				    wins = wins + $2,
				    elo = GREATEST(800, elo + $3),
				    best_territory_pct = GREATEST(best_territory_pct, $4)
				WHERE username_lower = $1`,
				lower, winInc, eloDelta, p.TerritoryPct,
			)
			continue
		}
		a.mu.Lock()
		if rec, ok := a.accounts[lower]; ok {
			rec.GamesPlayed++
			rec.Wins += winInc
			if rec.Elo <= 0 {
				rec.Elo = 1000
			}
			rec.Elo += eloDelta
			if rec.Elo < 800 {
				rec.Elo = 800
			}
			if p.TerritoryPct > rec.BestTerritoryPct {
				rec.BestTerritoryPct = p.TerritoryPct
			}
		}
		a.mu.Unlock()
	}
}

// RegisterAccountRoutes registers all account, DB search, friends, presence, and PFP routes on mux.
func RegisterAccountRoutes(mux *http.ServeMux, svc *AccountService) {
	extractBearer := func(r *http.Request) string {
		h := strings.TrimSpace(r.Header.Get("Authorization"))
		if strings.HasPrefix(strings.ToLower(h), "bearer ") {
			return strings.TrimSpace(h[7:])
		}
		return ""
	}

	requireAuth := func(w http.ResponseWriter, r *http.Request, touch bool) *AccountRecord {
		rec, err := svc.Authenticate(r.Context(), extractBearer(r), touch)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "Sign in required"})
			return nil
		}
		return rec
	}

	mux.HandleFunc("POST /api/auth/register", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "Invalid JSON body"})
			return
		}
		tok, prof, err := svc.Register(r.Context(), body.Username, body.Password)
		if err != nil {
			code := http.StatusBadRequest
			if err == errUsernameTaken {
				code = http.StatusConflict
			}
			writeJSON(w, code, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{"token": tok, "user": prof})
	})

	mux.HandleFunc("POST /api/auth/login", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "Invalid JSON body"})
			return
		}
		tok, prof, err := svc.Login(r.Context(), body.Username, body.Password)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"token": tok, "user": prof})
	})

	mux.HandleFunc("GET /api/auth/me", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"user": toProfileDTO(rec, true, "")})
	})

	mux.HandleFunc("POST /api/auth/logout", func(w http.ResponseWriter, r *http.Request) {
		svc.Logout(r.Context(), extractBearer(r))
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})

	mux.HandleFunc("POST /api/profile/avatar", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxAvatarBytes+1024))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "Avatar payload too large (max 1.5 MB)"})
			return
		}
		// Accept either raw image bytes or JSON {"data_b64": "..."}
		trimmed := bytes.TrimSpace(raw)
		if len(trimmed) > 0 && trimmed[0] == '{' {
			var wrap struct {
				DataB64 string `json:"data_b64"`
			}
			if err := json.Unmarshal(trimmed, &wrap); err == nil && wrap.DataB64 != "" {
				dec, decErr := base64.StdEncoding.DecodeString(wrap.DataB64)
				if decErr != nil {
					writeJSON(w, http.StatusBadRequest, map[string]any{"error": "Invalid base64 image data"})
					return
				}
				raw = dec
			}
		}
		prof, err := svc.UploadAvatar(r.Context(), rec.Username, raw)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"user": prof})
	})

	mux.HandleFunc("GET /api/avatar/{username}", func(w http.ResponseWriter, r *http.Request) {
		uname := r.PathValue("username")
		prof, err := svc.GetAvatar(r.Context(), uname)
		if err != nil {
			writeJSON(w, http.StatusNotFound, map[string]any{"error": "Player not found"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"user": prof})
	})

	mux.HandleFunc("GET /api/users/search", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		q := r.URL.Query().Get("q")
		users, err := svc.SearchUsers(r.Context(), rec.Username, q)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "Search failed"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"users": users})
	})

	mux.HandleFunc("GET /api/friends", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		friends, incoming, outgoing, invites, err := svc.GetFriendsOverview(r.Context(), rec.Username)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "Failed to load friends"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"friends":           friends,
			"incoming_requests": incoming,
			"outgoing_requests": outgoing,
			"room_invites":      invites,
		})
	})

	mux.HandleFunc("POST /api/friends/request", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		var body struct {
			Username string `json:"username"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024)).Decode(&body); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "Invalid JSON body"})
			return
		}
		msg, err := svc.SendFriendRequest(r.Context(), rec.Username, body.Username)
		if err != nil {
			code := http.StatusBadRequest
			if err == errNotFound {
				code = http.StatusNotFound
			}
			writeJSON(w, code, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": msg})
	})

	mux.HandleFunc("POST /api/friends/respond", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		var body struct {
			Username string `json:"username"`
			Accept   bool   `json:"accept"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024)).Decode(&body); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "Invalid JSON body"})
			return
		}
		msg, err := svc.RespondFriendRequest(r.Context(), rec.Username, body.Username, body.Accept)
		if err != nil {
			code := http.StatusBadRequest
			if err == errNotFound {
				code = http.StatusNotFound
			}
			writeJSON(w, code, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": msg})
	})

	mux.HandleFunc("DELETE /api/friends/{username}", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		if err := svc.RemoveFriend(r.Context(), rec.Username, r.PathValue("username")); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})

	mux.HandleFunc("POST /api/friends/invite", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		var body struct {
			Username string `json:"username"`
			RoomCode string `json:"room_code"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024)).Decode(&body); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "Invalid JSON body"})
			return
		}
		svc.SendRoomInvite(rec.Username, body.Username, body.RoomCode)
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})

	mux.HandleFunc("POST /api/presence/heartbeat", func(w http.ResponseWriter, r *http.Request) {
		rec := requireAuth(w, r, true)
		if rec == nil {
			return
		}
		_, incoming, _, invites, err := svc.GetFriendsOverview(r.Context(), rec.Username)
		if err != nil {
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "incoming_requests_count": 0, "room_invites": []RoomInviteDTO{}})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":                      true,
			"incoming_requests_count": len(incoming),
			"room_invites":            invites,
		})
	})
}

var (
	errUsernameTaken      = errorString("username is already taken")
	errInvalidCredentials = errorString("invalid username or password")
	errUnauthorized       = errorString("unauthorized")
	errNotFound           = errorString("player not found")
)
