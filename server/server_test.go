package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/color"
	"image/gif"
	"image/png"
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
		"type": "expand_to", "x": 2500, "y": 100,
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

func postJSONTest(t *testing.T, url, token string, body any) (int, map[string]any) {
	t.Helper()
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST %s failed: %v", url, err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

func getJSONTest(t *testing.T, url, token string) (int, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET %s failed: %v", url, err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

func TestAccountFriendsSearchPresenceAndAvatar(t *testing.T) {
	store, err := NewMatchStore(t.Context(), "")
	if err != nil {
		t.Fatalf("NewMatchStore failed: %v", err)
	}
	acct := NewAccountService(store)
	rm := NewRoomManager(store)
	defer rm.StopAll()

	srv := httptest.NewServer(newServerMux(rm, store, acct))
	defer srv.Close()

	// 1. Register permanent usernames (case-insensitive unique check)
	st, rAlice := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "Alice", "password": "secret1"})
	if st != http.StatusCreated {
		t.Fatalf("register Alice failed: status=%d body=%v", st, rAlice)
	}
	tokAlice := rAlice["token"].(string)

	stDup, _ := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "alice", "password": "secret1"})
	if stDup != http.StatusConflict {
		t.Fatalf("expected 409 conflict for duplicate case-insensitive username, got %d", stDup)
	}

	stWrong, _ := postJSONTest(t, srv.URL+"/api/auth/login", "", map[string]any{"username": "Alice", "password": "bad"})
	if stWrong != http.StatusUnauthorized {
		t.Fatalf("expected 401 on wrong password, got %d", stWrong)
	}

	_, rBob := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "Bob", "password": "secret2"})
	tokBob := rBob["token"].(string)
	_, rCharlie := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "Charlie", "password": "secret3"})
	tokCharlie := rCharlie["token"].(string)
	_, rDave := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "Dave", "password": "secret4"})
	tokDave := rDave["token"].(string)

	// 2. DB Player Search verification
	stS, sRes := getJSONTest(t, srv.URL+"/api/users/search?q=bo", tokAlice)
	users, _ := sRes["users"].([]any)
	if stS != http.StatusOK || len(users) != 1 || users[0].(map[string]any)["username"] != "Bob" {
		t.Fatalf("expected search 'bo' -> [Bob], got status=%d users=%v", stS, users)
	}
	_, sNone := getJSONTest(t, srv.URL+"/api/users/search?q=nobody_xyz", tokAlice)
	if len(sNone["users"].([]any)) != 0 {
		t.Fatalf("expected empty search result for unknown player")
	}

	// 3. Friend requests & acceptance
	stNF, _ := postJSONTest(t, srv.URL+"/api/friends/request", tokAlice, map[string]any{"username": "GhostUser"})
	if stNF != http.StatusNotFound {
		t.Fatalf("expected 404 adding non-existent user, got %d", stNF)
	}
	postJSONTest(t, srv.URL+"/api/friends/request", tokAlice, map[string]any{"username": "Bob"})
	postJSONTest(t, srv.URL+"/api/friends/request", tokAlice, map[string]any{"username": "Charlie"})
	postJSONTest(t, srv.URL+"/api/friends/request", tokAlice, map[string]any{"username": "Dave"})

	postJSONTest(t, srv.URL+"/api/friends/respond", tokBob, map[string]any{"username": "Alice", "accept": true})
	postJSONTest(t, srv.URL+"/api/friends/respond", tokCharlie, map[string]any{"username": "Alice", "accept": true})
	postJSONTest(t, srv.URL+"/api/friends/respond", tokDave, map[string]any{"username": "Alice", "accept": true})

	// 4. Online -> most recent offline -> longest offline sorting
	now := time.Now().UTC()
	acct.mu.Lock()
	acct.accounts["bob"].LastSeenAt = now
	acct.accounts["charlie"].LastSeenAt = now.Add(-5 * time.Minute)
	acct.accounts["dave"].LastSeenAt = now.Add(-72 * time.Hour)
	acct.mu.Unlock()

	_, ov := getJSONTest(t, srv.URL+"/api/friends", tokAlice)
	frList, _ := ov["friends"].([]any)
	if len(frList) != 3 {
		t.Fatalf("expected 3 friends, got %d", len(frList))
	}
	gotOrder := []string{
		frList[0].(map[string]any)["username"].(string),
		frList[1].(map[string]any)["username"].(string),
		frList[2].(map[string]any)["username"].(string),
	}
	if gotOrder[0] != "Bob" || gotOrder[1] != "Charlie" || gotOrder[2] != "Dave" {
		t.Fatalf("expected [Bob (online), Charlie (5m ago), Dave (3d ago)], got %v", gotOrder)
	}
	if !frList[0].(map[string]any)["online"].(bool) || frList[1].(map[string]any)["online"].(bool) {
		t.Fatalf("expected Bob online=true and Charlie online=false")
	}

	// 5. Animated GIF PFP upload -> decoded 2-frame 128x64 PNG strip
	pal := color.Palette{color.RGBA{255, 0, 0, 255}, color.RGBA{0, 255, 0, 255}}
	f0 := image.NewPaletted(image.Rect(0, 0, 16, 16), pal)
	f1 := image.NewPaletted(image.Rect(0, 0, 16, 16), pal)
	for i := range f1.Pix {
		f1.Pix[i] = 1
	}
	var gifBuf bytes.Buffer
	if err := gif.EncodeAll(&gifBuf, &gif.GIF{Image: []*image.Paletted{f0, f1}, Delay: []int{12, 12}}); err != nil {
		t.Fatalf("gif encode failed: %v", err)
	}
	reqUp, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/profile/avatar", bytes.NewReader(gifBuf.Bytes()))
	reqUp.Header.Set("Authorization", "Bearer "+tokAlice)
	respUp, err := http.DefaultClient.Do(reqUp)
	if err != nil || respUp.StatusCode != http.StatusOK {
		t.Fatalf("avatar upload failed: err=%v status=%v", err, respUp)
	}
	var upBody map[string]any
	_ = json.NewDecoder(respUp.Body).Decode(&upBody)
	_ = respUp.Body.Close()
	userObj := upBody["user"].(map[string]any)
	if int(userObj["avatar_frames"].(float64)) != 2 {
		t.Fatalf("expected 2 avatar frames, got %v", userObj["avatar_frames"])
	}
	stripBytes, err := base64.StdEncoding.DecodeString(userObj["avatar_b64"].(string))
	if err != nil {
		t.Fatalf("decode avatar_b64 failed: %v", err)
	}
	stripImg, err := png.Decode(bytes.NewReader(stripBytes))
	if err != nil || stripImg.Bounds().Dx() != 128 || stripImg.Bounds().Dy() != 64 {
		t.Fatalf("expected 128x64 strip PNG, got err=%v bounds=%v", err, stripImg.Bounds())
	}

	// Verify /api/avatar/Alice serves same 2-frame PFP publicly
	stAv, avRes := getJSONTest(t, srv.URL+"/api/avatar/Alice", "")
	if stAv != http.StatusOK || int(avRes["user"].(map[string]any)["avatar_frames"].(float64)) != 2 {
		t.Fatalf("GET /api/avatar/Alice failed: %d %v", stAv, avRes)
	}
}

