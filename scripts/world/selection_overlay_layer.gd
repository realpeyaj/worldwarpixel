class_name SelectionOverlayLayer
extends Node2D
## Layer 6 renderer: spawn-dot reticle, structure build validity ring,
## cached irregular organic Factory range contour, and live Naval Landing Crosshair preview.

var _world_state: WorldState
var _camera: Camera2D
var _selected_structure_id: int = 0
var _selected_ship_id: int = 0
var _build_mode: String = ""
var _missile_mode: String = ""
var _hover_sim_cell: Vector2i = Vector2i(-1, -1)
var _staged_missile_cell: Vector2i = Vector2i(-1, -1)
var _naval_preview: Dictionary = {}
var _elapsed: float = 0.0
var _cached_fac_key: String = ""
var _cached_fac_poly: PackedVector2Array = PackedVector2Array()


func setup(world_state: WorldState, camera: Camera2D) -> void:
	_world_state = world_state
	_camera = camera


func set_selected_structure(sid: int) -> void:
	_selected_structure_id = sid
	queue_redraw()


func set_selected_ship(sid: int) -> void:
	_selected_ship_id = sid
	queue_redraw()


func set_build_mode(mode: String) -> void:
	_build_mode = mode
	_refresh_naval_preview()
	queue_redraw()


func set_missile_mode(kind: String) -> void:
	_missile_mode = kind
	_refresh_naval_preview()
	queue_redraw()


func set_staged_missile_cell(cell: Vector2i) -> void:
	_staged_missile_cell = cell
	queue_redraw()


func set_hover_cell(cell: Vector2i) -> void:
	if _hover_sim_cell == cell:
		return
	_hover_sim_cell = cell
	_refresh_naval_preview()
	queue_redraw()


func _refresh_naval_preview() -> void:
	# Free-hand hover does not display naval crosshairs or sea paths; only explicit clicks show paths on active ships.
	_naval_preview = {}


func _get_sam_highlight_colors(sam_nation_id: int) -> Array[Color]:
	var p_id: int = _world_state.player_nation_id
	if sam_nation_id == p_id:
		return [Color(0.20, 0.92, 0.44, 0.14), Color(0.28, 0.96, 0.48, 0.86)]
	if _world_state.are_allied(p_id, sam_nation_id):
		return [Color(0.26, 0.64, 1.0, 0.14), Color(0.36, 0.76, 1.0, 0.86)]
	return [Color(0.96, 0.24, 0.22, 0.15), Color(1.0, 0.30, 0.26, 0.88)]


func _draw_sam_range_circle(st: StructureData, inv_z: float) -> void:
	var st_pos: Vector2 = st.get_world_pos()
	var sr: float = st.get_sam_radius() * 2.0
	var cols: Array[Color] = _get_sam_highlight_colors(st.nation_id)
	draw_circle(st_pos, sr, cols[0])
	var sam_dashes := 20
	var sam_step: float = TAU / float(sam_dashes)
	var sam_rot: float = _elapsed * 0.9
	for s_i in range(sam_dashes):
		var a0: float = sam_rot + float(s_i) * sam_step
		draw_arc(st_pos, sr, a0, a0 + sam_step * 0.65, 4, cols[1], 1.6 * inv_z)


func _process(delta: float) -> void:
	_elapsed += delta
	if _selected_structure_id > 0 or _selected_ship_id > 0 or _build_mode != "" or _missile_mode != "" or (_world_state != null and _world_state.match_phase == WorldState.PHASE_SPAWN_SELECT):
		queue_redraw()


