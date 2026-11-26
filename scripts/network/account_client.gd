class_name AccountClient
extends Node
## Client service for permanent accounts, DB user search, sorted friends list, presence heartbeats, and Photo/GIF PFPs.

const PROFILE_SAVE_PATH := "user://player_profile.cfg"
const AVATAR_CACHE_PATH := "user://custom_avatar.png"
const HEARTBEAT_INTERVAL_SEC := 15.0

signal auth_changed(logged_in: bool, username: String, message: String)
signal auth_error(message: String)
signal avatar_updated(username: String, frames: Array, delay_ms: int)
signal search_results_received(query: String, users: Array)
signal friends_overview_received(friends: Array, incoming: Array, outgoing: Array, invites: Array)
signal friend_action_result(ok: bool, message: String)
signal incoming_friend_request_notified(count: int)
signal incoming_room_invite_notified(from_name: String, room_code: String)
signal password_changed(ok: bool, message: String)
signal leaderboard_received(entries: Array)
signal my_matches_received(matches: Array)

var api_base_url: String = "http://151.242.136.18:30041"
var session_token: String = ""
var username: String = ""
var is_logged_in: bool = false

var local_avatar_frames: Array[ImageTexture] = []
var local_avatar_delay_ms: int = 100
var local_avatar_hash: String = ""
var local_stats: Dictionary = {"games_played": 0, "wins": 0, "elo": 1000, "rank_title": "Recruit", "best_territory_pct": 0.0}

var remote_avatar_cache: Dictionary = {} # username_lower -> {"frames": Array, "delay_ms": int, "hash": String}

var _heartbeat_timer: float = 2.0
var _last_seen_incoming_count: int = 0
var _seen_room_invites: Dictionary = {} # "from|code" -> true


func _ready() -> void:
	set_ws_url(MPClient.resolve_default_ws_url())
	load_saved_state()
	if not session_token.is_empty() and DisplayServer.get_name() != "headless":
		verify_session()


func set_ws_url(ws_url: String) -> void:
	var u: String = ws_url.strip_edges()
	if u.is_empty():
		u = MPClient.resolve_default_ws_url()
	u = u.replace("wss://", "https://").replace("ws://", "http://")
	if u.ends_with("/ws"):
		u = u.substr(0, u.length() - 3)
	while u.ends_with("/"):
		u = u.substr(0, u.length() - 1)
	if not u.is_empty():
		api_base_url = u


func _process(delta: float) -> void:
	if not is_logged_in or session_token.is_empty() or DisplayServer.get_name() == "headless":
		return
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = HEARTBEAT_INTERVAL_SEC
		send_heartbeat()


func load_saved_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_SAVE_PATH) == OK:
		session_token = str(cfg.get_value("account", "token", "")).strip_edges()
		username = str(cfg.get_value("account", "username", "")).strip_edges()
		local_avatar_hash = str(cfg.get_value("account", "avatar_hash", "")).strip_edges()
		var saved_frames: int = maxi(1, int(cfg.get_value("account", "avatar_frames", 1)))
		local_avatar_delay_ms = clampi(int(cfg.get_value("account", "avatar_delay_ms", 100)), 40, 1000)
		is_logged_in = (not session_token.is_empty()) and (not username.is_empty())
		if FileAccess.file_exists(AVATAR_CACHE_PATH):
			var img := Image.new()
			if img.load(AVATAR_CACHE_PATH) == OK and not img.is_empty():
				local_avatar_frames = GifDecoder.textures_from_strip_image(img, saved_frames)
	else:
		session_token = ""
		username = ""
		is_logged_in = false


func _save_account_state() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_SAVE_PATH)
	cfg.set_value("account", "token", session_token)
	cfg.set_value("account", "username", username)
	cfg.set_value("account", "avatar_hash", local_avatar_hash)
	cfg.set_value("account", "avatar_frames", maxi(1, local_avatar_frames.size()))
	cfg.set_value("account", "avatar_delay_ms", local_avatar_delay_ms)
	if not username.is_empty():
		cfg.set_value("profile", "player_name", username)
	cfg.save(PROFILE_SAVE_PATH)


func _save_local_strip_image(strip_img: Image, frames: Array[ImageTexture], delay_ms: int, hash_val: String) -> void:
	local_avatar_frames = frames
	local_avatar_delay_ms = clampi(delay_ms, 40, 1000)
	local_avatar_hash = hash_val
	if strip_img != null and not strip_img.is_empty():
		strip_img.save_png(ProjectSettings.globalize_path(AVATAR_CACHE_PATH))
	_save_account_state()
	avatar_updated.emit(username, local_avatar_frames, local_avatar_delay_ms)