func TestQuickPlayTeamsPingsAndProfileStats(t *testing.T) {
	store, err := NewMatchStore(t.Context(), "")
	if err != nil {
		t.Fatalf("NewMatchStore failed: %v", err)
	}
	acct := NewAccountService(store)
	rm := NewRoomManager(store)
	defer rm.StopAll()

	srv := httptest.NewServer(newServerMux(rm, store, acct))
	defer srv.Close()

	_, r1 := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "AlphaCmd", "password": "pass123"})
	_, r2 := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "BravoCmd", "password": "pass456"})
	tok1 := r1["token"].(string)
	tok2 := r2["token"].(string)

	// Host joins room QP101 via WS -> QuickPlay & Friends CurrentRoom should discover it
	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws?room=QP101&name=AlphaCmd&account_token=" + tok1
	c1, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial c1: %v", err)
	}
	defer c1.Close()
	readMsgType(t, c1, "lobby_state")

	// QuickPlay returns existing joinable room QP101
	stQP, qpRes := postJSONTest(t, srv.URL+"/api/rooms/quickplay", "", map[string]any{})
	if stQP != http.StatusOK || qpRes["room_code"] != "QP101" {
		t.Fatalf("expected QuickPlay -> QP101, got status=%d res=%v", stQP, qpRes)
	}

	// Host enables team_mode & sets team_id=2
	_ = c1.WriteJSON(map[string]any{"type": "set_room_options", "is_public": true, "team_mode": true})
	_ = c1.WriteJSON(map[string]any{"type": "set_team", "team_id": 2})
	lobbyMsg := readMsgType(t, c1, "lobby_state")
	for i := 0; i < 3; i++ {
		if b, ok := lobbyMsg["team_mode"].(bool); ok && b {
			pls := lobbyMsg["players"].([]any)
			if int(pls[0].(map[string]any)["team_id"].(float64)) == 2 {
				break
			}
		}
		lobbyMsg = readMsgType(t, c1, "lobby_state")
	}
	if !lobbyMsg["team_mode"].(bool) || int(lobbyMsg["players"].([]any)[0].(map[string]any)["team_id"].(float64)) != 2 {
		t.Fatalf("team_mode or team_id not reflected in lobby_state: %v", lobbyMsg)
	}

	// Make AlphaCmd & BravoCmd friends -> Bravo sees AlphaCmd's current_room = "QP101"
	postJSONTest(t, srv.URL+"/api/friends/request", tok1, map[string]any{"username": "BravoCmd"})
	postJSONTest(t, srv.URL+"/api/friends/respond", tok2, map[string]any{"username": "AlphaCmd", "accept": true})
	_, ov2 := getJSONTest(t, srv.URL+"/api/friends", tok2)
	fr2 := ov2["friends"].([]any)[0].(map[string]any)
	if fr2["current_room"] != "QP101" {
		t.Fatalf("expected friend current_room=QP101, got %v", fr2)
	}

	// Start match, send map_ping, finish match, and verify ELO & win increment
	_ = c1.WriteJSON(map[string]any{"type": "start_match", "ai_count": 2})
	readMsgType(t, c1, "spawn_phase")
	_ = c1.WriteJSON(map[string]any{"type": "map_ping", "x": 400, "y": 250, "kind": "defend"})
	pingEvt := readMsgType(t, c1, "map_ping")
	if pingEvt["kind"] != "defend" || int(pingEvt["x"].(float64)) != 400 {
		t.Fatalf("unexpected map_ping broadcast: %v", pingEvt)
	}
	_ = c1.WriteJSON(map[string]any{"type": "pick_spawn", "x": 300, "y": 200})
	readMsgType(t, c1, "match_begin")

	_ = c1.WriteJSON(map[string]any{
		"type":             "match_over",
		"winner_nation_id": 1,
		"winner_team_id":   2,
		"territory_pcts":   map[string]any{"1": 81.4},
	})
	time.Sleep(80 * time.Millisecond)

	_, me1 := getJSONTest(t, srv.URL+"/api/auth/me", tok1)
	u1 := me1["user"].(map[string]any)
	// Expected Elo: 1000 -> +18 (K=36 * 0.5) + round(81.4/12)=7 => 1025, Silver III (Silver tier, win_rate=100)
	if int(u1["wins"].(float64)) != 1 || int(u1["elo"].(float64)) != 1025 || u1["rank_title"] != "Silver III" || u1["rank_tier"] != "Silver" {
		t.Fatalf("expected updated match stats (wins=1, elo=1025, Silver III), got %v", u1)
	}

	_, lbWins := getJSONTest(t, srv.URL+"/api/leaderboard?sort=wins", "")
	_, lbTerr := getJSONTest(t, srv.URL+"/api/leaderboard?sort=territory", "")
	if len(lbWins["leaderboard"].([]any)) == 0 || len(lbTerr["leaderboard"].([]any)) == 0 {
		t.Fatalf("expected non-empty sorted leaderboards")
	}
}

