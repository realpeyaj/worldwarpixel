class_name MainGame
extends Node
## Entry coordinator wiring continuous 24 Hz WorldState, 7-layer WorldMap, GameHUD, and AudioManager.

@onready var world_map: WorldMap = $WorldMap
@onready var hud: GameHUD = $HUD

var world_state := WorldState.new()
var simulation_clock := SimulationClock.new()
var mp_client := MPClient.new()
var is_multiplayer: bool = false
var _mp_spawning: bool = false
var _pending_batches: Array[Dictionary] = []
var _tcp_ping: StreamPeerTCP = StreamPeerTCP.new()
var _http_ping_timer: float = 0.5
var _http_ping_inflight: bool = false
var _tcp_ping_sent_usec: int = 0


func _ready() -> void:
	if not world_state.load_world():
		push_error("MainGame failed to load world data.")
		return

	world_map.bind_world_state(world_state)
	hud.bind_world_state(world_state)
	hud.update_clock_text(simulation_clock.get_formatted_time())

	world_map.cell_hovered.connect(hud.show_hovered_cell)
	world_map.spawn_requested.connect(_on_spawn_requested)
	world_map.expand_requested.connect(_on_expand_requested)
	world_map.build_requested.connect(_on_build_requested)
	world_map.structure_selected.connect(hud.show_selected_structure)
	world_map.build_mode_cleared.connect(hud.clear_build_mode)
	world_map.warship_move_requested.connect(_on_warship_move_requested)
	world_map.missile_target_staged.connect(_on_missile_target_staged)
	world_map.missile_launch_requested.connect(_on_missile_launch_requested)
	world_map.missile_mode_cleared.connect(hud.clear_missile_mode)
	world_map.context_menu_requested.connect(hud.open_radial_menu)

	hud.map_mode_toggled.connect(world_map.set_political_mode)
	hud.reset_view_requested.connect(world_map.reset_camera_view)
	hud.build_mode_selected.connect(world_map.set_build_mode)
	hud.missile_mode_selected.connect(world_map.set_missile_mode)
	hud.close_structure_requested.connect(func() -> void: world_map.set_selected_structure(0))
	hud.upgrade_structure_requested.connect(_on_upgrade_structure_requested)
	hud.cancel_expansion_requested.connect(_on_cancel_expansion_requested)
	hud.cancel_ship_requested.connect(_on_cancel_ship_requested)
	hud.build_warship_requested.connect(_on_build_warship_requested)
	hud.radial_attack_requested.connect(_on_expand_requested)
	hud.radial_build_requested.connect(_on_build_requested)
	hud.radial_missile_requested.connect(_on_missile_launch_requested)
	hud.radial_warship_requested.connect(_on_radial_warship_requested)
	hud.request_alliance_requested.connect(_on_request_alliance_requested)
	hud.respond_alliance_requested.connect(_on_respond_alliance_requested)
	hud.break_alliance_requested.connect(_on_break_alliance_requested)
	hud.toggle_embargo_requested.connect(_on_toggle_embargo_requested)
	hud.donate_gold_requested.connect(_on_donate_gold_requested)
	hud.donate_troops_requested.connect(_on_donate_troops_requested)
	hud.new_match_requested.connect(_on_new_match_requested)
	hud.mp_connect_requested.connect(_on_mp_connect_requested)
	hud.mp_disconnect_requested.connect(_on_mp_disconnect_requested)
	hud.mp_start_match_requested.connect(func(ai_c: int) -> void: mp_client.send_start_match(ai_c))
	hud.friend_invite_requested.connect(func(f_name: String, _code: String) -> void: mp_client.send_friend_invite(f_name))
	hud.menu_visibility_changed.connect(_on_menu_visibility_changed)
	hud.quit_requested.connect(func() -> void: get_tree().quit(0))
	_on_menu_visibility_changed(hud.menu_overlay.visible)

	mp_client.lobby_updated.connect(hud.update_mp_lobby)
	mp_client.spawn_phase_started.connect(_on_mp_spawn_phase_started)
	mp_client.match_begun.connect(_on_mp_match_begun)
	mp_client.tick_batch_received.connect(_on_mp_tick_batch)
	mp_client.snapshot_received.connect(_on_mp_snapshot_received)
	mp_client.ping_updated.connect(hud.update_ping)
	mp_client.invite_received.connect(hud.show_incoming_invite)
	mp_client.disconnected.connect(_on_mp_disconnected)
	mp_client.server_error.connect(func(msg: String) -> void: hud.show_toast(msg, true))

	world_state.match_started.connect(_on_match_started)
	world_state.territory_changed.connect(func() -> void: hud.mark_leaderboard_dirty())
	world_state.expansion_updated.connect(func() -> void: hud.mark_expansions_dirty())
	world_state.structure_changed.connect(func(_sid: int) -> void: hud.refresh_all())
	world_state.structure_upgraded.connect(_on_structure_upgraded)
	world_state.factory_link_created.connect(_on_factory_link_created)
	world_state.ship_launched.connect(_on_ship_launched)
	world_state.trade_completed.connect(_on_trade_completed)
	world_state.trade_ship_captured.connect(_on_trade_ship_captured)
	world_state.naval_shot_fired.connect(func(_pos: Vector2) -> void: AudioManager.play_cannon_fire())
	world_state.missile_launched.connect(_on_missile_launched)
	world_state.missile_detonated.connect(_on_missile_detonated)
	world_state.missile_intercepted.connect(_on_missile_intercepted)
	world_state.attack_countered.connect(_on_attack_countered)
	world_state.diplomacy_changed.connect(func() -> void: hud.refresh_all())
	world_state.alliance_requested.connect(_on_alliance_requested)
	world_state.diplomacy_event.connect(_on_diplomacy_event)
	world_state.command_rejected.connect(_on_command_rejected)
	world_state.nation_eliminated.connect(_on_nation_eliminated)
	world_state.victory_reached.connect(_on_victory_reached)