func _draw() -> void:
	if _world_state == null:
		return
	var z: float = _camera.zoom.x if _camera != null else 1.0
	var inv_z: float = 1.0 / maxf(z, 1.0)

	# 1. Spawn reticle during SPAWN_SELECT
	if _world_state.match_phase == WorldState.PHASE_SPAWN_SELECT and _hover_sim_cell.x >= 0:
		var valid: bool = _world_state.is_land_cell(_hover_sim_cell.x, _hover_sim_cell.y)
		var pos: Vector2 = _world_state.sim_to_world(_hover_sim_cell)
		var col := Color(0.28, 0.94, 0.56, 0.92) if valid else Color(0.95, 0.32, 0.32, 0.85)
		var pulse: float = 8.0 + 1.5 * sin(_elapsed * 5.0)
		draw_arc(pos, pulse * inv_z, 0.0, TAU, 28, col, 1.8 * inv_z)
		draw_circle(pos, 2.8 * inv_z, col)

	# 2. Missile Targeting Crosshair, All SAM Range Highlights (Enemy=Red, Mine=Green, Ally=Blue) & Double-Click Lock
	elif _world_state.match_phase == WorldState.PHASE_PLAYING and _missile_mode != "":
		for sid_k: int in _world_state.structures.keys():
			var sam_st: StructureData = _world_state.structures[sid_k]
			if sam_st.type == StructureData.TYPE_SAM_LAUNCHER and not sam_st.is_constructing and sam_st.level > 0:
				_draw_sam_range_circle(sam_st, inv_z)
		if _hover_sim_cell.x >= 0 or _staged_missile_cell.x >= 0:
			var aim_cell: Vector2i = _staged_missile_cell if _staged_missile_cell.x >= 0 else _hover_sim_cell
			var pos: Vector2 = _world_state.sim_to_world(aim_cell)
			var blast_r: float = float(MissileUnit.get_blast_radius(_missile_mode)) * 2.0
			var pulse: float = 0.78 + 0.22 * sin(_elapsed * 7.0)
			var silo_ref: StructureData = _world_state.find_ready_silo(_world_state.player_nation_id, aim_cell)
			var ready_ok: bool = (silo_ref != null and silo_ref.action_cooldown_ticks == 0)
			if silo_ref != null:
				var silo_pos: Vector2 = silo_ref.get_world_pos()
				var preview_m := MissileUnit.new()
				preview_m.id = silo_ref.id
				preview_m.kind = _missile_mode
				preview_m.start_pos = silo_pos
				preview_m.target_pos = pos
				preview_m.target_cell = aim_cell
				preview_m.compute_ballistic_curve(false)

				var curve_steps := 28
				var curve_pts := PackedVector2Array()
				curve_pts.resize(curve_steps + 1)
				for ci in range(curve_steps + 1):
					curve_pts[ci] = preview_m.get_curve_point(float(ci) / float(curve_steps))

				# Check if curved pre-selection path crosses any enemy SAM range
				var p_id: int = _world_state.player_nation_id
				var sam_warnings: Array[Vector2] = []
				for sid_s: int in _world_state.structures.keys():
					var sam_chk: StructureData = _world_state.structures[sid_s]
					if sam_chk.type != StructureData.TYPE_SAM_LAUNCHER or sam_chk.is_constructing or sam_chk.level <= 0:
						continue
					if sam_chk.nation_id == p_id or _world_state.are_allied(p_id, sam_chk.nation_id):
						continue
					var sam_w: Vector2 = sam_chk.get_world_pos()
					var sam_rw: float = sam_chk.get_sam_radius() * 2.0
					for ci in range(curve_steps + 1):
						if curve_pts[ci].distance_to(sam_w) <= sam_rw:
							sam_warnings.append(curve_pts[ci])
							break

				var line_col := Color(1.0, 0.28, 0.24, 0.84) if not sam_warnings.is_empty() else Color(1.0, 0.52, 0.26, 0.68 if ready_ok else 0.30)
				for ci in range(curve_steps):
					if ci % 2 == 0:
						draw_line(curve_pts[ci], curve_pts[ci + 1], line_col, 1.5 * inv_z, true)

				# Draw X warning mark at each enemy SAM range crossing along the curved path
				var x_sz: float = (5.2 + 1.0 * sin(_elapsed * 9.0)) * inv_z
				for w_pt: Vector2 in sam_warnings:
					draw_circle(w_pt, x_sz * 1.45, Color(0.08, 0.03, 0.04, 0.82))
					draw_arc(w_pt, x_sz * 1.45, 0.0, TAU, 20, Color(1.0, 0.24, 0.22, 0.95), 1.4 * inv_z)
					draw_line(w_pt - Vector2(x_sz, x_sz), w_pt + Vector2(x_sz, x_sz), Color(1.0, 0.88, 0.24, 0.98), 2.1 * inv_z, true)
					draw_line(w_pt - Vector2(x_sz, -x_sz), w_pt + Vector2(x_sz, -x_sz), Color(1.0, 0.88, 0.24, 0.98), 2.1 * inv_z, true)
			var red_col := Color(1.0, 0.30, 0.24, 0.92 * pulse) if ready_ok else Color(0.70, 0.32, 0.32, 0.75)
			draw_circle(pos, blast_r, Color(1.0, 0.24, 0.18, 0.14 if _staged_missile_cell.x < 0 else 0.26))
			draw_arc(pos, blast_r, 0.0, TAU, 36, red_col, (2.4 if _staged_missile_cell.x >= 0 else 1.8) * inv_z)
			if _staged_missile_cell.x >= 0:
				draw_arc(pos, blast_r * 0.55, 0.0, TAU, 24, Color(1.0, 0.88, 0.28, 0.92 * pulse), 1.6 * inv_z)
			_draw_crosshair(pos, 11.0 * inv_z, red_col, inv_z)

	# 3. Build placement validity ring + Defense/Factory range preview (SAM range hidden unless SAM is clicked or in missile mode)
	elif _world_state.match_phase == WorldState.PHASE_PLAYING and _build_mode != "" and _hover_sim_cell.x >= 0:
		var pos: Vector2 = _world_state.sim_to_world(_hover_sim_cell)
		var valid := false
		if _build_mode == "warship":
			valid = _world_state.sea_pathfinder.find_nearest_nav_cell(_hover_sim_cell, 8).x >= 0
		else:
			var check: Dictionary = _world_state.can_place_structure(
				_world_state.player_nation_id, _build_mode, _hover_sim_cell.x, _hover_sim_cell.y
			)
			valid = bool(check.get("ok", false))
		if _build_mode == StructureData.TYPE_FACTORY:
			var preview_st := StructureData.new()
			preview_st.id = _world_state.structures.size() + 1
			preview_st.cell = _hover_sim_cell
			preview_st.level = 1
			_draw_irregular_factory_range(preview_st, inv_z, Color(1.0, 0.78, 0.30, 0.12), Color(1.0, 0.78, 0.30, 0.65))
		elif _build_mode == StructureData.TYPE_DEFENSE_POST:
			var dr: float = 27.5 * 2.0
			draw_circle(pos, dr, Color(0.45, 0.74, 1.0, 0.10))
			draw_arc(pos, dr, 0.0, TAU, 32, Color(0.45, 0.76, 1.0, 0.68), 1.5 * inv_z)

		var col := Color(0.28, 0.94, 0.56, 0.92) if valid else Color(0.95, 0.34, 0.34, 0.88)
		draw_arc(pos, 8.5 * inv_z, 0.0, TAU, 28, col, 1.8 * inv_z)
		draw_circle(pos, 2.5 * inv_z, col)

	# 4. Selected Structure highlight + cached irregular Factory / Defense / clicked SAM aura
	if _selected_structure_id > 0:
		var st: StructureData = _world_state.get_structure(_selected_structure_id)
		if st != null:
			var st_pos: Vector2 = st.get_world_pos()
			if st.type == StructureData.TYPE_FACTORY:
				_draw_irregular_factory_range(st, inv_z, Color(1.0, 0.78, 0.30, 0.10), Color(1.0, 0.82, 0.38, 0.72))
			elif st.type == StructureData.TYPE_DEFENSE_POST and st.level > 0:
				var dr: float = st.get_defense_radius() * 2.0
				draw_circle(st_pos, dr, Color(0.45, 0.74, 1.0, 0.11))
				draw_arc(st_pos, dr, 0.0, TAU, 36, Color(0.45, 0.78, 1.0, 0.78), 1.6 * inv_z)
				draw_arc(st_pos, dr * 0.55, 0.0, TAU, 24, Color(0.45, 0.78, 1.0, 0.28), 1.0 * inv_z)
			elif st.type == StructureData.TYPE_SAM_LAUNCHER and st.level > 0 and _missile_mode == "":
				_draw_sam_range_circle(st, inv_z)
			var pulse: float = 0.8 + 0.2 * sin(_elapsed * 5.0)
			draw_arc(st_pos, 11.5 * inv_z, 0.0, TAU, 28, Color(1.0, 0.88, 0.38, 0.95 * pulse), 2.0 * inv_z)

	# 6. Selected Warship Patrol Range & Manual Destination Route
	if _selected_ship_id > 0:
		var sh: ShipUnit = _world_state.ships.get(_selected_ship_id, null)
		if sh != null and sh.active and sh.kind == ShipUnit.KIND_WARSHIP:
			var p_center: Vector2 = sh.patrol_center if sh.patrol_center != Vector2.ZERO else sh.position
			if sh.manual_moving and sh.waypoint_index < sh.waypoints.size():
				var route_pts := PackedVector2Array([sh.position])
				for wi in range(sh.waypoint_index, sh.waypoints.size()):
					route_pts.append(sh.waypoints[wi])
				if route_pts.size() >= 2:
					draw_polyline(route_pts, Color(0.45, 0.94, 1.0, 0.72), 1.4 * inv_z, false)
			draw_arc(p_center, sh.patrol_radius, 0.0, TAU, 36, Color(0.38, 0.92, 1.0, 0.48), 1.4 * inv_z)
			var ring_z: float = minf(1.0, 1.0 / maxf(z, 0.25))
			draw_arc(sh.position, 11.0 * ring_z, 0.0, TAU, 24, Color(1.0, 0.88, 0.36, 0.92), 1.5 * ring_z)