func register_account(raw_user: String, password: String) -> void:
	var body := {"username": raw_user.strip_edges(), "password": password}
	_request_json("/api/auth/register", HTTPClient.METHOD_POST, body, false, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code >= 200 and code < 300 and data.has("token"):
			_apply_auth_response(data, "Account created & signed in!")
		else:
			auth_error.emit(str(data.get("error", err_msg if not err_msg.is_empty() else "Registration failed.")))
	)


func login_account(raw_user: String, password: String) -> void:
	var body := {"username": raw_user.strip_edges(), "password": password}
	_request_json("/api/auth/login", HTTPClient.METHOD_POST, body, false, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code >= 200 and code < 300 and data.has("token"):
			_apply_auth_response(data, "Signed in as %s." % str((data.get("user", {}) as Dictionary).get("username", raw_user)))
		else:
			auth_error.emit(str(data.get("error", err_msg if not err_msg.is_empty() else "Sign in failed.")))
	)


func verify_session() -> void:
	if session_token.is_empty():
		return
	_request_json("/api/auth/me", HTTPClient.METHOD_GET, {}, true, func(code: int, data: Dictionary, _err_msg: String) -> void:
		if code == 200 and data.has("user"):
			_apply_user_profile(data["user"] as Dictionary, true)
			auth_changed.emit(true, username, "Signed in as %s" % username)
			fetch_friends_overview()
		elif code == 401:
			session_token = ""
			username = ""
			is_logged_in = false
			_save_account_state()
			auth_changed.emit(false, "", "Session expired — please sign in.")
	)


func logout() -> void:
	if not session_token.is_empty():
		_request_json("/api/auth/logout", HTTPClient.METHOD_POST, {}, true, func(_c: int, _d: Dictionary, _e: String) -> void: pass)
	session_token = ""
	username = ""
	is_logged_in = false
	local_stats = {"games_played": 0, "wins": 0, "elo": 1000, "rank_title": "Recruit", "best_territory_pct": 0.0}
	_last_seen_incoming_count = 0
	_seen_room_invites.clear()
	_save_account_state()
	auth_changed.emit(false, "", "Signed out (Guest mode)")


func fetch_public_rooms(cb: Callable) -> void:
	_request_json("/api/rooms", HTTPClient.METHOD_GET, {}, false, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code == 200:
			cb.call(true, data.get("rooms", []), "")
		else:
			cb.call(false, [], str(data.get("error", err_msg if not err_msg.is_empty() else "Failed to load public rooms.")))
	)


func request_quickplay(cb: Callable) -> void:
	_request_json("/api/rooms/quickplay", HTTPClient.METHOD_POST, {}, false, func(code: int, data: Dictionary, err_msg: String) -> void:
		var rcode: String = str(data.get("room_code", "")).strip_edges().to_upper()
		if code >= 200 and code < 300 and not rcode.is_empty():
			cb.call(true, rcode, "")
		else:
			cb.call(false, "", str(data.get("error", err_msg if not err_msg.is_empty() else "Quick Play unavailable.")))
	)


func import_and_upload_avatar(file_path: String) -> void:
	var decoded: Dictionary = GifDecoder.load_avatar_from_file(file_path, 64)
	if not bool(decoded.get("ok", false)):
		friend_action_result.emit(false, str(decoded.get("error", "Invalid avatar image.")))
		return
	var strip_img: Image = decoded.get("strip_image")
	var frames: Array[ImageTexture] = []
	for t: Variant in decoded.get("frames", []):
		if t is ImageTexture:
			frames.append(t as ImageTexture)
	var delay_ms: int = int(decoded.get("delay_ms", 100))
	_save_local_strip_image(strip_img, frames, delay_ms, "local-%d" % Time.get_ticks_msec())

	if not is_logged_in or session_token.is_empty():
		friend_action_result.emit(true, "Custom PFP saved locally (sign in to sync online).")
		return

	var raw_bytes: PackedByteArray = decoded.get("raw_upload_bytes", PackedByteArray())
	var payload := {"data_b64": Marshalls.raw_to_base64(raw_bytes)}
	_request_json("/api/profile/avatar", HTTPClient.METHOD_POST, payload, true, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code >= 200 and code < 300 and data.has("user"):
			_apply_user_profile(data["user"] as Dictionary, true)
			friend_action_result.emit(true, "Custom PFP uploaded & synced!")
		else:
			friend_action_result.emit(false, str(data.get("error", err_msg if not err_msg.is_empty() else "PFP upload failed.")))
	)