func _exit_tree() -> void:
	_tcp_ping.disconnect_from_host()
	mp_client.disconnect_from_server(false)


func _on_menu_visibility_changed(is_open: bool) -> void:
	var preserve_view: bool = world_state.match_phase != WorldState.PHASE_SPAWN_SELECT
	world_map.set_home_pan_active(is_open, preserve_view)


func _process(delta: float) -> void:
	if mp_client.is_socket_active():
		mp_client.poll(delta)
	elif DisplayServer.get_name() != "headless":
		if _http_ping_inflight:
			_poll_tcp_ping()
		else:
			_http_ping_timer -= delta
			if _http_ping_timer <= 0.0:
				_http_ping_timer = 4.0
				_start_http_ping()

	if is_multiplayer:
		var stepped := false
		while not _pending_batches.is_empty():
			var batch: Dictionary = _pending_batches.pop_front()
			var from_t: int = int(batch.get("from_tick", 0))
			var to_t: int = int(batch.get("to_tick", 0))
			var cmds: Array = batch.get("commands", [])
			for c_item: Variant in cmds:
				if c_item is Dictionary:
					world_state.apply_command(c_item as Dictionary)
			for t in range(from_t, to_t + 1):
				world_state.step_tick(t)
				stepped = true
			simulation_clock.tick_count = world_state.current_tick
			if world_state.current_tick > 0 and world_state.current_tick % 240 == 0:
				mp_client.send_sync_check(world_state.current_tick, world_state.compute_state_hash())
		if stepped:
			hud.update_clock_text(simulation_clock.get_formatted_time())
			hud.refresh_player_bar()
		return

	var ticks: int = simulation_clock.advance(delta)
	if ticks > 0:
		var start_tick: int = simulation_clock.tick_count - ticks + 1
		for i in range(ticks):
			world_state.step_tick(start_tick + i)
		if simulation_clock.tick_count % 3 == 0:
			hud.update_clock_text(simulation_clock.get_formatted_time())
			hud.refresh_player_bar()


func _dispatch_game_command(cmd: Dictionary) -> Dictionary:
	if is_multiplayer:
		mp_client.send_command(cmd)
		return {"ok": true, "queued": true}
	return world_state.apply_command(cmd)


