class_name UnitsLayer
extends Node2D
## Layer 5 renderer: zoom-invariant nation-colored geometric ship markers
## (2x2 Trade square, 3x3 Explorer square, small diamond Warship), curving missiles & border counters.

const TRADE_SHIP_SIZE_PX := 2.0
const EXPLORER_SHIP_SIZE_PX := 3.0
const WARSHIP_DIAMOND_HALF_LEN := 5.2
const WARSHIP_DIAMOND_HALF_WID := 3.5

var _tex_train: Texture2D = preload("res://assets/sprites/icon_train.png")
var _tex_train_mask: Texture2D = preload("res://assets/sprites/icon_train_mask.png")

var _world_state: WorldState
var _camera: Camera2D
var _selected_ship_id: int = 0
var _explosions: Array[Dictionary] = []
var _elapsed: float = 0.0
var _was_active: bool = false
var _last_zoom: float = -1.0


func setup(world_state: WorldState, camera: Camera2D) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_world_state = world_state
	_camera = camera
	if not _world_state.missile_detonated.is_connected(_on_missile_detonated):
		_world_state.missile_detonated.connect(_on_missile_detonated)
	if not _world_state.missile_intercepted.is_connected(_on_missile_intercepted):
		_world_state.missile_intercepted.connect(_on_missile_intercepted)
	if not _world_state.ship_destroyed.is_connected(_on_ship_destroyed):
		_world_state.ship_destroyed.connect(_on_ship_destroyed)
	queue_redraw()


func set_selected_ship(sid: int) -> void:
	_selected_ship_id = sid
	queue_redraw()


func _on_missile_detonated(world_pos: Vector2, radius_world: float, _kind: String) -> void:
	_explosions.append({
		"pos": world_pos,
		"max_r": maxf(radius_world, 18.0),
		"age": 0.0,
		"duration": 1.1,
		"color": Color(1.0, 0.42, 0.16, 1.0),
	})


func _on_missile_intercepted(world_pos: Vector2) -> void:
	_explosions.append({
		"pos": world_pos,
		"max_r": 14.0,
		"age": 0.0,
		"duration": 0.45,
		"color": Color(0.36, 0.94, 1.0, 1.0),
	})


func _on_ship_destroyed(world_pos: Vector2, _kind: String) -> void:
	_explosions.append({
		"pos": world_pos,
		"max_r": 12.0,
		"age": 0.0,
		"duration": 0.55,
		"color": Color(1.0, 0.72, 0.34, 1.0),
	})


func _process(delta: float) -> void:
	_elapsed += delta
	for i in range(_explosions.size() - 1, -1, -1):
		var ex: Dictionary = _explosions[i]
		ex["age"] = float(ex["age"]) + delta
		if float(ex["age"]) >= float(ex["duration"]):
			_explosions.remove_at(i)
	if _world_state == null:
		return
	var active_now: bool = (
		(not _world_state.ships.is_empty())
		or (not _world_state.expansions.is_empty())
		or (not _world_state.trains.is_empty())
		or (not _world_state.missiles.is_empty())
		or (not _world_state.naval_shells.is_empty())
		or (not _explosions.is_empty())
		or _selected_ship_id > 0
	)
	var z: float = _camera.zoom.x if _camera != null else 1.0
	if active_now or _was_active or absf(z - _last_zoom) > 1e-4:
		_was_active = active_now
		_last_zoom = z
		queue_redraw()