func _draw_irregular_factory_range(st: StructureData, inv_z: float, fill_col: Color, rim_col: Color) -> void:
	var key := "%d_%d_%d_%d" % [st.id, st.cell.x, st.cell.y, maxi(1, st.level)]
	if _cached_fac_key != key:
		var poly: PackedVector2Array = st.get_organic_range_polygon(56)
		if poly.size() < 3:
			return
		var closed := poly.duplicate()
		closed.append(poly[0])
		_cached_fac_key = key
		_cached_fac_poly = closed
	draw_colored_polygon(_cached_fac_poly, fill_col)
	draw_polyline(_cached_fac_poly, rim_col, 1.5 * inv_z, false)


func _draw_crosshair(center: Vector2, r: float, col: Color, inv_z: float) -> void:
	draw_arc(center, r * 0.75, 0.0, TAU, 24, col, 1.6 * inv_z)
	draw_line(center - Vector2(r, 0.0), center - Vector2(r * 0.32, 0.0), col, 1.6 * inv_z)
	draw_line(center + Vector2(r * 0.32, 0.0), center + Vector2(r, 0.0), col, 1.6 * inv_z)
	draw_line(center - Vector2(0.0, r), center - Vector2(0.0, r * 0.32), col, 1.6 * inv_z)
	draw_line(center + Vector2(0.0, r * 0.32), center + Vector2(0.0, r), col, 1.6 * inv_z)