func _on_spawn_requested(cell: Vector2i) -> void:
	if is_multiplayer and _mp_spawning:
		if world_state.is_spawn_point_valid(cell.x, cell.y):
			mp_client.send_pick_spawn(cell)
			hud.show_toast("Spawn chosen! Waiting for opponents...", false)
			AudioManager.play_ui_tap()
		else:
			hud.show_toast("Pick a valid land tile (including islands or Antarctica).", true)
			AudioManager.play_error()
		return

	var cfg: Dictionary = hud.get_spawn_config()
	var res: Dictionary = world_state.apply_command({
		"type": "spawn_player",
		"x": cell.x,
		"y": cell.y,
		"name": cfg.get("name", "Terran Vanguard"),
		"ai_count": int(cfg.get("ai_count", 6)),
	})
	if bool(res.get("ok", false)):
		AudioManager.play_expand_launch()


func _on_match_started() -> void:
	hud.on_match_started()
	AudioManager.start_game_music(2.5)
	hud.show_toast("Nation founded! Use [1] Attack or build Towns, Ports & Factories.", false)


func _on_new_match_requested() -> void:
	mp_client.disconnect_from_server(false)
	is_multiplayer = false
	_mp_spawning = false
	_pending_batches.clear()
	AudioManager.stop_game_music(0.6)
	world_state.reset_match()
	simulation_clock.tick_count = 0
	simulation_clock.accumulator = 0.0
	world_map.set_build_mode("")
	world_map.set_missile_mode("")
	world_map.set_selected_ship(0)
	world_map.set_selected_structure(0)
	world_map._refresh_lut()
	world_map.sync_owner_texture()
	world_map.reset_camera_view()
	hud.update_clock_text(simulation_clock.get_formatted_time())
	hud.on_match_reset()


func _on_mp_connect_requested(ws_url: String, room_code: String, player_name: String) -> void:
	if _http_ping_inflight:
		_tcp_ping.disconnect_from_host()
		_http_ping_inflight = false
	is_multiplayer = true
	_mp_spawning = false
	_pending_batches.clear()
	mp_client.connect_to_room(ws_url, room_code, player_name)


func _on_mp_disconnect_requested() -> void:
	mp_client.disconnect_from_server(false)
	is_multiplayer = false
	_mp_spawning = false
	_pending_batches.clear()
	_http_ping_timer = 0.5


func _on_mp_spawn_phase_started(seconds_left: float, _players: Array) -> void:
	is_multiplayer = true
	_mp_spawning = true
	world_state.reset_match()
	simulation_clock.tick_count = 0
	world_map.sync_owner_texture()
	hud.on_mp_spawn_phase(seconds_left)
	hud.show_toast("Multiplayer Spawn: click any landmass before timer ends!", false)


func _on_mp_match_begun(seed_val: int, local_nid: int, ai_count: int, players: Array) -> void:
	is_multiplayer = true
	_mp_spawning = false
	_pending_batches.clear()
	simulation_clock.tick_count = 0
	world_state.apply_command({
		"type": "start_mp_match",
		"seed": seed_val,
		"local_nation_id": local_nid,
		"ai_count": ai_count,
		"players": players,
	})
	world_map._refresh_lut()
	world_map.sync_owner_texture()


func _on_mp_tick_batch(from_tick: int, to_tick: int, commands: Array) -> void:
	_pending_batches.append({"from_tick": from_tick, "to_tick": to_tick, "commands": commands})


func _on_mp_snapshot_received(snap: Dictionary) -> void:
	is_multiplayer = true
	_mp_spawning = false
	_pending_batches.clear()
	world_state.apply_command({
		"type": "start_mp_match",
		"seed": int(snap.get("seed", 1)),
		"local_nation_id": int(snap.get("local_nation_id", 1)),
		"ai_count": int(snap.get("ai_count", 4)),
		"players": snap.get("players", []),
	})
	for batch_v: Variant in snap.get("batches", []):
		if batch_v is Dictionary:
			var b := batch_v as Dictionary
			for c_item: Variant in b.get("commands", []):
				if c_item is Dictionary:
					world_state.apply_command(c_item as Dictionary)
			for t in range(int(b.get("from_tick", 0)), int(b.get("to_tick", 0)) + 1):
				world_state.step_tick(t)
	simulation_clock.tick_count = world_state.current_tick
	world_map._refresh_lut()
	world_map.sync_owner_texture()
	hud.refresh_all()
	hud.show_toast("Reconnected & synced to tick %d!" % world_state.current_tick, false)


func _on_mp_disconnected(reason: String) -> void:
	hud.on_mp_disconnected(reason)
	_http_ping_timer = 0.5
	if is_multiplayer:
		hud.show_toast("Multiplayer disconnected: %s" % reason, true)