func search_players(query: String) -> void:
	var q: String = query.strip_edges()
	if q.is_empty():
		search_results_received.emit("", [])
		return
	if not is_logged_in:
		friend_action_result.emit(false, "Sign in to search the player database.")
		return
	_request_json("/api/users/search?q=" + q.uri_encode(), HTTPClient.METHOD_GET, {}, true, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code == 200:
			var users: Array = data.get("users", [])
			_hydrate_user_avatars(users)
			search_results_received.emit(q, users)
		else:
			friend_action_result.emit(false, str(data.get("error", err_msg if not err_msg.is_empty() else "Player search failed.")))
	)


func fetch_friends_overview() -> void:
	if not is_logged_in or session_token.is_empty():
		friends_overview_received.emit([], [], [], [])
		return
	_request_json("/api/friends", HTTPClient.METHOD_GET, {}, true, func(code: int, data: Dictionary, _err_msg: String) -> void:
		if code == 200:
			var friends: Array = sort_friends_list(data.get("friends", []))
			var incoming: Array = data.get("incoming_requests", [])
			var outgoing: Array = data.get("outgoing_requests", [])
			var invites: Array = data.get("room_invites", [])
			_hydrate_user_avatars(friends)
			_hydrate_user_avatars(incoming)
			_check_new_notifications(incoming.size(), invites)
			friends_overview_received.emit(friends, incoming, outgoing, invites)
	)


func send_friend_request(target_username: String) -> void:
	if not is_logged_in:
		friend_action_result.emit(false, "Sign in first to add friends.")
		return
	_request_json("/api/friends/request", HTTPClient.METHOD_POST, {"username": target_username}, true, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code >= 200 and code < 300:
			friend_action_result.emit(true, str(data.get("message", "Friend request sent!")))
			fetch_friends_overview()
		else:
			friend_action_result.emit(false, str(data.get("error", err_msg if not err_msg.is_empty() else "Request failed.")))
	)


func respond_friend_request(from_username: String, accept: bool) -> void:
	if not is_logged_in:
		return
	_request_json("/api/friends/respond", HTTPClient.METHOD_POST, {"username": from_username, "accept": accept}, true, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code >= 200 and code < 300:
			friend_action_result.emit(true, str(data.get("message", "Updated request.")))
			fetch_friends_overview()
		else:
			friend_action_result.emit(false, str(data.get("error", err_msg if not err_msg.is_empty() else "Failed to respond.")))
	)


func remove_friend(target_username: String) -> void:
	if not is_logged_in:
		return
	_request_json("/api/friends/" + target_username.uri_encode(), HTTPClient.METHOD_DELETE, {}, true, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code >= 200 and code < 300:
			friend_action_result.emit(true, "Removed %s from friends." % target_username)
			fetch_friends_overview()
		else:
			friend_action_result.emit(false, str(data.get("error", err_msg if not err_msg.is_empty() else "Remove failed.")))
	)


func send_room_invite(target_username: String, room_code: String) -> void:
	if not is_logged_in or room_code.strip_edges().is_empty():
		return
	_request_json("/api/friends/invite", HTTPClient.METHOD_POST, {"username": target_username, "room_code": room_code}, true, func(_c: int, _d: Dictionary, _e: String) -> void: pass)


func send_heartbeat() -> void:
	if not is_logged_in or session_token.is_empty():
		return
	_request_json("/api/presence/heartbeat", HTTPClient.METHOD_POST, {}, true, func(code: int, data: Dictionary, _err_msg: String) -> void:
		if code == 200:
			var inc_cnt: int = int(data.get("incoming_requests_count", 0))
			var invites: Array = data.get("room_invites", [])
			var changed: bool = _check_new_notifications(inc_cnt, invites)
			if changed:
				fetch_friends_overview()
	)


