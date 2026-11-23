class_name MPClient
extends RefCounted
## Client-side WebSocketPeer manager handling lobby rooms, spawn negotiation,
## deterministic 24 Hz command batches, sync hash checks, and token-based reconnect.

const DEFAULT_SERVER_URL := "ws://151.242.136.36:30041/ws"

signal connected_to_room(room_code: String, nation_id: int, token: String, is_host: bool)
signal lobby_updated(room_code: String, phase: String, players: Array, ai_count: int, is_host: bool)
signal spawn_phase_started(seconds_left: float, players: Array)
signal match_begun(seed: int, local_nation_id: int, ai_count: int, players: Array)
signal tick_batch_received(from_tick: int, to_tick: int, commands: Array)
signal snapshot_received(payload: Dictionary)
signal ping_updated(ping_ms: int)
signal invite_received(from_name: String, room_code: String)
signal disconnected(reason: String)
signal server_error(message: String)

var _peer: WebSocketPeer
var _last_url: String = DEFAULT_SERVER_URL
var _last_room: String = ""
var _last_name: String = "Commander"
var _reconnect_token: String = ""
var _room_code: String = ""
var _local_nation_id: int = 0
var _is_host: bool = false
var _seq: int = 0
var _was_connected: bool = false
var _in_match: bool = false
var _manual_disconnect: bool = false
var _reconnect_timer: float = 0.0
var _reconnect_attempts: int = 0
var last_ping_ms: int = -1
var _ping_timer: float = 0.0


func connect_to_room(ws_url: String, room_code: String, player_name: String, reconnect_token: String = "") -> int:
	disconnect_from_server(false)
	var clean_url: String = ws_url.strip_edges()
	if clean_url.is_empty():
		clean_url = DEFAULT_SERVER_URL
	_last_url = clean_url
	_last_room = room_code.strip_edges().to_upper()
	_last_name = player_name.strip_edges()
	if _last_name.is_empty():
		_last_name = "Commander"
	_reconnect_token = reconnect_token
	_seq = 0
	_was_connected = false
	_in_match = false
	_manual_disconnect = false
	_reconnect_timer = 0.0
	_reconnect_attempts = 0
	last_ping_ms = -1
	_ping_timer = 0.0
	return _open_socket()


func _open_socket() -> int:
	var sep: String = "&" if _last_url.find("?") >= 0 else "?"
	var full_url: String = "%s%sroom=%s&name=%s" % [
		_last_url, sep, _last_room.uri_encode(), _last_name.uri_encode()
	]
	if not _reconnect_token.is_empty():
		full_url += "&token=" + _reconnect_token.uri_encode()

	_peer = WebSocketPeer.new()
	var err: int = _peer.connect_to_url(full_url)
	if err != OK:
		_peer = null
		server_error.emit("Failed to initiate WebSocket connection (err=%d)." % err)
	return err


func disconnect_from_server(emit_signal: bool = true) -> void:
	_manual_disconnect = true
	_in_match = false
	_reconnect_timer = 0.0
	_reconnect_attempts = 0
	if _peer != null:
		if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_peer.close(1000, "client leave")
		_peer = null
	_room_code = ""
	_local_nation_id = 0
	_is_host = false
	_reconnect_token = ""
	last_ping_ms = -1
	_ping_timer = 0.0
	ping_updated.emit(-1)
	if emit_signal and _was_connected:
		_was_connected = false
		disconnected.emit("Disconnected from server.")
	else:
		_was_connected = false


func is_socket_active() -> bool:
	return _peer != null or _reconnect_timer > 0.0