func _start_http_ping() -> void:
	var ws_url: String = hud.get_mp_server_url()
	var stripped: String = ws_url.replace("wss://", "").replace("ws://", "").replace("https://", "").replace("http://", "")
	var slash_idx: int = stripped.find("/")
	if slash_idx >= 0:
		stripped = stripped.substr(0, slash_idx)
	var host := "151.242.136.36"
	var port := 30041
	var colon_idx: int = stripped.rfind(":")
	if colon_idx > 0:
		host = stripped.substr(0, colon_idx)
		port = maxi(1, int(stripped.substr(colon_idx + 1)))
	elif not stripped.is_empty():
		host = stripped
	_tcp_ping.disconnect_from_host()
	_tcp_ping_sent_usec = Time.get_ticks_usec()
	if _tcp_ping.connect_to_host(host, port) == OK:
		_http_ping_inflight = true
	else:
		hud.update_ping(-1)


func _poll_tcp_ping() -> void:
	_tcp_ping.poll()
	var st: int = _tcp_ping.get_status()
	var elapsed_ms: int = int(round(float(Time.get_ticks_usec() - _tcp_ping_sent_usec) / 1000.0))
	if st == StreamPeerTCP.STATUS_CONNECTED:
		_tcp_ping.disconnect_from_host()
		_http_ping_inflight = false
		if not mp_client.is_socket_active():
			hud.update_ping(clampi(elapsed_ms, 1, 9999))
	elif st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE or elapsed_ms > 2500:
		_tcp_ping.disconnect_from_host()
		_http_ping_inflight = false
		if not mp_client.is_socket_active():
			hud.update_ping(-1)


func _on_expand_requested(cell: Vector2i) -> void:
	var res: Dictionary = _dispatch_game_command({
		"type": "expand_to",
		"nation_id": world_state.player_nation_id,
		"x": cell.x,
		"y": cell.y,
		"commit_ratio": hud.get_commit_ratio(),
	})
	if bool(res.get("ok", false)):
		var mode_s: String = str(res.get("mode", ""))
		if mode_s == "naval_landing":
			AudioManager.play_boat_bell()
		elif mode_s == "land" or mode_s == "land_reinforce":
			AudioManager.play_expand_launch()


func _on_build_requested(s_type: String, cell: Vector2i) -> void:
	if s_type == "warship":
		_on_radial_warship_requested(cell)
		return
	var res: Dictionary = _dispatch_game_command({
		"type": "build_structure",
		"nation_id": world_state.player_nation_id,
		"structure_type": s_type,
		"x": cell.x,
		"y": cell.y,
	})
	if bool(res.get("ok", false)):
		AudioManager.play_build_placed()
		if res.has("structure_id"):
			world_map.set_selected_structure(int(res.get("structure_id", 0)))


func _on_missile_target_staged(kind: String, _cell: Vector2i) -> void:
	AudioManager.play_target_lock()
	hud.show_toast("Target locked! Click again on target to confirm %s launch." % kind.to_upper(), false)


func _on_upgrade_structure_requested(sid: int) -> void:
	_dispatch_game_command({
		"type": "upgrade_structure",
		"nation_id": world_state.player_nation_id,
		"structure_id": sid,
	})


func _on_cancel_expansion_requested(eid: int) -> void:
	var res: Dictionary = _dispatch_game_command({
		"type": "cancel_expansion",
		"nation_id": world_state.player_nation_id,
		"expansion_id": eid,
	})
	if bool(res.get("ok", false)):
		AudioManager.play_retreat_horn()


func _on_structure_upgraded(sid: int, new_level: int) -> void:
	var st: StructureData = world_state.get_structure(sid)
	if st != null and st.nation_id == world_state.player_nation_id:
		AudioManager.play_upgrade_instant(new_level)
	hud.refresh_all()


func _on_factory_link_created(is_bridge: bool) -> void:
	AudioManager.play_bridge_connect()
	if is_bridge:
		hud.show_toast("Factory Bridge built across water! Pesos & trade linked.", false)


func _on_ship_launched(ship_id: int) -> void:
	var sh: ShipUnit = world_state.ships.get(ship_id, null)
	if sh != null and sh.nation_id == world_state.player_nation_id:
		if sh.kind == ShipUnit.KIND_LANDING:
			AudioManager.play_boat_bell()
		elif sh.kind == ShipUnit.KIND_WARSHIP:
			AudioManager.play_warship_horn()
		else:
			AudioManager.play_ship_depart()