func fetch_remote_avatar(acct_username: String, callback: Callable) -> void:
	var key: String = acct_username.strip_edges().to_lower()
	if key.is_empty():
		return
	if remote_avatar_cache.has(key):
		var entry: Dictionary = remote_avatar_cache[key]
		callback.call(acct_username, entry.get("frames", []), int(entry.get("delay_ms", 100)))
		return
	_request_json("/api/avatar/" + acct_username.uri_encode(), HTTPClient.METHOD_GET, {}, false, func(code: int, data: Dictionary, _err: String) -> void:
		if code == 200 and data.has("user"):
			var u: Dictionary = data["user"] as Dictionary
			var b64: String = str(u.get("avatar_b64", ""))
			if not b64.is_empty():
				var frames: Array[ImageTexture] = GifDecoder.textures_from_strip_b64(b64, int(u.get("avatar_frames", 1)))
				var dms: int = int(u.get("avatar_delay_ms", 100))
				if not frames.is_empty():
					remote_avatar_cache[key] = {"frames": frames, "delay_ms": dms, "hash": str(u.get("avatar_hash", ""))}
					callback.call(acct_username, frames, dms)
	)


func get_cached_avatar(acct_username: String) -> Dictionary:
	var key: String = acct_username.strip_edges().to_lower()
	if key == username.to_lower() and not local_avatar_frames.is_empty():
		return {"frames": local_avatar_frames, "delay_ms": local_avatar_delay_ms}
	if remote_avatar_cache.has(key):
		return remote_avatar_cache[key] as Dictionary
	return {}


static func sort_friends_list(friends: Array) -> Array:
	var out: Array = friends.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		if not (a is Dictionary) or not (b is Dictionary):
			return false
		var da := a as Dictionary
		var db := b as Dictionary
		var oa: bool = bool(da.get("online", false))
		var ob: bool = bool(db.get("online", false))
		if oa != ob:
			return oa
		var ua: String = str(da.get("username", "")).to_lower()
		var ub: String = str(db.get("username", "")).to_lower()
		if oa and ob:
			return ua < ub
		var la: int = int(da.get("last_seen_unix", 0))
		var lb: int = int(db.get("last_seen_unix", 0))
		if la != lb:
			return la > lb
		return ua < ub
	)
	return out


func _check_new_notifications(inc_count: int, invites: Array) -> bool:
	var got_new := false
	if inc_count > _last_seen_incoming_count:
		got_new = true
		incoming_friend_request_notified.emit(inc_count)
	_last_seen_incoming_count = inc_count
	for inv: Variant in invites:
		if inv is Dictionary:
			var idict := inv as Dictionary
			var from_u: String = str(idict.get("from_username", ""))
			var rcode: String = str(idict.get("room_code", ""))
			var k: String = from_u.to_lower() + "|" + rcode
			if not rcode.is_empty() and not _seen_room_invites.has(k):
				_seen_room_invites[k] = true
				got_new = true
				incoming_room_invite_notified.emit(from_u, rcode)
	return got_new


func _hydrate_user_avatars(users: Array) -> void:
	for uv: Variant in users:
		if not (uv is Dictionary):
			continue
		var u := uv as Dictionary
		var uname: String = str(u.get("username", "")).strip_edges()
		var b64: String = str(u.get("avatar_b64", ""))
		if uname.is_empty() or b64.is_empty():
			continue
		var key: String = uname.to_lower()
		var h: String = str(u.get("avatar_hash", ""))
		if remote_avatar_cache.has(key) and str((remote_avatar_cache[key] as Dictionary).get("hash", "")) == h and not h.is_empty():
			continue
		var frames: Array[ImageTexture] = GifDecoder.textures_from_strip_b64(b64, int(u.get("avatar_frames", 1)))
		if not frames.is_empty():
			remote_avatar_cache[key] = {
				"frames": frames,
				"delay_ms": clampi(int(u.get("avatar_delay_ms", 100)), 40, 1000),
				"hash": h,
			}


func _apply_auth_response(data: Dictionary, message: String) -> void:
	session_token = str(data.get("token", "")).strip_edges()
	var u: Dictionary = data.get("user", {}) as Dictionary
	_apply_user_profile(u, false)
	is_logged_in = (not session_token.is_empty()) and (not username.is_empty())
	_save_account_state()
	auth_changed.emit(is_logged_in, username, message)
	fetch_friends_overview()