func poll(delta: float) -> void:
	if _peer == null:
		if _reconnect_timer > 0.0:
			_reconnect_timer -= delta
			if _reconnect_timer <= 0.0:
				_open_socket()
		return

	_peer.poll()
	var st: int = _peer.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		_was_connected = true
		_reconnect_attempts = 0
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 2.0
			_send_json({"type": "ping", "t": Time.get_ticks_msec()})
		while _peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _peer.get_packet()
			var txt: String = pkt.get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				_handle_message(parsed as Dictionary)
	elif st == WebSocketPeer.STATE_CLOSED:
		var reason: String = _peer.get_close_reason()
		if reason.is_empty():
			reason = "Connection closed (code %d)." % _peer.get_close_code()
		_peer = null
		last_ping_ms = -1
		ping_updated.emit(-1)
		if (not _manual_disconnect) and _in_match and (not _reconnect_token.is_empty()) and _reconnect_attempts < 5:
			_reconnect_attempts += 1
			_reconnect_timer = 1.5
			return
		_in_match = false
		_was_connected = false
		disconnected.emit(reason)


func _handle_message(msg: Dictionary) -> void:
	var msg_type: String = str(msg.get("type", ""))
	match msg_type:
		"connected":
			_room_code = str(msg.get("room_code", _last_room))
			_last_room = _room_code
			_local_nation_id = int(msg.get("nation_id", 1))
			_reconnect_token = str(msg.get("reconnect_token", _reconnect_token))
			_is_host = bool(msg.get("is_host", false))
			connected_to_room.emit(_room_code, _local_nation_id, _reconnect_token, _is_host)

		"lobby_state":
			_room_code = str(msg.get("room_code", _room_code))
			var players: Array = msg.get("players", [])
			for pv: Variant in players:
				if pv is Dictionary and int((pv as Dictionary).get("nation_id", 0)) == _local_nation_id:
					_is_host = bool((pv as Dictionary).get("is_host", _is_host))
			lobby_updated.emit(
				_room_code,
				str(msg.get("phase", "LOBBY")),
				players,
				int(msg.get("ai_count", 4)),
				_is_host
			)

		"spawn_phase":
			spawn_phase_started.emit(float(msg.get("seconds_left", 10.0)), msg.get("players", []))

		"match_begin":
			_in_match = true
			match_begun.emit(
				int(msg.get("seed", 1)),
				_local_nation_id,
				int(msg.get("ai_count", 4)),
				msg.get("players", [])
			)

		"tick_batch":
			tick_batch_received.emit(
				int(msg.get("from_tick", 0)),
				int(msg.get("to_tick", 0)),
				msg.get("commands", [])
			)

		"match_snapshot":
			_in_match = true
			snapshot_received.emit(msg)

		"pong":
			var sent_ms: int = int(msg.get("t", 0))
			if sent_ms > 0:
				var rtt: int = clampi(int(Time.get_ticks_msec()) - sent_ms, 1, 9999)
				last_ping_ms = rtt
				ping_updated.emit(rtt)

		"invite_received":
			invite_received.emit(str(msg.get("from_name", "Friend")), str(msg.get("room_code", "")))

		"error":
			server_error.emit(str(msg.get("message", "Server rejected action.")))


func get_room_code() -> String:
	return _room_code


func send_friend_invite(friend_name: String) -> void:
	_send_json({
		"type": "invite_friend",
		"friend_name": friend_name.strip_edges(),
		"from_name": _last_name,
		"room_code": _room_code,
	})


func send_start_match(ai_count: int) -> void:
	_send_json({"type": "start_match", "ai_count": ai_count})


func send_pick_spawn(cell: Vector2i) -> void:
	_send_json({"type": "pick_spawn", "x": cell.x, "y": cell.y})


func send_command(cmd: Dictionary) -> void:
	_seq += 1
	_send_json({"type": "command", "seq": _seq, "cmd": cmd})


func send_sync_check(tick: int, state_hash: int) -> void:
	_send_json({"type": "sync_check", "tick": tick, "hash": state_hash})


func send_match_over(winner_nation_id: int) -> void:
	_in_match = false
	_send_json({"type": "match_over", "winner_nation_id": winner_nation_id})


func _send_json(payload: Dictionary) -> void:
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.send_text(JSON.stringify(payload))