func _on_trade_completed(nation_id: int, _world_pos: Vector2, _gold_amount: float) -> void:
	if nation_id == world_state.player_nation_id:
		AudioManager.play_trade_gold()


func _on_command_rejected(reason: String) -> void:
	hud.show_toast(reason, true)
	AudioManager.play_error()


func _on_nation_eliminated(dead_nid: int, conqueror_nid: int) -> void:
	var c_n: NationData = world_state.get_nation(conqueror_nid)
	var c_name: String = c_n.name if c_n != null else "an enemy nation"
	if dead_nid == world_state.player_nation_id:
		world_map.set_build_mode("")
		world_map.set_missile_mode("")
		world_map.set_selected_ship(0)
		world_map.set_selected_structure(0)
		AudioManager.play_retreat_horn()
		hud.enter_spectator_mode(c_name)
	else:
		var d_n: NationData = world_state.get_nation(dead_nid)
		if d_n != null:
			hud.show_toast("%s was conquered by %s!" % [d_n.name, c_name], false)
	hud.refresh_all()


func _on_victory_reached(winner_id: int, pct: float) -> void:
	var nation: NationData = world_state.get_nation(winner_id)
	var name_str: String = nation.name if nation != null else "Nation #%d" % winner_id
	hud.show_toast("VICTORY: %s controls %.1f%% of Earth!" % [name_str, pct], false)
	AudioManager.play_victory()
	hud.refresh_all()
	hud.show_victory_screen(winner_id, pct)
	if is_multiplayer and mp_client.is_socket_active():
		mp_client.send_match_over(winner_id)


func _on_cancel_ship_requested(sid: int) -> void:
	var res: Dictionary = _dispatch_game_command({
		"type": "cancel_ship",
		"nation_id": world_state.player_nation_id,
		"ship_id": sid,
	})
	if bool(res.get("ok", false)):
		AudioManager.play_retreat_horn()
		if res.has("refunded_troops"):
			hud.show_toast("Landing boat retreated (%d troops returned)." % int(round(float(res.get("refunded_troops", 0.0)))), false)


func _on_build_warship_requested(port_id: int) -> void:
	var res: Dictionary = _dispatch_game_command({
		"type": "build_warship",
		"nation_id": world_state.player_nation_id,
		"port_id": port_id,
	})
	if bool(res.get("ok", false)):
		AudioManager.play_warship_horn()
		world_map.set_selected_structure(0)
		world_map.set_selected_ship(0)
		hud.show_toast("Warship launched! Click any Warship to manually steer it.", false)
		hud.refresh_all()


func _on_radial_warship_requested(cell: Vector2i) -> void:
	var p_n: NationData = world_state.get_player_nation()
	if p_n == null:
		return
	var best_port := 0
	var best_d2 := 1e12
	for sid: int in p_n.structure_ids:
		var st: StructureData = world_state.get_structure(sid)
		if st != null and st.type == StructureData.TYPE_PORT and not st.is_constructing and st.level >= 1 and st.action_cooldown_ticks == 0:
			var d2: float = Vector2(st.cell - cell).length_squared()
			if d2 < best_d2:
				best_d2 = d2
				best_port = sid
	if best_port == 0:
		hud.show_toast("Need a ready completed Port to commission a Warship.", true)
		AudioManager.play_error()
		return
	var res: Dictionary = _dispatch_game_command({
		"type": "build_warship",
		"nation_id": world_state.player_nation_id,
		"port_id": best_port,
		"x": cell.x,
		"y": cell.y,
	})
	if bool(res.get("ok", false)):
		AudioManager.play_warship_horn()
		world_map.set_selected_ship(0)
		hud.refresh_all()


func _on_warship_move_requested(ship_id: int, cell: Vector2i) -> void:
	var res: Dictionary = _dispatch_game_command({
		"type": "command_warship",
		"nation_id": world_state.player_nation_id,
		"ship_id": ship_id,
		"x": cell.x,
		"y": cell.y,
	})
	if bool(res.get("ok", false)):
		AudioManager.play_warship_horn()