func _apply_user_profile(u: Dictionary, save_state: bool) -> void:
	var uname: String = str(u.get("username", "")).strip_edges()
	if not uname.is_empty():
		username = uname
		is_logged_in = not session_token.is_empty()
	if u.has("elo") or u.has("games_played"):
		local_stats = {
			"games_played": int(u.get("games_played", 0)),
			"wins": int(u.get("wins", 0)),
			"elo": int(u.get("elo", 1000)),
			"rank_title": str(u.get("rank_title", "Recruit")),
			"best_territory_pct": float(u.get("best_territory_pct", 0.0)),
		}
	var b64: String = str(u.get("avatar_b64", ""))
	if not b64.is_empty():
		var raw: PackedByteArray = Marshalls.base64_to_raw(b64)
		var strip_img := Image.new()
		if strip_img.load_png_from_buffer(raw) == OK:
			var f_cnt: int = maxi(1, int(u.get("avatar_frames", 1)))
			var frames: Array[ImageTexture] = GifDecoder.textures_from_strip_image(strip_img, f_cnt)
			_save_local_strip_image(strip_img, frames, int(u.get("avatar_delay_ms", 100)), str(u.get("avatar_hash", "")))
			return
	if save_state:
		_save_account_state()


func change_password(cur_pass: String, new_pass: String) -> void:
	if not is_logged_in or session_token.is_empty():
		password_changed.emit(false, "Sign in required.")
		return
	var body := {"current_password": cur_pass, "new_password": new_pass}
	_request_json("/api/auth/change_password", HTTPClient.METHOD_POST, body, true, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code >= 200 and code < 300:
			password_changed.emit(true, str(data.get("message", "Password updated.")))
		else:
			password_changed.emit(false, str(data.get("error", err_msg if not err_msg.is_empty() else "Password change failed.")))
	)


func fetch_leaderboard(limit: int = 25, cb: Callable = Callable(), sort_by: String = "elo") -> void:
	var s_clean: String = sort_by.strip_edges().to_lower()
	if not (s_clean in ["elo", "wins", "territory"]):
		s_clean = "elo"
	_request_json("/api/leaderboard?limit=%d&sort=%s" % [clampi(limit, 1, 50), s_clean], HTTPClient.METHOD_GET, {}, false, func(code: int, data: Dictionary, _err_msg: String) -> void:
		var arr: Array = data.get("leaderboard", []) as Array if (code >= 200 and code < 300 and data.get("leaderboard") is Array) else []
		leaderboard_received.emit(arr)
		if cb.is_valid():
			cb.call(code >= 200 and code < 300, arr)
	)


func fetch_my_matches(limit: int = 20, cb: Callable = Callable()) -> void:
	if not is_logged_in or session_token.is_empty():
		my_matches_received.emit([])
		if cb.is_valid():
			cb.call(false, [])
		return
	_request_json("/api/me/matches?limit=%d" % clampi(limit, 1, 40), HTTPClient.METHOD_GET, {}, true, func(code: int, data: Dictionary, _err_msg: String) -> void:
		var arr: Array = data.get("matches", []) as Array if (code >= 200 and code < 300 and data.get("matches") is Array) else []
		my_matches_received.emit(arr)
		if cb.is_valid():
			cb.call(code >= 200 and code < 300, arr)
	)


func fetch_match_replay(match_id: String, cb: Callable) -> void:
	var clean_id: String = match_id.strip_edges()
	if clean_id.is_empty():
		cb.call(false, {}, "Missing match ID.")
		return
	_request_json("/api/matches/" + clean_id.uri_encode() + "/replay", HTTPClient.METHOD_GET, {}, false, func(code: int, data: Dictionary, err_msg: String) -> void:
		if code >= 200 and code < 300 and data.has("batches"):
			cb.call(true, data, "")
		else:
			cb.call(false, {}, str(data.get("error", err_msg if not err_msg.is_empty() else "Replay unavailable.")))
	)


func _request_json(path: String, method: int, body_dict: Dictionary, with_auth: bool, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			cb.call(0, {}, "Server unreachable.")
			return
		var txt: String = body.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(txt) if not txt.is_empty() else {}
		var data: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
		cb.call(response_code, data, "")
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if with_auth and not session_token.is_empty():
		headers.append("Authorization: Bearer " + session_token)
	var url: String = api_base_url + path
	var payload_str: String = "" if (method == HTTPClient.METHOD_GET or method == HTTPClient.METHOD_DELETE) else JSON.stringify(body_dict)
	var err: int = req.request(url, headers, method, payload_str)
	if err != OK:
		req.queue_free()
		cb.call(0, {}, "Failed to send request.")