func TestLeaderboardReplaysModifiersChatSpectateAndChangePassword(t *testing.T) {
	store, err := NewMatchStore(t.Context(), "")
	if err != nil {
		t.Fatalf("NewMatchStore failed: %v", err)
	}
	acct := NewAccountService(store)
	rm := NewRoomManager(store)
	defer rm.StopAll()

	srv := httptest.NewServer(newServerMux(rm, store, acct))
	defer srv.Close()

	_, r1 := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "ChampOne", "password": "oldpass1"})
	tok1 := r1["token"].(string)
	_, r2 := postJSONTest(t, srv.URL+"/api/auth/register", "", map[string]any{"username": "ChallengerTwo", "password": "pass2222"})
	tok2 := r2["token"].(string)

	// 1. ChangePassword check
	stBadPW, _ := postJSONTest(t, srv.URL+"/api/auth/change_password", tok1, map[string]any{"current_password": "wrong", "new_password": "newpass9"})
	if stBadPW == http.StatusOK {
		t.Fatalf("expected wrong current password to fail")
	}
	stOKPW, _ := postJSONTest(t, srv.URL+"/api/auth/change_password", tok1, map[string]any{"current_password": "oldpass1", "new_password": "newpass9"})
	if stOKPW != http.StatusOK {
		t.Fatalf("expected password change to succeed, got %d", stOKPW)
	}
	stLoginNew, loginBody := postJSONTest(t, srv.URL+"/api/auth/login", "", map[string]any{"username": "ChampOne", "password": "newpass9"})
	if stLoginNew != http.StatusOK {
		t.Fatalf("expected login with updated password to succeed, got %d", stLoginNew)
	}
	tok1 = loginBody["token"].(string)

	// 2. Host creates room, enables team_mode + modifiers, second player joins same team
	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	c1, _, err := websocket.DefaultDialer.Dial(wsURL+"?room=MOD99&account_token="+tok1, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c1.Close()
	readMsgType(t, c1, "connected")
	readMsgType(t, c1, "lobby_state")

	c2, _, err := websocket.DefaultDialer.Dial(wsURL+"?room=MOD99&account_token="+tok2, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c2.Close()
	readMsgType(t, c2, "connected")
	readMsgType(t, c2, "lobby_state")

	_ = c1.WriteJSON(map[string]any{
		"type":          "set_room_options",
		"is_public":     true,
		"team_mode":     true,
		"game_speed":    2.0,
		"no_nukes":      true,
		"ai_difficulty": "hard",
		"start_preset":  "fast",
	})
	_ = c1.WriteJSON(map[string]any{"type": "set_team", "team_id": 1})
	_ = c2.WriteJSON(map[string]any{"type": "set_team", "team_id": 1})
	time.Sleep(40 * time.Millisecond)

	// Drain until match_begin with modifiers
	_ = c1.WriteJSON(map[string]any{"type": "start_match", "ai_count": 2})
	readMsgType(t, c1, "spawn_phase")
	_ = c1.WriteJSON(map[string]any{"type": "pick_spawn", "x": 200, "y": 200})
	_ = c2.WriteJSON(map[string]any{"type": "pick_spawn", "x": 300, "y": 250})
	mb := readMsgType(t, c1, "match_begin")
	opts, _ := mb["options"].(map[string]any)
	if opts == nil || opts["no_nukes"] != true || opts["ai_difficulty"] != "hard" || opts["game_speed"].(float64) != 2.0 {
		t.Fatalf("expected modifiers in match_begin, got %v", mb)
	}
	readMsgType(t, c2, "match_begin")

	// 3. Team chat check
	_ = c1.WriteJSON(map[string]any{"type": "chat_msg", "channel": "team", "text": "Rush Europe"})
	chatEv := readMsgType(t, c2, "chat_msg")
	if chatEv["channel"] != "team" || chatEv["text"] != "Rush Europe" {
		t.Fatalf("unexpected team chat event: %v", chatEv)
	}

	// 4. Live spectator joins mid-match and receives spectator snapshot + does not disrupt match
	spec, _, err := websocket.DefaultDialer.Dial(wsURL+"?room=MOD99&spectate=1&name=Watcher", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer spec.Close()
	sConn := readMsgType(t, spec, "connected")
	if sConn["spectator"] != true {
		t.Fatalf("expected spectator=true in connected envelope: %v", sConn)
	}
	readMsgType(t, spec, "match_snapshot")

	// Finish match & verify leaderboard, my matches, and replay endpoint
	_ = c1.WriteJSON(map[string]any{
		"type":             "match_over",
		"winner_nation_id": 1,
		"winner_team_id":   1,
		"territory_pcts":   map[string]any{"1": 52.0, "2": 31.0},
	})
	time.Sleep(100 * time.Millisecond)

	stLB, lbBody := getJSONTest(t, srv.URL+"/api/leaderboard?limit=10", "")
	lbList, _ := lbBody["leaderboard"].([]any)
	if stLB != http.StatusOK || len(lbList) < 2 {
		t.Fatalf("expected leaderboard entries, got status=%d body=%v", stLB, lbBody)
	}

	stHist, histBody := getJSONTest(t, srv.URL+"/api/me/matches", tok1)
	mList, _ := histBody["matches"].([]any)
	if stHist != http.StatusOK || len(mList) < 1 {
		t.Fatalf("expected match history entry for ChampOne, got status=%d body=%v", stHist, histBody)
	}
	matchID := mList[0].(map[string]any)["match_id"].(string)

	stRep, repBody := getJSONTest(t, srv.URL+"/api/matches/"+matchID+"/replay", "")
	if stRep != http.StatusOK || repBody["match_id"] != matchID {
		t.Fatalf("expected replay payload for %s, got status=%d body=%v", matchID, stRep, repBody)
	}
}

func TestDuplicateJoinPreventedAndHostLeaveDisbandsRoom(t *testing.T) {
	store, err := NewMatchStore(t.Context(), "")
	if err != nil {
		t.Fatalf("NewMatchStore failed: %v", err)
	}
	acct := NewAccountService(store)
	rm := NewRoomManager(store)
	defer rm.StopAll()

	srv := httptest.NewServer(newServerMux(rm, store, acct))
	defer srv.Close()

	// 1. Spam-joining the same room with same guest name or authenticated account does not create duplicate slots
	rmTest, _ := rm.CreateOrGetRoom("SPAM1")
	s1, cid1, _, err := rmTest.JoinWithSession("SpamUser", "", "SpamUser", func([]byte) {}, nil)
	if err != nil || s1 == nil || cid1 == 0 {
		t.Fatalf("first join failed: %v", err)
	}
	s2, cid2, reconn, err := rmTest.JoinWithSession("SpamUser", "", "SpamUser", func([]byte) {}, nil)
	if err != nil || !reconn || s2 != s1 || cid2 == cid1 {
		t.Fatalf("expected second join to deduplicate onto same slot: reconn=%v same=%v cid1=%d cid2=%d err=%v", reconn, s2 == s1, cid1, cid2, err)
	}
	rmTest.mu.Lock()
	slotCount := len(rmTest.Players)
	rmTest.mu.Unlock()
	if slotCount != 1 {
		t.Fatalf("expected 1 player slot after duplicate join, got %d", slotCount)
	}
	rm.RemoveRoom("SPAM1")

	// 2. Host disconnect in LOBBY disbands room with room_disbanded notification and deletes room
	wsBase := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws?room=DISB1&name="
	hostConn, _, err := websocket.DefaultDialer.Dial(wsBase+"LeaderOne", nil)
	if err != nil {
		t.Fatalf("dial host failed: %v", err)
	}
	defer hostConn.Close()
	_ = readMsgType(t, hostConn, "connected")

	guestConn, _, err := websocket.DefaultDialer.Dial(wsBase+"GuestTwo", nil)
	if err != nil {
		t.Fatalf("dial guest failed: %v", err)
	}
	defer guestConn.Close()
	_ = readMsgType(t, guestConn, "connected")

	_ = hostConn.Close()
	disb := readMsgType(t, guestConn, "room_disbanded")
	if disb["room_code"] != "DISB1" || !strings.Contains(strings.ToLower(disb["reason"].(string)), "disbanded") {
		t.Fatalf("expected room_disbanded payload with reason, got %v", disb)
	}
	time.Sleep(80 * time.Millisecond)
	if rm.RoomCount() != 0 {
		t.Fatalf("expected disbanded room removed from RoomManager, still have %d", rm.RoomCount())
	}
}