func _draw() -> void:
	if _world_state == null:
		return
	var z: float = _camera.zoom.x if _camera != null else 1.0
	var inv_z: float = 1.0 / maxf(z, 1.0)
	var font: Font = ThemeFactory.get_ui_font()

	# 1. Active expansion targets + live troop counts on every expanding border
	for eid: int in _world_state.expansions.keys():
		var order: ExpansionOrder = _world_state.expansions[eid]
		if order.nation_id == _world_state.player_nation_id:
			var tgt_pos: Vector2 = _world_state.sim_to_world(order.target_cell)
			var pulse: float = 0.75 + 0.25 * sin(_elapsed * 5.0)
			var col := Color(1.0, 0.42, 0.38, 0.85 * pulse) if order.is_contested else Color(0.45, 0.90, 1.0, 0.85 * pulse)
			draw_arc(tgt_pos, 5.5 * inv_z, 0.0, TAU, 24, col, 1.5 * inv_z)
			draw_circle(tgt_pos, 1.8 * inv_z, col)

		if order.front_world_pos != Vector2.ZERO:
			var nation: NationData = _world_state.get_nation(order.nation_id)
			var base_col: Color = nation.color.lightened(0.22) if nation != null else Color.WHITE
			var label: String = _format_troops(order.remaining_troops)
			var is_flashing: bool = order.troop_flash_timer > 0.0
			var rim_col: Color = Color(0.28, 0.96, 0.54, 0.96) if is_flashing else (Color(1.0, 0.42, 0.36, 0.95) if order.is_contested else base_col)
			var text_col: Color = Color(0.68, 1.0, 0.78, 0.98) if is_flashing else Color(0.96, 0.98, 1.0, 0.96)
			var badge_w: float = maxf(22.0, float(label.length()) * 6.5 + 8.0) * inv_z
			var badge_h: float = 12.0 * inv_z
			var rect := Rect2(order.front_world_pos - Vector2(badge_w * 0.5, badge_h * 0.5), Vector2(badge_w, badge_h))
			draw_rect(rect, Color(0.04, 0.06, 0.10, 0.84), true)
			draw_rect(rect, rim_col, false, 1.1 * inv_z)
			draw_set_transform(order.front_world_pos + Vector2(-24.0 * inv_z, 3.0 * inv_z), 0.0, Vector2(inv_z * 0.72, inv_z * 0.72))
			draw_string(font, Vector2(1.0, 1.0), label, HORIZONTAL_ALIGNMENT_CENTER, 66, 11, Color(0.02, 0.03, 0.05, 0.92))
			draw_string(font, Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_CENTER, 66, 11, text_col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. Ships (geometric nation-colored markers; never enlarge on zoom out)
	var ship_scale: float = 1.0 / maxf(z, 1.0)
	for sid: int in _world_state.ships.keys():
		var ship: ShipUnit = _world_state.ships[sid]
		if not ship.active:
			continue
		var nation: NationData = _world_state.get_nation(ship.nation_id)
		var n_col: Color = nation.color if nation != null else Color.WHITE
		var pos: Vector2 = ship.position
		var fwd := Vector2(cos(ship.heading), sin(ship.heading))
		var is_trade: bool = (ship.kind == ShipUnit.KIND_TRADE)
		var is_warship: bool = (ship.kind == ShipUnit.KIND_WARSHIP)

		var wake_start: float = (1.8 if is_trade else (3.2 if is_warship else 2.4)) * ship_scale
		var wake_end: float = (4.5 if is_trade else (7.5 if is_warship else 5.8)) * ship_scale
		draw_line(
			pos - fwd * wake_start,
			pos - fwd * wake_end,
			Color(0.84, 0.94, 1.0, 0.30 if is_trade else 0.42),
			(0.65 if is_trade else (1.0 if is_warship else 0.85)) * ship_scale
		)

		# Draw remaining sea route polyline to beachhead + post-landing marker for active player explorer ships
		if ship.kind == ShipUnit.KIND_LANDING and ship.nation_id == _world_state.player_nation_id:
			var land_w: Vector2 = _world_state.sim_to_world(ship.landing_cell)
			var tgt_w: Vector2 = _world_state.sim_to_world(ship.target_cell if ship.target_cell.x >= 0 else ship.landing_cell)
			var sea_pts := PackedVector2Array([pos])
			for wi in range(ship.waypoint_index, ship.waypoints.size()):
				sea_pts.append(ship.waypoints[wi])
			sea_pts.append(land_w)
			if sea_pts.size() >= 2:
				draw_polyline(sea_pts, Color(0.48, 0.92, 1.0, 0.36), 1.1 * inv_z, false)
			if land_w.distance_to(tgt_w) > 4.0:
				draw_dashed_line(land_w, tgt_w, Color(0.48, 0.92, 1.0, 0.24), 1.0 * inv_z, 4.0 * inv_z)
			_draw_crosshair(tgt_w, 7.0 * inv_z, Color(0.48, 0.95, 1.0, 0.92), inv_z)

		if is_trade:
			if ship.is_allied_trade and ship.nation_id == _world_state.player_nation_id and ship.waypoints.size() >= 2:
				var route_pts := PackedVector2Array([pos])
				for wi in range(ship.waypoint_index, ship.waypoints.size()):
					route_pts.append(ship.waypoints[wi])
				if route_pts.size() >= 2:
					draw_polyline(route_pts, Color(0.98, 0.84, 0.36, 0.24), 0.75 * ship_scale, false)
			var sq_sz: float = (TRADE_SHIP_SIZE_PX * (1.25 if ship.is_allied_trade else 1.0)) * ship_scale
			var sq_rect := Rect2(pos - Vector2(sq_sz, sq_sz) * 0.5, Vector2(sq_sz, sq_sz))
			draw_rect(sq_rect, n_col.lightened(0.08), true)
			var trade_rim: Color = Color(0.98, 0.86, 0.32, 0.96) if ship.is_allied_trade else Color(0.04, 0.06, 0.09, 0.78)
			draw_rect(sq_rect, trade_rim, false, (0.85 if ship.is_allied_trade else 0.55) * ship_scale)
		elif is_warship:
			var hl: float = WARSHIP_DIAMOND_HALF_LEN * ship_scale
			var hw: float = WARSHIP_DIAMOND_HALF_WID * ship_scale
			var pts := PackedVector2Array([
				Vector2(hl, 0.0),
				Vector2(0.0, hw),
				Vector2(-hl, 0.0),
				Vector2(0.0, -hw),
			])
			var outline := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
			draw_set_transform(pos, ship.heading, Vector2.ONE)
			draw_colored_polygon(pts, n_col.lightened(0.16))
			draw_polyline(outline, Color(0.04, 0.06, 0.10, 0.90), 0.75 * ship_scale, true)
			draw_circle(Vector2.ZERO, 0.85 * ship_scale, Color(0.96, 0.98, 1.0, 0.85))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var ex_sz: float = EXPLORER_SHIP_SIZE_PX * ship_scale
			var ex_rect := Rect2(pos - Vector2(ex_sz, ex_sz) * 0.5, Vector2(ex_sz, ex_sz))
			draw_rect(ex_rect, n_col.lightened(0.14), true)
			draw_rect(ex_rect, Color(0.04, 0.06, 0.09, 0.86), false, 0.65 * ship_scale)

		if ship.kind == ShipUnit.KIND_LANDING and ship.troops_carried >= 1.0:
			var ship_txt := _format_troops(ship.troops_carried)
			draw_set_transform(pos + Vector2(-18.0 * ship_scale, -6.5 * ship_scale), 0.0, Vector2(ship_scale * 0.68, ship_scale * 0.68))
			draw_string(font, Vector2(1.0, 1.0), ship_txt, HORIZONTAL_ALIGNMENT_CENTER, 52, 10, Color(0.02, 0.03, 0.05, 0.92))
			draw_string(font, Vector2.ZERO, ship_txt, HORIZONTAL_ALIGNMENT_CENTER, 52, 10, Color(0.95, 0.98, 1.0, 0.96))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif is_warship:
			if ship.id == _selected_ship_id:
				draw_arc(pos, 6.5 * ship_scale, 0.0, TAU, 24, Color(1.0, 0.90, 0.36, 0.94), 1.2 * ship_scale)
			if ship.docked_port_id > 0:
				var heal_pulse: float = 0.65 + 0.35 * sin(_elapsed * 6.0)
				draw_arc(pos, 5.2 * ship_scale, 0.0, TAU, 18, Color(0.28, 0.96, 0.62, 0.88 * heal_pulse), 1.0 * ship_scale)
			if ship.hp < ship.max_hp:
				var hp_ratio: float = clampf(ship.hp / maxf(ship.max_hp, 1.0), 0.0, 1.0)
				var bw: float = 11.0 * ship_scale
				var bh: float = 2.6 * ship_scale
				var bx: float = pos.x - bw * 0.5
				var by: float = pos.y - 6.2 * ship_scale
				var bar_col := Color(0.173, 0.937, 0.071, 0.96)
				if hp_ratio <= 0.25:
					bar_col = Color(0.910, 0.098, 0.098, 0.96)
				elif hp_ratio <= 0.50:
					bar_col = Color(0.941, 0.478, 0.098, 0.96)
				elif hp_ratio <= 0.75:
					bar_col = Color(0.792, 0.906, 0.059, 0.96)
				draw_rect(Rect2(bx - 0.6 * ship_scale, by - 0.6 * ship_scale, bw + 1.2 * ship_scale, bh + 1.2 * ship_scale), Color(0.03, 0.04, 0.06, 0.92), true)
				draw_rect(Rect2(bx, by, bw * hp_ratio, bh), bar_col, true)
			if ship.ship_level >= 2:
				var pips: int = ship.ship_level - 1
				var pip_w: float = 3.6 * ship_scale
				var pip_h: float = 1.2 * ship_scale
				var pip_gap: float = 1.0 * ship_scale
				var total_pw: float = float(pips) * pip_w + float(pips - 1) * pip_gap
				var start_px: float = pos.x - total_pw * 0.5
				var pip_y: float = pos.y + 4.2 * ship_scale
				for p_i in range(pips):
					var px: float = start_px + float(p_i) * (pip_w + pip_gap)
					draw_rect(Rect2(px, pip_y, pip_w, pip_h), Color(1.0, 0.84, 0.0, 0.98), true)

	# 3. Top-down OpenFront 1:1 Multi-Car Factory Trains (Engine + Trailing Cargo Carriages)
	for tr: Dictionary in _world_state.trains:
		var t_pos: Vector2 = tr["pos"]
		var nation: NationData = _world_state.get_nation(int(tr.get("nation_id", 0)))
		var t_col: Color = nation.color if nation != null else Color.WHITE
		var p_a: Vector2 = tr["from_pos"]
		var p_b: Vector2 = tr["to_pos"]
		var is_ret: bool = bool(tr.get("returning", false))
		var t_dir: Vector2 = (p_a - p_b) if is_ret else (p_b - p_a)
		var t_heading: float = float(tr.get("heading", t_dir.angle()))
		var car_pts: PackedVector2Array = tr.get("car_positions", PackedVector2Array())
		var car_hdgs: PackedFloat32Array = tr.get("car_headings", PackedFloat32Array())
		var car_sz := Vector2(5.4, 3.0) * ship_scale
		for c_i in range(car_pts.size() - 1, -1, -1):
			var c_pos: Vector2 = car_pts[c_i]
			if c_pos.distance_squared_to(t_pos) < 1.5 * ship_scale:
				continue
			var c_hdg: float = car_hdgs[c_i] if c_i < car_hdgs.size() else t_heading
			draw_set_transform(c_pos, c_hdg, Vector2.ONE)
			var car_rect := Rect2(-car_sz * 0.5, car_sz)
			draw_rect(car_rect, Color(0.06, 0.08, 0.11, 0.92), true)
			var inner_rect := car_rect.grow(-0.55 * ship_scale)
			var cargo_col: Color = t_col.lightened(0.15) if is_ret else t_col.lightened(0.28).lerp(Color(1.0, 0.86, 0.32), 0.35)
			draw_rect(inner_rect, cargo_col, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var t_sz := Vector2(8.0, 4.0) * ship_scale
		draw_set_transform(t_pos, t_heading, Vector2.ONE)
		draw_texture_rect(_tex_train, Rect2(-t_sz * 0.5, t_sz), false, Color(1.0, 1.0, 1.0, 0.96))
		draw_texture_rect(_tex_train_mask, Rect2(-t_sz * 0.5, t_sz), false, t_col.lightened(0.20))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Naval Shells
	for sh_d: Dictionary in _world_state.naval_shells:
		var a: Vector2 = sh_d["start_pos"]
		var b: Vector2 = sh_d["target_pos"]
		var prog: float = float(sh_d["progress"])
		var p0: Vector2 = a.lerp(b, maxf(0.0, prog - 0.18))
		var p1: Vector2 = a.lerp(b, prog)
		draw_line(p0, p1, Color(1.0, 0.86, 0.38, 0.96), 1.5 * ship_scale)

	# 5. Curved Ballistic Missiles, MIRVs, OpenFront 1:1 Rotating Telegraph & SAM Interceptors
	var targeted_by_sam: Dictionary = {}
	for mid_s: int in _world_state.missiles.keys():
		var ms: MissileUnit = _world_state.missiles[mid_s]
		if ms.active and ms.kind == MissileUnit.KIND_SAM and ms.target_missile_id > 0:
			targeted_by_sam[ms.target_missile_id] = true

	for mid: int in _world_state.missiles.keys():
		var m: MissileUnit = _world_state.missiles[mid]
		if not m.active:
			continue
		var is_sam: bool = (m.kind == MissileUnit.KIND_SAM)
		if is_sam:
			var t_sam: float = maxf(0.0, m.progress - 0.55)
			draw_line(m.start_pos.lerp(m.pos, t_sam), m.pos, Color(0.45, 0.94, 1.0, 0.55), 1.0 * ship_scale)
			_draw_actual_missile(m, ship_scale, false)
		else:
			var is_mini: bool = (m.kind == MissileUnit.KIND_MIRV_WARHEAD)
			var is_intercepted: bool = targeted_by_sam.has(m.id)
			var t0: float = maxf(0.0, m.progress - 0.58)
			var arc_pts := PackedVector2Array()
			var arc_n: int = 8 if is_mini else 15
			for si in range(arc_n):
				var tt: float = lerpf(t0, m.progress, float(si) / float(arc_n - 1))
				arc_pts.append(m.get_curve_point(tt))
			if arc_pts.size() >= 2:
				var trail_col := Color(1.0, 0.32, 0.32, 0.85) if is_intercepted else Color(1.0, 0.52, 0.24, 0.82)
				draw_polyline(arc_pts, trail_col, (1.0 if is_mini else 1.5) * ship_scale, true)

			# Remaining dashed trajectory preview (OpenFront NukeTrajectoryPass)
			if not is_mini and m.progress < 0.96:
				var rem_col := Color(1.0, 0.31, 0.31, 0.52) if is_intercepted else Color(1.0, 1.0, 1.0, 0.34)
				var prev_pt: Vector2 = m.pos
				for fi in range(1, 7):
					var ft: float = lerpf(m.progress, 1.0, float(fi) / 6.0)
					var next_pt: Vector2 = m.get_curve_point(ft)
					if fi % 2 == 1:
						draw_line(prev_pt, next_pt, rem_col, 1.1 * ship_scale)
					prev_pt = next_pt

			if m.ground_pos != Vector2.ZERO and not is_mini:
				draw_circle(m.ground_pos, 1.4 * ship_scale, Color(0.04, 0.05, 0.08, 0.30))

			# Exact destroyed blast radius telegraph at impact zone (1:1 with _detonate_missile)
			var tele_col := Color(1.0, 0.18, 0.16, 0.86)
			if m.nation_id == _world_state.player_nation_id:
				tele_col = Color(0.16, 0.96, 0.38, 0.84)
			elif _world_state.are_allied(_world_state.player_nation_id, m.nation_id):
				tele_col = Color(1.0, 0.92, 0.20, 0.84)
			var sim_s: float = _world_state.sim_scale
			var tele_r: float = (12.0 * inv_z) if m.kind == MissileUnit.KIND_MIRV else (float(m.blast_radius_sim) * sim_s)
			var tele_pulse: float = 0.82 + 0.12 * sin(_elapsed * 3.5)
			if not is_mini:
				draw_circle(m.target_pos, tele_r, Color(tele_col.r, tele_col.g, tele_col.b, 0.11 * tele_pulse))
			var dash_count: int = 8 if is_mini else 16
			var rot_base: float = _elapsed * 1.4
			var seg_step: float = TAU / float(dash_count)
			for di in range(dash_count):
				var a0: float = rot_base + float(di) * seg_step
				draw_arc(m.target_pos, tele_r, a0, a0 + seg_step * 0.62, 4, Color(tele_col.r, tele_col.g, tele_col.b, tele_col.a * tele_pulse), (1.0 if is_mini else 1.4) * inv_z)

			# H-Bomb warm halo in flight
			if m.kind == MissileUnit.KIND_HYDROGEN:
				draw_circle(m.pos, 8.5 * ship_scale, Color(1.0, 0.72, 0.15, 0.26))
				draw_circle(m.pos, 4.8 * ship_scale, Color(1.0, 0.84, 0.30, 0.38))

			_draw_actual_missile(m, ship_scale, is_intercepted)

	# 6. Explosions & Intercept Flashes
	for ex: Dictionary in _explosions:
		var t_prog: float = clampf(float(ex["age"]) / maxf(float(ex["duration"]), 0.01), 0.0, 1.0)
		var col: Color = ex["color"]
		var r: float = maxf(2.0, float(ex["max_r"]) * (0.18 + 0.82 * t_prog))
		var alpha: float = 1.0 - t_prog
		draw_circle(ex["pos"], r * 0.45, Color(col.r, col.g, col.b, alpha * 0.26))
		draw_arc(ex["pos"], r, 0.0, TAU, 32, Color(col.r, col.g, col.b, alpha * 0.92), 2.2 * inv_z)


static func _format_troops(amount: float) -> String:
	var n: int = int(round(maxf(0.0, amount)))
	if n >= 1000:
		return "%.1fk" % (float(n) / 1000.0)
	return "%d" % n


func _draw_actual_missile(m: MissileUnit, s: float, is_intercepted: bool) -> void:
	var flick: float = 0.82 + 0.18 * sin(_elapsed * 32.0 + float(m.id))
	draw_set_transform(m.pos, m.heading, Vector2.ONE)
	match m.kind:
		MissileUnit.KIND_SAM:
			# Needle interceptor + swept cyan fins + hot cyan-white exhaust
			var exhaust := PackedVector2Array([Vector2(-3.2 * s, 0.0), Vector2(-7.8 * s * flick, -1.2 * s), Vector2(-9.5 * s * flick, 0.0), Vector2(-7.8 * s * flick, 1.2 * s)])
			draw_colored_polygon(exhaust, Color(0.42, 0.96, 1.0, 0.90))
			var body := PackedVector2Array([Vector2(-3.4 * s, -0.95 * s), Vector2(3.6 * s, -0.75 * s), Vector2(6.2 * s, 0.0), Vector2(3.6 * s, 0.75 * s), Vector2(-3.4 * s, 0.95 * s)])
			draw_colored_polygon(body, Color(0.92, 0.96, 1.0, 1.0))
			var nose := PackedVector2Array([Vector2(3.6 * s, -0.75 * s), Vector2(6.4 * s, 0.0), Vector2(3.6 * s, 0.75 * s)])
			draw_colored_polygon(nose, Color(0.24, 0.88, 1.0, 1.0))
			var f1 := PackedVector2Array([Vector2(-3.4 * s, -0.95 * s), Vector2(-4.4 * s, -2.5 * s), Vector2(-1.8 * s, -0.95 * s)])
			var f2 := PackedVector2Array([Vector2(-3.4 * s, 0.95 * s), Vector2(-4.4 * s, 2.5 * s), Vector2(-1.8 * s, 0.95 * s)])
			draw_colored_polygon(f1, Color(0.24, 0.76, 0.96, 0.98))
			draw_colored_polygon(f2, Color(0.24, 0.76, 0.96, 0.98))
		MissileUnit.KIND_HYDROGEN:
			# Heavy thermonuclear ICBM: side fins, slate-silver body, brass collar, crimson warhead
			var flame := PackedVector2Array([Vector2(-5.5 * s, -1.5 * s), Vector2(-12.5 * s * flick, -2.1 * s), Vector2(-15.5 * s * flick, 0.0), Vector2(-12.5 * s * flick, 2.1 * s), Vector2(-5.5 * s, 1.5 * s)])
			draw_colored_polygon(flame, Color(1.0, 0.68, 0.16, 0.92))
			var body_h := PackedVector2Array([Vector2(-5.8 * s, -1.9 * s), Vector2(4.6 * s, -1.6 * s), Vector2(4.6 * s, 1.6 * s), Vector2(-5.8 * s, 1.9 * s)])
			draw_colored_polygon(body_h, Color(0.82, 0.86, 0.92, 1.0))
			draw_rect(Rect2(Vector2(1.4 * s, -1.6 * s), Vector2(1.4 * s, 3.2 * s)), Color(0.95, 0.78, 0.24, 1.0), true)
			var nose_h := PackedVector2Array([Vector2(4.6 * s, -1.6 * s), Vector2(8.8 * s, 0.0), Vector2(4.6 * s, 1.6 * s)])
			draw_colored_polygon(nose_h, Color(0.96, 0.22, 0.22, 1.0))
			var hf1 := PackedVector2Array([Vector2(-5.8 * s, -1.9 * s), Vector2(-7.2 * s, -4.1 * s), Vector2(-2.4 * s, -1.8 * s)])
			var hf2 := PackedVector2Array([Vector2(-5.8 * s, 1.9 * s), Vector2(-7.2 * s, 4.1 * s), Vector2(-2.4 * s, 1.8 * s)])
			draw_colored_polygon(hf1, Color(0.54, 0.20, 0.22, 1.0))
			draw_colored_polygon(hf2, Color(0.54, 0.20, 0.22, 1.0))
		MissileUnit.KIND_MIRV:
			# Wide multi-warhead carrier fairing + twin plumes
			var plume := PackedVector2Array([Vector2(-5.2 * s, -1.8 * s), Vector2(-12.0 * s * flick, 0.0), Vector2(-5.2 * s, 1.8 * s)])
			draw_colored_polygon(plume, Color(1.0, 0.48, 0.18, 0.92))
			var hull := PackedVector2Array([Vector2(-5.5 * s, -2.3 * s), Vector2(3.8 * s, -2.0 * s), Vector2(8.2 * s, 0.0), Vector2(3.8 * s, 2.0 * s), Vector2(-5.5 * s, 2.3 * s)])
			draw_colored_polygon(hull, Color(0.24, 0.28, 0.36, 1.0))
			var cap := PackedVector2Array([Vector2(3.8 * s, -2.0 * s), Vector2(8.4 * s, 0.0), Vector2(3.8 * s, 2.0 * s)])
			draw_colored_polygon(cap, Color(0.98, 0.72, 0.18, 1.0))
			draw_rect(Rect2(Vector2(-2.5 * s, -2.2 * s), Vector2(2.4 * s, 4.4 * s)), Color(0.95, 0.26, 0.28, 0.96), true)
		MissileUnit.KIND_MIRV_WARHEAD:
			# Compact re-entry cone dart
			var r_flame := PackedVector2Array([Vector2(-2.2 * s, -0.8 * s), Vector2(-6.5 * s * flick, 0.0), Vector2(-2.2 * s, 0.8 * s)])
			draw_colored_polygon(r_flame, Color(1.0, 0.78, 0.26, 0.94))
			var cone := PackedVector2Array([Vector2(-2.4 * s, -1.2 * s), Vector2(4.2 * s, 0.0), Vector2(-2.4 * s, 1.2 * s)])
			draw_colored_polygon(cone, Color(0.98, 0.28, 0.22, 1.0))
		_:
			# Atom tactical ballistic missile
			var a_flame := PackedVector2Array([Vector2(-4.4 * s, -1.1 * s), Vector2(-10.2 * s * flick, 0.0), Vector2(-4.4 * s, 1.1 * s)])
			draw_colored_polygon(a_flame, Color(1.0, 0.56, 0.16, 0.92))
			var a_body := PackedVector2Array([Vector2(-4.6 * s, -1.4 * s), Vector2(3.6 * s, -1.25 * s), Vector2(3.6 * s, 1.25 * s), Vector2(-4.6 * s, 1.4 * s)])
			draw_colored_polygon(a_body, Color(0.88, 0.90, 0.94, 1.0))
			var a_nose := PackedVector2Array([Vector2(3.6 * s, -1.25 * s), Vector2(7.0 * s, 0.0), Vector2(3.6 * s, 1.25 * s)])
			draw_colored_polygon(a_nose, Color(0.96, 0.24, 0.22, 1.0))
			var af1 := PackedVector2Array([Vector2(-4.6 * s, -1.4 * s), Vector2(-5.8 * s, -3.1 * s), Vector2(-1.9 * s, -1.35 * s)])
			var af2 := PackedVector2Array([Vector2(-4.6 * s, 1.4 * s), Vector2(-5.8 * s, 3.1 * s), Vector2(-1.9 * s, 1.35 * s)])
			draw_colored_polygon(af1, Color(0.68, 0.22, 0.24, 1.0))
			draw_colored_polygon(af2, Color(0.68, 0.22, 0.24, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if is_intercepted:
		var xr: float = (3.5 if m.kind == MissileUnit.KIND_MIRV_WARHEAD else 5.5) * s
		var x_col := Color(1.0, 0.31, 0.31, 0.95)
		draw_line(m.pos - Vector2(xr, xr), m.pos + Vector2(xr, xr), x_col, 1.3 * s)
		draw_line(m.pos - Vector2(xr, -xr), m.pos + Vector2(xr, -xr), x_col, 1.3 * s)


func _draw_crosshair(center: Vector2, r: float, col: Color, inv_z: float) -> void:
	draw_arc(center, r * 0.72, 0.0, TAU, 20, col, 1.4 * inv_z)
	draw_line(center - Vector2(r, 0.0), center - Vector2(r * 0.35, 0.0), col, 1.5 * inv_z)
	draw_line(center + Vector2(r * 0.35, 0.0), center + Vector2(r, 0.0), col, 1.5 * inv_z)
	draw_line(center - Vector2(0.0, r), center - Vector2(0.0, r * 0.35), col, 1.5 * inv_z)
	draw_line(center + Vector2(0.0, r * 0.35), center + Vector2(0.0, r), col, 1.5 * inv_z)