func _on_missile_launch_requested(kind: String, cell: Vector2i) -> void:
	_dispatch_game_command({
		"type": "launch_missile",
		"nation_id": world_state.player_nation_id,
		"missile_kind": kind,
		"x": cell.x,
		"y": cell.y,
	})
	hud.refresh_all()


func _on_request_alliance_requested(target_nid: int) -> void:
	_dispatch_game_command({
		"type": "request_alliance",
		"nation_id": world_state.player_nation_id,
		"target_nation_id": target_nid,
	})


func _on_respond_alliance_requested(from_nid: int, accept: bool) -> void:
	_dispatch_game_command({
		"type": "respond_alliance",
		"nation_id": world_state.player_nation_id,
		"from_nation_id": from_nid,
		"accept": accept,
	})


func _on_break_alliance_requested(target_nid: int) -> void:
	_dispatch_game_command({
		"type": "break_alliance",
		"nation_id": world_state.player_nation_id,
		"target_nation_id": target_nid,
	})


func _on_toggle_embargo_requested(target_nid: int) -> void:
	_dispatch_game_command({
		"type": "toggle_embargo",
		"nation_id": world_state.player_nation_id,
		"target_nation_id": target_nid,
	})


func _on_donate_gold_requested(target_nid: int, amount: float) -> void:
	var res: Dictionary = _dispatch_game_command({
		"type": "donate_gold",
		"nation_id": world_state.player_nation_id,
		"target_nation_id": target_nid,
		"amount": amount,
	})
	if bool(res.get("ok", false)):
		AudioManager.play_troop_donate()
	hud.refresh_all()


func _on_donate_troops_requested(target_nid: int, ratio: float) -> void:
	var res: Dictionary = _dispatch_game_command({
		"type": "donate_troops",
		"nation_id": world_state.player_nation_id,
		"target_nation_id": target_nid,
		"ratio": ratio,
	})
	if bool(res.get("ok", false)):
		AudioManager.play_troop_donate()
	hud.refresh_all()


func _on_trade_ship_captured(captor_nid: int, _pos: Vector2, gold_amount: float) -> void:
	if captor_nid == world_state.player_nation_id:
		AudioManager.play_trade_gold()
		hud.show_toast("Warship captured trade ship (+%s Pesos queued)!" % StructureData.format_pesos(gold_amount), false)


func _on_missile_launched(_mid: int, kind: String) -> void:
	if kind == MissileUnit.KIND_SAM:
		AudioManager.play_sam_launch()
	elif kind == MissileUnit.KIND_HYDROGEN or kind == MissileUnit.KIND_MIRV:
		AudioManager.play_silo_nuke_launch()
	elif kind != MissileUnit.KIND_MIRV_WARHEAD:
		AudioManager.play_missile_launch()


func _on_missile_detonated(_pos: Vector2, _rad: float, kind: String) -> void:
	AudioManager.play_nuke_blast()
	hud.show_toast("Strategic %s detonation!" % kind.to_upper(), true)
	hud.refresh_all()


func _on_missile_intercepted(_pos: Vector2) -> void:
	AudioManager.play_sam_intercept()
	hud.show_toast("SAM Launcher intercepted incoming warhead!", false)


func _on_attack_countered(defender_id: int, attacker_id: int, destroyed: float, repelled: bool) -> void:
	if defender_id == world_state.player_nation_id or attacker_id == world_state.player_nation_id:
		AudioManager.play_battle_clash()
		if defender_id == world_state.player_nation_id:
			var atk_n: NationData = world_state.get_nation(attacker_id)
			var nm: String = atk_n.name if atk_n != null else "Invader"
			if repelled:
				hud.show_toast("Counter-attack REPELLED %s's invasion (-%d enemy troops)!" % [nm, int(round(destroyed))], false)
			else:
				hud.show_toast("Counter-attack clashed with %s (-%d enemy troops)!" % [nm, int(round(destroyed))], false)


func _on_alliance_requested(from_nid: int, to_nid: int) -> void:
	if to_nid == world_state.player_nation_id:
		AudioManager.play_diplomacy_chime()
		hud.show_alliance_offer(from_nid)


func _on_diplomacy_event(msg: String, is_warning: bool) -> void:
	if is_warning:
		AudioManager.play_betrayal_alert()
	else:
		AudioManager.play_diplomacy_chime()
	hud.show_toast(msg, is_warning)
