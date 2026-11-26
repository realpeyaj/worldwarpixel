class_name WorldState
extends RefCounted
## Authoritative free-world simulation state and command validator.
## Supports circular-organic expansion, closest-shore sea crossings with crosshairs,
## irregular Factory links & cross-island Bridges, and instant Lv.1-10 upgrades at 24 Hz.

signal world_loaded
signal match_started
signal simulation_ticked(tick: int)
signal territory_changed
signal nation_spawned(nation_id: int)
signal expansion_updated
signal structure_changed(structure_id: int)
signal structure_upgraded(structure_id: int, new_level: int)
signal factory_link_created(is_bridge: bool)
signal ship_launched(ship_id: int)
signal trade_completed(nation_id: int, world_pos: Vector2, gold_amount: float)
signal structure_income_popup(nation_id: int, world_pos: Vector2, gold_amount: float, structure_type: String)
signal victory_reached(winner_nation_id: int, territory_percent: float)
signal command_rejected(reason: String)
signal naval_shot_fired(world_pos: Vector2)
signal ship_destroyed(world_pos: Vector2, kind: String)
signal trade_ship_captured(captor_nation_id: int, world_pos: Vector2, gold_amount: float)
signal missile_launched(missile_id: int, kind: String)
signal missile_detonated(world_pos: Vector2, radius_world: float, kind: String)
signal missile_intercepted(world_pos: Vector2)
signal attack_countered(defender_id: int, attacker_id: int, enemy_troops_destroyed: float, repelled: bool)
signal diplomacy_changed
signal alliance_requested(from_nation_id: int, to_nation_id: int)
signal diplomacy_event(message: String, is_warning: bool)
signal nation_eliminated(nation_id: int, conqueror_id: int)
signal player_land_conquered(cells_claimed: int, is_contested: bool)
signal player_territory_attacked(attacker_id: int, cells_lost: int)

const TICK_RATE_HZ := SimulationClock.TICK_RATE_HZ
const TICK_DT := SimulationClock.TICK_INTERVAL

const GRID_PATH := "res://data/world/world_grid.bin"
const NAV_PATH := "res://data/world/ocean_nav.bin"
const META_PATH := "res://data/world/world_meta.json"

const PHASE_SPAWN_SELECT := 0
const PHASE_PLAYING := 1
const PHASE_VICTORY := 2

const T_OCEAN := 0
const T_LAKE := 1
const T_PLAINS := 2
const T_FOREST := 3
const T_JUNGLE := 4
const T_HILLS := 5
const T_MOUNTAINS := 6
const T_DESERT := 7
const T_TUNDRA := 8
const T_POLAR_ICE := 9

const TERRAIN_NAMES := {
	T_OCEAN: "Open Ocean",
	T_LAKE: "Inland Lake",
	T_PLAINS: "Plains",
	T_FOREST: "Forest",
	T_JUNGLE: "Jungle",
	T_HILLS: "Hills",
	T_MOUNTAINS: "Mountains",
	T_DESERT: "Desert",
	T_TUNDRA: "Tundra",
	T_POLAR_ICE: "Polar Ice",
}

const TERRAIN_COST := {
	T_PLAINS: 1.0,
	T_FOREST: 1.28,
	T_HILLS: 1.38,
	T_DESERT: 1.42,
	T_TUNDRA: 1.50,
	T_JUNGLE: 1.55,
	T_POLAR_ICE: 1.65,
	T_MOUNTAINS: 2.05,
}

const VICTORY_THRESHOLD_PERCENT := 80.0
const FALLOUT_TROOP_COST_MULT := 2.4
const NEUTRAL_EXPLORE_TROOP_COST_MULT := 1.85
const MAX_ACTIVE_EXPANSIONS_PER_NATION := 3
const MAX_ACTIVE_TRADE_SHIPS := 150
const MIN_STRUCTURE_SPACING_CELLS := 8
const NATION_LABEL_MIN_SCALE := 0.65
const NATION_LABEL_MAX_SCALE := 1.55
const SHIP_SPEED_PX_SEC := 22.0
const ALLIANCE_DURATION_TICKS := 7200
const ALLIANCE_REQUEST_TTL_TICKS := 720
const BETRAYAL_DURATION_TICKS := 1440
const NATION_COLOR_PALETTE: Array[String] = [
	"#3b82f6", "#ef4444", "#22c55e", "#eab308",
	"#a855f7", "#06b6d4", "#f97316", "#ec4899",
	"#84cc16", "#14b8a6", "#f43f5e", "#6366f1",
	"#d97706", "#10b981", "#e879f9", "#0ea5e9",
	"#fb7185", "#facc15", "#34d399", "#818cf8",
	"#fb923c", "#2dd4bf", "#c084fc", "#f87171",
]

var sim_width: int = 2048
var sim_height: int = 1024
var sim_scale: float = 1.0
var map_size: Vector2 = Vector2(2048.0, 1024.0)

var terrain_grid: PackedByteArray = PackedByteArray()
var owner_grid: PackedByteArray = PackedByteArray()
var fallout_grid: PackedByteArray = PackedByteArray()
var render_owner_grid: PackedByteArray = PackedByteArray()
var coastal_grid: PackedByteArray = PackedByteArray()
var landmass_grid: PackedInt32Array = PackedInt32Array()
var row_area_km2: PackedFloat64Array = PackedFloat64Array()

var total_land_cells: int = 0
var total_conquerable_area_km2: float = 0.0
var fallout_cell_count: int = 0
var region_labels: Array = []
var ai_spawn_candidates: Array[Vector2i] = []

var sea_pathfinder := SeaPathfinder.new()
var match_phase: int = PHASE_SPAWN_SELECT
var current_tick: int = 0
var player_nation_id: int = 1
var winner_nation_id: int = 0

var nations: Dictionary = {}        # int -> NationData
var structures: Dictionary = {}     # int -> StructureData
var expansions: Dictionary = {}     # int -> ExpansionOrder
var ships: Dictionary = {}          # int -> ShipUnit
var missiles: Dictionary = {}       # int -> MissileUnit
var naval_shells: Array[Dictionary] = []
var trains: Array[Dictionary] = []
var factory_links: Array[Dictionary] = []

var match_seed: int = 0
var winner_team_id: int = 0
var game_speed: float = 1.0
var no_nukes: bool = false
var ai_difficulty: String = "normal"
var start_preset: String = "standard"
var match_history: Array[Dictionary] = []
var last_player_threat_world_pos: Vector2 = Vector2(-1.0, -1.0)
var _rng := RandomNumberGenerator.new()
var _nation_borders: Dictionary = {}     # int -> Dictionary (cell_idx -> true)
var _nation_coasts: Dictionary = {}      # int -> Dictionary (cell_idx -> true)
var _nation_landmasses: Dictionary = {}  # int -> Dictionary (landmass_id -> int count)
var _prev_link_keys: Dictionary = {}
var _road_cache: Dictionary = {}
var _station_road_adj: Dictionary = {}     # station_id -> Array[Dictionary] directed road edges
var _factory_train_routes: Dictionary = {} # factory_id -> Array[Dictionary] BFS 1..8-hop train routes
var _factory_route_cursor: Dictionary = {} # factory_id -> int round-robin route cursor
var _landmass_coasts: Dictionary = {}    # int (lm_id) -> PackedInt32Array of navigable coastal cell indices
var _next_nation_id: int = 1
var _next_structure_id: int = 1
var _next_expansion_id: int = 1
var _next_ship_id: int = 1
var _next_missile_id: int = 1
var _next_shell_id: int = 1
var _next_train_id: int = 1
var owner_dirty: bool = false
var _factory_links_dirty: bool = false
var _economy_dirty: bool = false


func load_world(meta_path: String = META_PATH, grid_path: String = GRID_PATH, nav_path: String = NAV_PATH) -> bool:
	var mf := FileAccess.open(meta_path, FileAccess.READ)
	if mf == null:
		push_error("Failed to open world_meta.json: %s" % meta_path)
		return false
	var parsed: Variant = JSON.parse_string(mf.get_as_text())
	mf.close()
	if not (parsed is Dictionary):
		push_error("Invalid world_meta.json format.")
		return false
	var meta := parsed as Dictionary

	sim_width = int(meta.get("sim_width", 2048))
	sim_height = int(meta.get("sim_height", 1024))
	map_size = Vector2(float(meta.get("map_width", 2048)), float(meta.get("map_height", 1024)))
	sim_scale = map_size.x / float(maxi(sim_width, 1))
	var nav_w: int = int(meta.get("nav_width", 1024))
	var nav_h: int = int(meta.get("nav_height", 512))
	region_labels = meta.get("region_labels", [])

	ai_spawn_candidates.clear()
	for pt_dict: Dictionary in meta.get("ai_spawn_candidates", []):
		ai_spawn_candidates.append(Vector2i(int(pt_dict.get("x", 0)), int(pt_dict.get("y", 0))))

	var gf := FileAccess.open(grid_path, FileAccess.READ)
	if gf == null:
		push_error("Failed to open world_grid.bin: %s" % grid_path)
		return false
	terrain_grid = gf.get_buffer(sim_width * sim_height)
	gf.close()
	if terrain_grid.size() != sim_width * sim_height:
		push_error("world_grid.bin size mismatch.")
		return false

	if not sea_pathfinder.load_nav_grid(nav_path, nav_w, nav_h, sim_width):
		return false

	_init_row_areas()
	_precompute_coast_and_landmasses()
	reset_match()
	world_loaded.emit()
	return true


func reset_match() -> void:
	owner_grid.resize(sim_width * sim_height)
	owner_grid.fill(0)
	fallout_grid.resize(sim_width * sim_height)
	fallout_grid.fill(0)
	render_owner_grid.resize(sim_width * sim_height)
	render_owner_grid.fill(0)
	fallout_cell_count = 0
	nations.clear()
	structures.clear()
	expansions.clear()
	ships.clear()
	missiles.clear()
	naval_shells.clear()
	trains.clear()
	factory_links.clear()
	_nation_borders.clear()
	_nation_coasts.clear()
	_nation_landmasses.clear()
	_prev_link_keys.clear()
	_road_cache.clear()
	_station_road_adj.clear()
	_factory_train_routes.clear()
	_factory_route_cursor.clear()
	_next_nation_id = 1
	_next_structure_id = 1
	_next_expansion_id = 1
	_next_ship_id = 1
	_next_missile_id = 1
	_next_shell_id = 1
	_next_train_id = 1
	match_seed = 0
	player_nation_id = 1
	winner_nation_id = 0
	winner_team_id = 0
	game_speed = 1.0
	no_nukes = false
	ai_difficulty = "normal"
	start_preset = "standard"
	match_history.clear()
	last_player_threat_world_pos = Vector2(-1.0, -1.0)
	current_tick = 0
	match_phase = PHASE_SPAWN_SELECT
	owner_dirty = true
	_factory_links_dirty = false
	_economy_dirty = false


func _init_row_areas() -> void:
	row_area_km2.resize(sim_height)
	var r_earth := 6371.0
	var d_lon: float = TAU / float(sim_width)
	var d_lat: float = PI / float(sim_height)
	for y in range(sim_height):
		var lat_rad: float = deg_to_rad(90.0 - ((float(y) + 0.5) / float(sim_height)) * 180.0)
		row_area_km2[y] = (r_earth * r_earth) * d_lon * d_lat * maxf(cos(lat_rad), 0.01)

	total_land_cells = 0
	total_conquerable_area_km2 = 0.0
	for y in range(sim_height):
		var row_off: int = y * sim_width
		var r_area: float = row_area_km2[y]
		for x in range(sim_width):
			if terrain_grid[row_off + x] >= T_PLAINS:
				total_land_cells += 1
				total_conquerable_area_km2 += r_area


func _precompute_coast_and_landmasses() -> void:
	var n_cells: int = sim_width * sim_height
	coastal_grid.resize(n_cells)
	coastal_grid.fill(0)
	landmass_grid.resize(n_cells)
	landmass_grid.fill(0)
	_landmass_coasts.clear()

	var all_coasts := PackedInt32Array()
	var lm_id: int = 0
	var queue := PackedInt32Array()
	for start_idx in range(n_cells):
		if terrain_grid[start_idx] < T_PLAINS:
			continue
		var sy: int = int(start_idx / sim_width)
		var sx: int = start_idx % sim_width
		var touches_ocean := false
		if sx > 0 and terrain_grid[start_idx - 1] == T_OCEAN:
			touches_ocean = true
		elif sx < sim_width - 1 and terrain_grid[start_idx + 1] == T_OCEAN:
			touches_ocean = true
		elif sy > 0 and terrain_grid[start_idx - sim_width] == T_OCEAN:
			touches_ocean = true
		elif sy < sim_height - 1 and terrain_grid[start_idx + sim_width] == T_OCEAN:
			touches_ocean = true
		elif sx > 0 and sy > 0 and terrain_grid[start_idx - sim_width - 1] == T_OCEAN:
			touches_ocean = true
		elif sx < sim_width - 1 and sy > 0 and terrain_grid[start_idx - sim_width + 1] == T_OCEAN:
			touches_ocean = true
		elif sx > 0 and sy < sim_height - 1 and terrain_grid[start_idx + sim_width - 1] == T_OCEAN:
			touches_ocean = true
		elif sx < sim_width - 1 and sy < sim_height - 1 and terrain_grid[start_idx + sim_width + 1] == T_OCEAN:
			touches_ocean = true
		if touches_ocean:
			coastal_grid[start_idx] = 1
			all_coasts.append(start_idx)

		if landmass_grid[start_idx] != 0:
			continue
		lm_id += 1
		landmass_grid[start_idx] = lm_id
		queue.resize(0)
		queue.append(start_idx)
		var head := 0
		var w1: int = sim_width - 1
		var h1: int = sim_height - 1
		while head < queue.size():
			var curr: int = queue[head]
			head += 1
			var cx: int = curr % sim_width
			var cy: int = int(curr / sim_width)
			if cx > 0:
				var ni: int = curr - 1
				if terrain_grid[ni] >= T_PLAINS and landmass_grid[ni] == 0:
					landmass_grid[ni] = lm_id
					queue.append(ni)
			if cx < w1:
				var ni: int = curr + 1
				if terrain_grid[ni] >= T_PLAINS and landmass_grid[ni] == 0:
					landmass_grid[ni] = lm_id
					queue.append(ni)
			if cy > 0:
				var ni: int = curr - sim_width
				if terrain_grid[ni] >= T_PLAINS and landmass_grid[ni] == 0:
					landmass_grid[ni] = lm_id
					queue.append(ni)
			if cy < h1:
				var ni: int = curr + sim_width
				if terrain_grid[ni] >= T_PLAINS and landmass_grid[ni] == 0:
					landmass_grid[ni] = lm_id
					queue.append(ni)

	var tmp_coasts: Dictionary = {}
	for k in range(1, lm_id + 1):
		tmp_coasts[k] = []
	for idx: int in all_coasts:
		var lm_c: int = landmass_grid[idx]
		if lm_c > 0:
			(tmp_coasts[lm_c] as Array).append(idx)
	for k in range(1, lm_id + 1):
		_landmass_coasts[k] = PackedInt32Array(tmp_coasts[k])


func world_to_sim(world_pos: Vector2) -> Vector2i:
	var inv_s: float = 1.0 / maxf(sim_scale, 0.25)
	return Vector2i(
		clampi(int(floor(world_pos.x * inv_s)), 0, sim_width - 1),
		clampi(int(floor(world_pos.y * inv_s)), 0, sim_height - 1)
	)


func sim_to_world(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * sim_scale, (float(cell.y) + 0.5) * sim_scale)


func is_land_cell(sx: int, sy: int) -> bool:
	if sx < 0 or sy < 0 or sx >= sim_width or sy >= sim_height:
		return false
	return terrain_grid[sy * sim_width + sx] >= T_PLAINS


func get_terrain_at(sx: int, sy: int) -> int:
	if sx < 0 or sy < 0 or sx >= sim_width or sy >= sim_height:
		return T_OCEAN
	return terrain_grid[sy * sim_width + sx]


func get_owner_at(sx: int, sy: int) -> int:
	if sx < 0 or sy < 0 or sx >= sim_width or sy >= sim_height:
		return 0
	return owner_grid[sy * sim_width + sx]


func is_fallout_at(sx: int, sy: int) -> bool:
	if sx < 0 or sy < 0 or sx >= sim_width or sy >= sim_height:
		return false
	return fallout_grid[sy * sim_width + sx] > 0


func is_spawn_point_valid(sx: int, sy: int) -> bool:
	return is_land_cell(sx, sy)


func apply_command(cmd: Dictionary) -> Dictionary:
	var cmd_type: String = str(cmd.get("type", ""))
	match cmd_type:
		"spawn_player":
			return _cmd_spawn_player(cmd)
		"start_mp_match":
			return _cmd_start_mp_match(cmd)
		"expand_to":
			return _cmd_expand_to(cmd)
		"cancel_expansion":
			return _cmd_cancel_expansion(cmd)
		"cancel_ship":
			return _cmd_cancel_ship(cmd)
		"build_structure":
			return _cmd_build_structure(cmd)
		"upgrade_structure":
			return _cmd_upgrade_structure(cmd)
		"build_warship":
			return _cmd_build_warship(cmd)
		"command_warship":
			return _cmd_command_warship(cmd)
		"launch_missile":
			return _cmd_launch_missile(cmd)
		"request_alliance":
			return _cmd_request_alliance(cmd)
		"respond_alliance":
			return _cmd_respond_alliance(cmd)
		"break_alliance":
			return _cmd_break_alliance(cmd)
		"toggle_embargo":
			return _cmd_toggle_embargo(cmd)
		"donate_gold":
			return _cmd_donate_gold(cmd)
		"donate_troops":
			return _cmd_donate_troops(cmd)
	return _reject("Unsupported command: %s" % cmd_type)


func _shuffled_palette() -> Array[String]:
	var palette: Array[String] = NATION_COLOR_PALETTE.duplicate()
	for i in range(palette.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: String = palette[i]
		palette[i] = palette[j]
		palette[j] = tmp
	return palette


func _spawn_ai_nations(ai_count: int, spawned_pts: Array[Vector2i], palette: Array[String], palette_offset: int) -> void:
	var ai_idx := 0
	for min_dist_sq: float in [14400.0, 4900.0, 2500.0, 900.0]:
		for cand: Vector2i in ai_spawn_candidates:
			if ai_idx >= ai_count:
				return
			if not is_land_cell(cand.x, cand.y) or get_owner_at(cand.x, cand.y) != 0:
				continue
			var too_close := false
			for pt: Vector2i in spawned_pts:
				if cand.distance_squared_to(pt) < min_dist_sq:
					too_close = true
					break
			if too_close:
				continue
			var col := Color.from_string(palette[(ai_idx + palette_offset) % palette.size()], Color.ORANGE)
			var nm: String = AIController.AI_NAMES[ai_idx % AIController.AI_NAMES.size()]
			_create_nation(nm, col, false, cand, 49)
			spawned_pts.append(cand)
			ai_idx += 1


func _apply_match_options(opts: Dictionary) -> void:
	var spd: float = float(opts.get("game_speed", 1.0))
	game_speed = spd if spd in [1.0, 1.5, 2.0] else 1.0
	no_nukes = bool(opts.get("no_nukes", false))
	var diff: String = str(opts.get("ai_difficulty", "normal")).to_lower()
	ai_difficulty = diff if diff in ["normal", "hard", "brutal"] else "normal"
	var preset: String = str(opts.get("start_preset", "standard")).to_lower()
	start_preset = preset if preset in ["standard", "fast", "sandbox"] else "standard"


func _cmd_spawn_player(cmd: Dictionary) -> Dictionary:
	if match_phase != PHASE_SPAWN_SELECT:
		return _reject("Match has already started.")
	var sx: int = int(cmd.get("x", -1))
	var sy: int = int(cmd.get("y", -1))
	if not is_land_cell(sx, sy):
		return _reject("Cannot spawn in ocean or lakes — click any landmass (including islands or Antarctica).")

	_apply_match_options(cmd.get("options", cmd) as Dictionary)

	var p_name: String = str(cmd.get("name", "Terran Vanguard")).strip_edges()
	if p_name.is_empty():
		p_name = "Terran Vanguard"

	match_seed = int(cmd.get("seed", Time.get_ticks_usec()))
	_rng.seed = match_seed

	var palette: Array[String] = _shuffled_palette()
	var p_color := Color.from_string(palette[0], Color("#3b82f6"))
	var ai_count: int = clampi(int(cmd.get("ai_count", 6)), 0, 23)

	var p_nation := _create_nation(p_name, p_color, true, Vector2i(sx, sy), 49)
	player_nation_id = p_nation.id

	var spawned_pts: Array[Vector2i] = [Vector2i(sx, sy)]
	_spawn_ai_nations(ai_count, spawned_pts, palette, 1)

	match_phase = PHASE_PLAYING
	_recompute_all_economy_rates()
	territory_changed.emit()
	expansion_updated.emit()
	match_started.emit()
	return {"ok": true, "nation_id": player_nation_id}


func _cmd_start_mp_match(cmd: Dictionary) -> Dictionary:
	reset_match()
	_apply_match_options(cmd.get("options", cmd) as Dictionary)
	match_seed = int(cmd.get("seed", 1))
	_rng.seed = match_seed

	var palette: Array[String] = _shuffled_palette()
	var raw_players: Array = cmd.get("players", [])
	var sorted_players: Array = []
	for p_item: Variant in raw_players:
		if p_item is Dictionary:
			sorted_players.append(p_item)
	sorted_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("nation_id", 0)) < int(b.get("nation_id", 0))
	)

	var spawned_pts: Array[Vector2i] = []
	for i in range(sorted_players.size()):
		var pd: Dictionary = sorted_players[i]
		var nid: int = int(pd.get("nation_id", i + 1))
		var nm: String = str(pd.get("name", "Nation %d" % nid)).strip_edges()
		if nm.is_empty():
			nm = "Nation %d" % nid
		var sx: int = int(pd.get("x", -1))
		var sy: int = int(pd.get("y", -1))
		if not is_land_cell(sx, sy) or get_owner_at(sx, sy) != 0:
			for cand: Vector2i in ai_spawn_candidates:
				if is_land_cell(cand.x, cand.y) and get_owner_at(cand.x, cand.y) == 0:
					var far_ok := true
					for prev_pt: Vector2i in spawned_pts:
						if cand.distance_squared_to(prev_pt) < 6400.0:
							far_ok = false
							break
					if far_ok:
						sx = cand.x
						sy = cand.y
						break
		var col := Color.from_string(palette[i % palette.size()], Color("#3b82f6"))
		var mp_n := _create_nation(nm, col, true, Vector2i(sx, sy), 49, nid)
		mp_n.team_id = clampi(int(pd.get("team_id", 0)), 0, 4)
		spawned_pts.append(Vector2i(sx, sy))

	player_nation_id = int(cmd.get("local_nation_id", 1))
	var ai_count: int = clampi(int(cmd.get("ai_count", 4)), 0, 23)
	_spawn_ai_nations(ai_count, spawned_pts, palette, sorted_players.size())

	match_phase = PHASE_PLAYING
	_recompute_all_economy_rates()
	owner_dirty = true
	territory_changed.emit()
	match_started.emit()
	return {"ok": true, "nation_count": nations.size()}


func _create_nation(n_name: String, col: Color, is_player: bool, center: Vector2i, start_cells: int, forced_id: int = 0) -> NationData:
	var nid: int = forced_id if forced_id > 0 else _next_nation_id
	_next_nation_id = maxi(_next_nation_id, nid + 1)

	var n := NationData.new()
	n.id = nid
	n.name = n_name
	n.color = col
	n.is_player = is_player
	n.capital_cell = center
	n.label_cell = center
	n.label_dirty = true
	n.gold = 125000.0
	n.troops = 1500.0
	n.max_troops = 3200.0
	if start_preset == "fast":
		n.gold = 500000.0
		n.troops = 3000.0
		n.max_troops = 5500.0
	elif start_preset == "sandbox":
		n.gold = 5000000.0
		n.troops = 6000.0
		n.max_troops = 10000.0
	nations[nid] = n
	_nation_borders[nid] = {}
	_nation_coasts[nid] = {}
	_nation_landmasses[nid] = {}

	if start_cells == 49:
		_claim_spawn_circle(nid, center, 4.0)
	else:
		_claim_organic_dot(nid, center, start_cells)
	nation_spawned.emit(nid)
	return n


func _claim_spawn_circle(nid: int, center: Vector2i, radius_cells: float = 4.0) -> int:
	if not is_land_cell(center.x, center.y):
		return 0
	var r_i: int = int(ceil(radius_cells))
	var r2: float = radius_cells * radius_cells
	var claimed := 0
	for dy in range(-r_i, r_i + 1):
		var cy: int = center.y + dy
		if cy < 0 or cy >= sim_height:
			continue
		for dx in range(-r_i, r_i + 1):
			if float(dx * dx + dy * dy) > r2:
				continue
			var cx: int = center.x + dx
			if cx < 0 or cx >= sim_width:
				continue
			var idx: int = cy * sim_width + cx
			if terrain_grid[idx] >= T_PLAINS and owner_grid[idx] == 0:
				_set_cell_owner(idx, nid)
				claimed += 1
	return claimed


static func _can_order_claim_owner(order_target_owner: int, cell_owner: int, attacker_nid: int) -> bool:
	if cell_owner == attacker_nid:
		return false
	if order_target_owner == 0:
		return cell_owner == 0
	return cell_owner == order_target_owner


func _claim_organic_dot(nid: int, center: Vector2i, target_count: int, allowed_owner: int = 0) -> int:
	if not is_land_cell(center.x, center.y):
		return 0
	var start_idx: int = center.y * sim_width + center.x
	var order := ExpansionOrder.new()
	order.id = nid * 10000 + current_tick
	order.push_frontier(start_idx, 0.0, 0.0)

	var claimed := 0
	while claimed < target_count and order.frontier_size() > 0:
		var idx: int = order.pop_best()
		if terrain_grid[idx] < T_PLAINS or not _can_order_claim_owner(allowed_owner, owner_grid[idx], nid):
			continue
		_set_cell_owner(idx, nid)
		claimed += 1
		var cx: int = idx % sim_width
		var cy: int = int(idx / sim_width)
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if (dx != 0 and dy != 0) or (dx == 0 and dy == 0):
					continue
				var nx: int = cx + dx
				var ny: int = cy + dy
				if nx < 0 or ny < 0 or nx >= sim_width or ny >= sim_height:
					continue
				var n_idx: int = ny * sim_width + nx
				if terrain_grid[n_idx] >= T_PLAINS and _can_order_claim_owner(allowed_owner, owner_grid[n_idx], nid):
					var d: float = Vector2(nx - center.x, ny - center.y).length()
					var jitter: float = float(((n_idx * 73856093) ^ (nid * 19349663)) & 1023) / 1024.0 * 1.4
					order.push_frontier(n_idx, d + jitter, d)
	return claimed


func find_closest_owned_shore(nid: int, target_cell: Vector2i, required_lm: int = -1, preview_only: bool = false) -> Dictionary:
	"""Finds the fastest sea-time owned departure coast (considering sea detours & 1.25x Port speed) and valid A* route."""
	if target_cell.x < 0 or target_cell.y < 0 or target_cell.x >= sim_width or target_cell.y >= sim_height:
		return {"ok": false, "reason": "Destination out of bounds."}
	var t_idx: int = target_cell.y * sim_width + target_cell.x
	if terrain_grid[t_idx] < T_PLAINS:
		return {"ok": false, "reason": "Destination is not land."}

	var target_lm: int = landmass_grid[t_idx]
	var clicked_own: int = owner_grid[t_idx]
	var pref_owner: int = clicked_own if clicked_own != nid else -1
	var landing_spot: Vector2i = _find_coastal_landing_on_landmass(target_cell, target_lm, pref_owner)
	if landing_spot.x < 0:
		return {"ok": false, "reason": "Destination has no coastal landing zone."}
	var dest_nav: Vector2i = sea_pathfinder.find_nearest_nav_cell(landing_spot, 2)
	if dest_nav.x < 0:
		dest_nav = sea_pathfinder.find_nearest_nav_cell(landing_spot, 3)
	if dest_nav.x < 0:
		return {"ok": false, "reason": "No navigable ocean approach near landing site."}

	var coasts: Dictionary = _nation_coasts.get(nid, {})
	if coasts.is_empty():
		return {"ok": false, "reason": "Expand to a coastline first to launch boats across water."}

	if preview_only:
		var best_shore := Vector2i(-1, -1)
		var best_d2 := 1e12
		for idx_var in coasts.keys():
			var c_idx: int = int(idx_var)
			if owner_grid[c_idx] != nid:
				continue
			if required_lm > 0 and landmass_grid[c_idx] != required_lm:
				continue
			var cx: int = c_idx % sim_width
			var cy: int = int(c_idx / sim_width)
			var d2: float = float((cx - landing_spot.x) * (cx - landing_spot.x) + (cy - landing_spot.y) * (cy - landing_spot.y))
			if d2 < best_d2:
				best_d2 = d2
				best_shore = Vector2i(cx, cy)
		if best_shore.x < 0:
			return {"ok": false, "reason": "No coastal departure shore on source landmass."}
		return {
			"ok": true,
			"shore_cell": best_shore,
			"start_nav": best_shore,
			"landing_cell": landing_spot,
			"dest_nav": dest_nav,
			"route": PackedVector2Array([sim_to_world(best_shore), sim_to_world(landing_spot)]),
			"near_port": false,
		}

	# Diverse candidate selection: best per ocean-facing direction + spatially separated shores + Ports
	var dir_best_cell: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1)]
	var dir_best_d2: Array[float] = [1e12, 1e12, 1e12, 1e12]
	var near_shores: Array[Dictionary] = []  # [{"cell": Vector2i, "d2": float}] max 6 separated >= 28 cells
	var coast_keys: Array = coasts.keys()
	var c_total: int = coast_keys.size()
	var c_step: int = maxi(1, int(c_total / 2500))
	var ci := 0
	while ci < c_total:
		var c_idx: int = int(coast_keys[ci])
		ci += c_step
		if owner_grid[c_idx] != nid:
			continue
		if required_lm > 0 and landmass_grid[c_idx] != required_lm:
			continue
		var cx: int = c_idx % sim_width
		var cy: int = int(c_idx / sim_width)
		var d2: float = float((cx - landing_spot.x) * (cx - landing_spot.x) + (cy - landing_spot.y) * (cy - landing_spot.y))
		var sc := Vector2i(cx, cy)
		if cy > 0 and terrain_grid[c_idx - sim_width] == T_OCEAN and d2 < dir_best_d2[0]:
			dir_best_d2[0] = d2
			dir_best_cell[0] = sc
		if cy + 1 < sim_height and terrain_grid[c_idx + sim_width] == T_OCEAN and d2 < dir_best_d2[1]:
			dir_best_d2[1] = d2
			dir_best_cell[1] = sc
		if cx + 1 < sim_width and terrain_grid[c_idx + 1] == T_OCEAN and d2 < dir_best_d2[2]:
			dir_best_d2[2] = d2
			dir_best_cell[2] = sc
		if cx > 0 and terrain_grid[c_idx - 1] == T_OCEAN and d2 < dir_best_d2[3]:
			dir_best_d2[3] = d2
			dir_best_cell[3] = sc

		var merged := false
		for ns_i in range(near_shores.size()):
			var prev_c: Vector2i = near_shores[ns_i]["cell"]
			if Vector2(prev_c - sc).length_squared() < 784.0:
				merged = true
				if d2 < float(near_shores[ns_i]["d2"]):
					near_shores[ns_i] = {"cell": sc, "d2": d2}
				break
		if not merged:
			if near_shores.size() < 6:
				near_shores.append({"cell": sc, "d2": d2})
			else:
				var worst_i := 0
				var worst_d2 := -1.0
				for ns_i in range(near_shores.size()):
					if float(near_shores[ns_i]["d2"]) > worst_d2:
						worst_d2 = float(near_shores[ns_i]["d2"])
						worst_i = ns_i
				if d2 < worst_d2:
					near_shores[worst_i] = {"cell": sc, "d2": d2}

	var cand_raw: Array[Dictionary] = []
	for di in range(4):
		if dir_best_cell[di].x >= 0:
			cand_raw.append({"cell": dir_best_cell[di], "from_port": false})
	for ns: Dictionary in near_shores:
		cand_raw.append({"cell": ns["cell"], "from_port": false})

	var nation: NationData = nations.get(nid, null)
	if nation != null:
		var port_cands: Array[Dictionary] = []
		for sid: int in nation.structure_ids:
			var pst: StructureData = structures.get(sid, null)
			if pst != null and pst.type == StructureData.TYPE_PORT and pst.level > 0 and pst.water_cell.x >= 0:
				if required_lm > 0 and landmass_grid[pst.cell.y * sim_width + pst.cell.x] != required_lm:
					continue
				var pd2: float = Vector2(pst.cell - landing_spot).length_squared()
				port_cands.append({"cell": pst.cell, "d2": pd2})
		port_cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d2"]) < float(b["d2"]))
		for pi in range(mini(4, port_cands.size())):
			cand_raw.append({"cell": port_cands[pi]["cell"], "from_port": true})

	var candidates_by_nav: Dictionary = {}
	var world_scale: float = sea_pathfinder._world_scale
	for item: Dictionary in cand_raw:
		var shore: Vector2i = item["cell"]
		var start_nav: Vector2i = sea_pathfinder.find_nearest_nav_cell(shore, 2)
		if start_nav.x < 0:
			continue
		var nav_key: int = start_nav.y * sea_pathfinder.nav_width + start_nav.x
		var near_port: bool = bool(item["from_port"]) or _has_nearby_port(nid, shore, 24.0)
		var ship_speed: float = SHIP_SPEED_PX_SEC * (1.25 if near_port else 1.0)
		var min_eta: float = (Vector2(start_nav - dest_nav).length() * world_scale) / ship_speed
		var entry := {
			"shore_cell": shore,
			"start_nav": start_nav,
			"near_port": near_port,
			"ship_speed": ship_speed,
			"min_eta": min_eta,
		}
		if not candidates_by_nav.has(nav_key):
			candidates_by_nav[nav_key] = entry
		else:
			var old: Dictionary = candidates_by_nav[nav_key]
			if (not bool(old["near_port"]) and near_port) or (bool(old["near_port"]) == near_port and min_eta < float(old["min_eta"])):
				candidates_by_nav[nav_key] = entry

	if candidates_by_nav.is_empty():
		return {"ok": false, "reason": "No coastal departure shore on source landmass."}

	var candidates: Array[Dictionary] = []
	for k in candidates_by_nav.keys():
		candidates.append(candidates_by_nav[k])
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["min_eta"]) < float(b["min_eta"])
	)
	if candidates.size() > 10:
		candidates.resize(10)

	var best_time := 1e12
	var best_res: Dictionary = {}
	for cand: Dictionary in candidates:
		if best_time < 1e11 and float(cand["min_eta"]) >= best_time:
			break
		var start_nav: Vector2i = cand["start_nav"]
		var route: PackedVector2Array = sea_pathfinder.find_path(start_nav, dest_nav)
		if route.is_empty():
			continue
		var eta: float = _compute_route_length(route) / float(cand["ship_speed"])
		if eta < best_time:
			best_time = eta
			best_res = {
				"ok": true,
				"shore_cell": cand["shore_cell"],
				"start_nav": start_nav,
				"landing_cell": landing_spot,
				"dest_nav": dest_nav,
				"route": route,
				"near_port": cand["near_port"],
				"travel_time": eta,
			}

	if not best_res.is_empty():
		return best_res
	return {"ok": false, "reason": "No navigable sea route from your coasts."}


func _has_nearby_port(nid: int, cell: Vector2i, max_dist: float) -> bool:
	var n: NationData = nations.get(nid, null)
	if n == null:
		return false
	for sid: int in n.structure_ids:
		var st: StructureData = structures.get(sid, null)
		if st != null and st.type == StructureData.TYPE_PORT and st.level > 0:
			if st.cell.distance_to(cell) <= max_dist:
				return true
	return false


func _cmd_expand_to(cmd: Dictionary) -> Dictionary:
	if match_phase != PHASE_PLAYING:
		return _reject("Match is not active.")
	var nid: int = int(cmd.get("nation_id", 0))
	var nation: NationData = nations.get(nid, null)
	if nation == null or not nation.alive:
		return _reject("Invalid or defeated nation.")

	var sx: int = clampi(int(cmd.get("x", 0)), 0, sim_width - 1)
	var sy: int = clampi(int(cmd.get("y", 0)), 0, sim_height - 1)
	var target_idx: int = sy * sim_width + sx
	if terrain_grid[target_idx] < T_PLAINS:
		return _reject("Select a land destination to expand into.")

	var ratio: float = clampf(float(cmd.get("commit_ratio", 0.35)), 0.15, 0.80)
	var commit_troops: float = floor(nation.troops * ratio)
	if commit_troops < 15.0:
		return _reject("Need at least 15 troops available to launch expansion.")

	var target_cell := Vector2i(sx, sy)
	var target_lm: int = landmass_grid[target_idx]
	var nation_lms: Dictionary = _nation_landmasses.get(nid, {})
	var on_same_lm: bool = nation_lms.has(target_lm)
	var clicked_owner: int = owner_grid[target_idx]
	var desired_target_owner: int = 0 if clicked_owner == nid else clicked_owner
	if clicked_owner == nid:
		var homeland_threat: ExpansionOrder = _find_incoming_invasion_for(nid, 0, target_cell)
		if homeland_threat == null:
			return {"ok": false, "ignored_own_land": true, "reason": "You already control this entire island/landmass — click outside your territory to explore or attack."}
		desired_target_owner = homeland_threat.nation_id
	if desired_target_owner > 0 and are_allied(nid, desired_target_owner):
		var ally_n: NationData = nations.get(desired_target_owner, null)
		var ally_name: String = ally_n.name if ally_n != null else "that nation"
		return _reject("Cannot attack allied nation (%s) — break alliance first." % ally_name)

	if desired_target_owner > 0:
		var has_active_front: ExpansionOrder = null if clicked_owner == nid else _find_reinforceable_expansion(nid, target_cell, target_lm, desired_target_owner)
		var inv: ExpansionOrder = _find_incoming_invasion_for(nid, desired_target_owner, target_cell) if has_active_front == null else null
		if inv != null:
			var inv_cell: Vector2i = world_to_sim(inv.front_world_pos) if inv.front_world_pos != Vector2.ZERO else inv.target_cell
			var inv_lm: int = landmass_grid[inv_cell.y * sim_width + inv_cell.x]
			if inv_lm == target_lm or on_same_lm:
				nation.troops -= commit_troops
				var def_bonus: float = sqrt(get_defense_multiplier_at(nid, inv.target_cell))
				var effective_power: float = commit_troops * def_bonus
				if effective_power >= inv.remaining_troops:
					var crushed: float = inv.remaining_troops
					var surplus: float = maxf(0.0, commit_troops - crushed / maxf(def_bonus, 1.0))
					expansions.erase(inv.id)
					attack_countered.emit(nid, desired_target_owner, crushed, true)
					if surplus >= 12.0:
						var inv_n: NationData = nations.get(desired_target_owner, null)
						var push_target: Vector2i = target_cell if clicked_owner == desired_target_owner else (inv_n.capital_cell if inv_n != null and inv_n.capital_cell.x >= 0 else inv_cell)
						var counter_ord := _start_land_expansion(nid, push_target, surplus, desired_target_owner)
						if counter_ord == null:
							nation.troops = minf(nation.max_troops, nation.troops + surplus)
					elif surplus > 0.0:
						nation.troops = minf(nation.max_troops, nation.troops + surplus)
					expansion_updated.emit()
					return {"ok": true, "mode": "counter_repel", "enemy_destroyed": crushed, "surplus": surplus}
				else:
					inv.remaining_troops -= effective_power
					inv.last_troop_delta = -effective_power
					inv.troop_flash_timer = 0.65
					attack_countered.emit(nid, desired_target_owner, effective_power, false)
					expansion_updated.emit()
					return {"ok": true, "mode": "counter_clash", "enemy_destroyed": effective_power, "invader_remaining": inv.remaining_troops}

	var use_sea: bool = should_use_sea_crossing(nid, target_cell)

	if not use_sea:
		var existing := _find_reinforceable_expansion(nid, target_cell, target_lm, desired_target_owner)
		if existing != null:
			nation.troops -= commit_troops
			existing.remaining_troops += commit_troops
			existing.initial_troops += commit_troops
			existing.last_troop_delta = commit_troops
			existing.troop_flash_timer = 0.65
			existing.target_cell = target_cell
			if is_fallout_at(target_cell.x, target_cell.y):
				existing.allow_fallout = true
			if existing.frontier_size() < 24 or existing.allow_fallout:
				_seed_expansion_arc(existing, nid, target_cell, target_lm, 24)
			expansion_updated.emit()
			return {"ok": true, "mode": "land_reinforce", "expansion_id": existing.id, "added_troops": commit_troops}

	if count_active_expansions(nid) >= MAX_ACTIVE_EXPANSIONS_PER_NATION:
		return _reject("Max %d concurrent expansion fronts active." % MAX_ACTIVE_EXPANSIONS_PER_NATION)

	if use_sea:
		var shore_res: Dictionary = find_closest_owned_shore(nid, target_cell)
		if bool(shore_res.get("ok", false)):
			return _launch_landing_ship(nid, target_cell, shore_res, commit_troops, desired_target_owner)
		if on_same_lm:
			var fallback_land := _start_land_expansion(nid, target_cell, commit_troops, desired_target_owner)
			if fallback_land != null:
				nation.troops -= commit_troops
				expansion_updated.emit()
				return {"ok": true, "mode": "land", "expansion_id": fallback_land.id}
		return _reject(str(shore_res.get("reason", "No coastal route to destination island.")))

	var order := _start_land_expansion(nid, target_cell, commit_troops, desired_target_owner)
	if order != null:
		nation.troops -= commit_troops
		expansion_updated.emit()
		return {"ok": true, "mode": "land", "expansion_id": order.id}

	if desired_target_owner > 0:
		var fallback_attack_shore: Dictionary = find_closest_owned_shore(nid, target_cell)
		if bool(fallback_attack_shore.get("ok", false)):
			return _launch_landing_ship(nid, target_cell, fallback_attack_shore, commit_troops, desired_target_owner)
		var target_n: NationData = nations.get(desired_target_owner, null)
		var t_name: String = target_n.name if target_n != null else "that nation"
		return _reject("No shared border with %s — expand to their border or attack by sea." % t_name)

	if clicked_owner == nid:
		if _has_foreign_border_on_landmass(nid, target_lm):
			return _reject("Click a foreign nation's territory directly to attack them, or click across the sea.")
		return _reject("You already control this entire island/landmass — click across the sea to launch a boat.")

	var fallback_shore: Dictionary = find_closest_owned_shore(nid, target_cell)
	if bool(fallback_shore.get("ok", false)):
		return _launch_landing_ship(nid, target_cell, fallback_shore, commit_troops, desired_target_owner)
	return _reject(str(fallback_shore.get("reason", "No reachable land or sea route toward destination.")))


func should_use_sea_crossing(nid: int, target_cell: Vector2i) -> bool:
	"""Returns true when expanding to target_cell should launch a boat across water."""
	if target_cell.x < 0 or target_cell.y < 0 or target_cell.x >= sim_width or target_cell.y >= sim_height:
		return false
	var t_idx: int = target_cell.y * sim_width + target_cell.x
	if terrain_grid[t_idx] < T_PLAINS:
		return false

	var target_lm: int = landmass_grid[t_idx]
	var nation_lms: Dictionary = _nation_landmasses.get(nid, {})
	if not nation_lms.has(target_lm):
		return true
	if owner_grid[t_idx] == nid:
		return false

	var borders: Dictionary = _nation_borders.get(nid, {})
	var b_keys: Array = borders.keys()
	var b_stride: int = maxi(1, int(b_keys.size() / 1200))
	var best_bx := -1
	var best_by := -1
	var best_d2 := 1e12
	var bi := 0
	while bi < b_keys.size():
		var b_idx: int = int(b_keys[bi])
		bi += b_stride
		if owner_grid[b_idx] != nid or landmass_grid[b_idx] != target_lm:
			continue
		var bx: int = b_idx % sim_width
		var by: int = int(b_idx / sim_width)
		var d2: float = float((bx - target_cell.x) * (bx - target_cell.x) + (by - target_cell.y) * (by - target_cell.y))
		if d2 < best_d2:
			best_d2 = d2
			best_bx = bx
			best_by = by

	if best_bx < 0:
		return false

	var dx: int = target_cell.x - best_bx
	var dy: int = target_cell.y - best_by
	var steps: int = maxi(abs(dx), abs(dy))
	var ocean_hits := 0
	for s in range(1, steps):
		var t: float = float(s) / float(steps)
		var sx: int = clampi(int(round(float(best_bx) + float(dx) * t)), 0, sim_width - 1)
		var sy: int = clampi(int(round(float(best_by) + float(dy) * t)), 0, sim_height - 1)
		if terrain_grid[sy * sim_width + sx] == T_OCEAN:
			ocean_hits += 1

	if ocean_hits == 0:
		return false
	var best_d: float = sqrt(best_d2)
	if best_d >= 24.0 and ocean_hits >= 10:
		return true

	# Bounded local overland BFS to verify whether a narrow water gap lacks a nearby land detour
	var max_depth: int = mini(40, int(ceil(best_d * 2.2)) + 8)
	var max_popped: int = 960
	var queue_idx := PackedInt32Array([t_idx])
	var queue_depth := PackedInt32Array([0])
	var visited: Dictionary = {t_idx: true}
	var head := 0
	while head < queue_idx.size() and head < max_popped:
		var c_idx: int = queue_idx[head]
		var depth: int = queue_depth[head]
		head += 1
		if owner_grid[c_idx] == nid:
			return false
		if depth >= max_depth:
			continue
		var cx: int = c_idx % sim_width
		var cy: int = int(c_idx / sim_width)
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + dir.x
			var ny: int = cy + dir.y
			if nx < 0 or nx >= sim_width or ny < 0 or ny >= sim_height:
				continue
			var n_idx: int = ny * sim_width + nx
			if visited.has(n_idx) or terrain_grid[n_idx] < T_PLAINS:
				continue
			visited[n_idx] = true
			queue_idx.append(n_idx)
			queue_depth.append(depth + 1)
	return true


func _launch_landing_ship(nid: int, target_cell: Vector2i, shore_res: Dictionary, commit_troops: float, target_owner_id: int = 0) -> Dictionary:
	var nation: NationData = nations[nid]
	var route: PackedVector2Array = shore_res["route"]
	var landing_spot: Vector2i = shore_res["landing_cell"]
	var near_port: bool = bool(shore_res.get("near_port", false))

	nation.troops -= commit_troops
	var ship := ShipUnit.new()
	ship.id = _next_ship_id
	_next_ship_id += 1
	ship.kind = ShipUnit.KIND_LANDING
	ship.nation_id = nid
	ship.waypoints = route
	ship.position = route[0]
	ship.waypoint_index = 1 if route.size() > 1 else 0
	ship.speed_px_per_sec = SHIP_SPEED_PX_SEC * (1.25 if near_port else 1.0)
	ship.troops_carried = commit_troops
	ship.landing_cell = landing_spot
	ship.target_cell = target_cell
	ship.target_owner_id = target_owner_id
	ship.hp = 45.0
	ship.max_hp = 45.0
	ships[ship.id] = ship
	ship_launched.emit(ship.id)
	expansion_updated.emit()
	return {"ok": true, "mode": "naval_landing", "ship_id": ship.id, "shore": shore_res["shore_cell"]}


func _find_incoming_invasion_for(defender_id: int, attacker_id: int, near_cell: Vector2i) -> ExpansionOrder:
	var best: ExpansionOrder = null
	var best_d2 := 1e12
	var near_w: Vector2 = sim_to_world(near_cell)
	var max_w_d2: float = 120.0 * 120.0
	var active_invaders := 0
	for eid: int in expansions.keys():
		var o: ExpansionOrder = expansions[eid]
		if not o.active or o.enemy_nation_id != defender_id or o.remaining_troops <= 0.5:
			continue
		if attacker_id > 0 and o.nation_id != attacker_id:
			continue
		active_invaders += 1
		var front_pos: Vector2 = o.front_world_pos if o.front_world_pos != Vector2.ZERO else sim_to_world(o.target_cell)
		var d2: float = front_pos.distance_squared_to(near_w)
		if d2 < best_d2:
			best_d2 = d2
			best = o
	if best == null:
		return null
	if attacker_id == 0 and active_invaders > 1 and best_d2 > max_w_d2:
		return best
	return best


func _find_reinforceable_expansion(nid: int, target_cell: Vector2i, target_lm: int, desired_target_owner: int) -> ExpansionOrder:
	var target_w: Vector2 = sim_to_world(target_cell)
	for eid: int in expansions.keys():
		var o: ExpansionOrder = expansions[eid]
		if o.nation_id != nid or not o.active or o.target_owner_id != desired_target_owner:
			continue
		var o_idx: int = o.target_cell.y * sim_width + o.target_cell.x
		if landmass_grid[o_idx] != target_lm:
			continue
		if desired_target_owner > 0:
			return o
		if o.target_cell.distance_to(target_cell) <= 110.0 or (o.front_world_pos != Vector2.ZERO and o.front_world_pos.distance_to(target_w) <= 110.0):
			return o
	return null


func _has_foreign_border_on_landmass(nid: int, target_lm: int) -> bool:
	var borders: Dictionary = _nation_borders.get(nid, {})
	for idx_var in borders.keys():
		var b_idx: int = int(idx_var)
		if owner_grid[b_idx] != nid or landmass_grid[b_idx] != target_lm:
			continue
		var bx: int = b_idx % sim_width
		var by: int = int(b_idx / sim_width)
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = bx + dir.x
			var ny: int = by + dir.y
			if nx < 0 or nx >= sim_width or ny < 0 or ny >= sim_height:
				continue
			var n_idx: int = ny * sim_width + nx
			if terrain_grid[n_idx] >= T_PLAINS and owner_grid[n_idx] != 0 and owner_grid[n_idx] != nid:
				return true
	return false


func _seed_expansion_arc(order: ExpansionOrder, nid: int, target: Vector2i, target_lm: int, max_seeds: int = 72) -> void:
	var borders: Dictionary = _nation_borders.get(nid, {})
	if borders.is_empty():
		return
	var b_keys: Array = borders.keys()
	var b_stride: int = maxi(1, int(b_keys.size() / 1200))
	var ranked: Array = []
	var bi := 0
	while bi < b_keys.size():
		var b_idx: int = int(b_keys[bi])
		bi += b_stride
		if owner_grid[b_idx] != nid or landmass_grid[b_idx] != target_lm:
			continue
		var bx: int = b_idx % sim_width
		var by: int = int(b_idx / sim_width)
		var d2: float = float((bx - target.x) * (bx - target.x) + (by - target.y) * (by - target.y))
		ranked.append([d2, b_idx])
	if ranked.is_empty():
		return
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var min_dist: float = sqrt(float(ranked[0][0]))
	var seed_limit: int = mini(ranked.size(), max_seeds)
	for i in range(seed_limit):
		var b_idx: int = int(ranked[i][1])
		var bd: float = sqrt(float(ranked[i][0]))
		var base_depth: float = (bd - min_dist) * 0.25
		_push_adjacent_frontier(order, b_idx, nid, target, base_depth)
	if order.frontier_size() == 0:
		for item: Array in ranked:
			_push_adjacent_frontier(order, int(item[1]), nid, target, 0.0)
			if order.frontier_size() >= 36:
				break


func _start_land_expansion(nid: int, target: Vector2i, troops: float, forced_target_owner: int = -1) -> ExpansionOrder:
	var target_idx: int = target.y * sim_width + target.x
	var target_lm: int = landmass_grid[target_idx]
	var borders: Dictionary = _nation_borders.get(nid, {})
	if borders.is_empty():
		return null

	var b_keys: Array = borders.keys()
	var b_stride: int = maxi(1, int(b_keys.size() / 1200))
	var ranked: Array = []
	var bi := 0
	while bi < b_keys.size():
		var b_idx: int = int(b_keys[bi])
		bi += b_stride
		if owner_grid[b_idx] != nid or landmass_grid[b_idx] != target_lm:
			continue
		var bx: int = b_idx % sim_width
		var by: int = int(b_idx / sim_width)
		var d2: float = float((bx - target.x) * (bx - target.x) + (by - target.y) * (by - target.y))
		ranked.append([d2, b_idx])
	if ranked.is_empty():
		return null

	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var min_dist: float = sqrt(float(ranked[0][0]))

	var order := ExpansionOrder.new()
	order.id = _next_expansion_id
	_next_expansion_id += 1
	order.nation_id = nid
	order.target_cell = target
	order.origin_dist_to_target = min_dist
	order.initial_troops = troops
	order.remaining_troops = troops
	order.target_terrain = terrain_grid[target_idx]
	var target_owner: int = forced_target_owner if forced_target_owner >= 0 else owner_grid[target_idx]
	if target_owner == nid:
		target_owner = 0
	order.target_owner_id = target_owner
	order.is_contested = (target_owner != 0)
	order.enemy_nation_id = target_owner
	var nation_ref: NationData = nations.get(nid, null)
	var cap_fallout: bool = nation_ref != null and nation_ref.capital_cell.x >= 0 and is_fallout_at(nation_ref.capital_cell.x, nation_ref.capital_cell.y)
	order.allow_fallout = is_fallout_at(target.x, target.y) or cap_fallout

	var supply := _evaluate_supply(nid, target)
	order.supply_quality = supply["quality"]
	order.supply_factor = supply["factor"]

	# OpenFront 1:1 frontier seeding across the entire active border (up to 900 cells at 2048x1024)
	var seed_limit: int = mini(ranked.size(), 900)
	for i in range(seed_limit):
		var b_idx: int = int(ranked[i][1])
		var bd: float = sqrt(float(ranked[i][0]))
		var base_depth: float = (bd - min_dist) * (0.06 if order.is_contested else 0.14)
		_push_adjacent_frontier(order, b_idx, nid, target, base_depth)

	if order.frontier_size() == 0:
		for item: Array in ranked:
			_push_adjacent_frontier(order, int(item[1]), nid, target, 0.0)
			if order.frontier_size() >= 128:
				break
	if order.frontier_size() == 0:
		return null

	var first_idx: int = order.peek_best()
	if first_idx >= 0:
		order.front_world_pos = Vector2(float(first_idx % sim_width) + 0.5, float(int(first_idx / sim_width)) + 0.5) * sim_scale
	expansions[order.id] = order
	return order


func _push_adjacent_frontier(
	order: ExpansionOrder,
	center_idx: int,
	nid: int,
	target: Vector2i,
	parent_depth: float,
) -> void:
	var cx: int = center_idx % sim_width
	var cy: int = int(center_idx / sim_width)
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if dx != 0 and dy != 0:
				continue
			var nx: int = cx + dx
			var ny: int = cy + dy
			if nx < 0 or ny < 0 or nx >= sim_width or ny >= sim_height:
				continue
			var n_idx: int = ny * sim_width + nx
			var t: int = terrain_grid[n_idx]
			if t < T_PLAINS or not _can_order_claim_owner(order.target_owner_id, owner_grid[n_idx], nid):
				continue
			if fallout_grid[n_idx] > 0 and not order.allow_fallout:
				continue

			# OpenFront 1:1 priority queue: terrain cost + friendly neighbor cohesion + jitter
			var friendly_adj := 0
			if nx > 0 and owner_grid[n_idx - 1] == nid:
				friendly_adj += 1
			if nx < sim_width - 1 and owner_grid[n_idx + 1] == nid:
				friendly_adj += 1
			if ny > 0 and owner_grid[n_idx - sim_width] == nid:
				friendly_adj += 1
			if ny < sim_height - 1 and owner_grid[n_idx + sim_width] == nid:
				friendly_adj += 1

			var t_step: float = 0.85 + (float(TERRAIN_COST.get(t, 1.0)) - 1.0) * 0.72
			var noise: float = float(((n_idx * 73856093) ^ (order.id * 19349663)) & 255) / 255.0 * 0.28
			var new_depth: float = parent_depth + t_step + noise
			var dist: float = Vector2(float(nx - target.x), float(ny - target.y)).length()
			var dir_weight: float = 0.08 if order.is_contested else 0.16
			var dir_pull: float = dir_weight * (dist - order.origin_dist_to_target)
			var cohesion: float = -float(friendly_adj) * 0.85
			var enemy_pen: float = 1.6 if owner_grid[n_idx] != 0 else 0.0
			var fallout_pen: float = 0.35 if fallout_grid[n_idx] > 0 else 0.0
			var score: float = new_depth + dir_pull + cohesion + enemy_pen + fallout_pen
			order.push_frontier(n_idx, score, new_depth)


func _evaluate_supply(nid: int, target: Vector2i) -> Dictionary:
	var nation: NationData = nations.get(nid, null)
	if nation == null:
		return {"quality": "Normal", "factor": 1.0}
	var best_ratio: float = Vector2(nation.capital_cell - target).length() / 75.0
	for sid: int in nation.structure_ids:
		var st: StructureData = structures.get(sid, null)
		if st != null and st.level > 0:
			var rad: float = st.get_supply_radius()
			if rad > 0.0:
				best_ratio = minf(best_ratio, Vector2(st.cell - target).length() / rad)
	if best_ratio <= 1.0:
		return {"quality": "Strong", "factor": 1.2}
	if best_ratio <= 2.1:
		return {"quality": "Normal", "factor": 1.0}
	return {"quality": "Stretched", "factor": 0.72}


func _find_coastal_landing_on_landmass(target: Vector2i, target_lm: int, preferred_owner: int = -1) -> Vector2i:
	# Fast local 22-cell box scan around target first (< 0.03 ms for island & coastal clicks)
	var loc_pref := Vector2i(-1, -1)
	var loc_pref_d2 := 1e12
	var loc_any := Vector2i(-1, -1)
	var loc_any_d2 := 1e12
	var y0: int = maxi(0, target.y - 22)
	var y1: int = mini(sim_height - 1, target.y + 22)
	var x0: int = maxi(0, target.x - 22)
	var x1: int = mini(sim_width - 1, target.x + 22)
	for yy in range(y0, y1 + 1):
		var row_off: int = yy * sim_width
		var dy: int = yy - target.y
		for xx in range(x0, x1 + 1):
			var idx: int = row_off + xx
			if landmass_grid[idx] != target_lm or coastal_grid[idx] != 1:
				continue
			var dx: int = xx - target.x
			var d2: float = float(dx * dx + dy * dy)
			if preferred_owner >= 0 and owner_grid[idx] == preferred_owner:
				if d2 < loc_pref_d2 and sea_pathfinder.find_nearest_nav_cell(Vector2i(xx, yy), 2).x >= 0:
					loc_pref_d2 = d2
					loc_pref = Vector2i(xx, yy)
			if d2 < loc_any_d2 and sea_pathfinder.find_nearest_nav_cell(Vector2i(xx, yy), 2).x >= 0:
				loc_any_d2 = d2
				loc_any = Vector2i(xx, yy)
	if loc_pref.x >= 0:
		return loc_pref
	if loc_any.x >= 0:
		return loc_any

	if not _landmass_coasts.has(target_lm):
		var coast_arr := PackedInt32Array()
		for idx in range(sim_width * sim_height):
			if landmass_grid[idx] == target_lm and coastal_grid[idx] == 1:
				var cx: int = idx % sim_width
				var cy: int = int(idx / sim_width)
				if sea_pathfinder.find_nearest_nav_cell(Vector2i(cx, cy), 2).x >= 0:
					coast_arr.append(idx)
		_landmass_coasts[target_lm] = coast_arr

	var lm_coasts: PackedInt32Array = _landmass_coasts[target_lm]
	var best_pref := Vector2i(-1, -1)
	var best_pref_d2 := 1e12
	var best_any := Vector2i(-1, -1)
	var best_any_d2 := 1e12
	var stride: int = maxi(1, int(lm_coasts.size() / 400))
	var i := 0
	while i < lm_coasts.size():
		var idx: int = lm_coasts[i]
		i += stride
		var xx: int = idx % sim_width
		var yy: int = int(idx / sim_width)
		var dx: int = xx - target.x
		var dy: int = yy - target.y
		var d2: float = float(dx * dx + dy * dy)
		if preferred_owner >= 0 and owner_grid[idx] == preferred_owner:
			if d2 < best_pref_d2 and sea_pathfinder.find_nearest_nav_cell(Vector2i(xx, yy), 2).x >= 0:
				best_pref_d2 = d2
				best_pref = Vector2i(xx, yy)
		if d2 < best_any_d2 and sea_pathfinder.find_nearest_nav_cell(Vector2i(xx, yy), 2).x >= 0:
			best_any_d2 = d2
			best_any = Vector2i(xx, yy)
	return best_pref if best_pref.x >= 0 else best_any


func _cmd_cancel_expansion(cmd: Dictionary) -> Dictionary:
	var nid: int = int(cmd.get("nation_id", 0))
	var eid: int = int(cmd.get("expansion_id", 0))
	var order: ExpansionOrder = expansions.get(eid, null)
	if order == null or order.nation_id != nid:
		return _reject("Expansion order not found.")
	var nation: NationData = nations.get(nid, null)
	# OpenFront 1:1 retreat: 25% troop malus when retreating from a contested player attack
	var return_ratio: float = 0.75 if order.is_contested else 1.0
	var returned: float = floor(order.remaining_troops * return_ratio)
	if nation != null and nation.alive:
		nation.troops = minf(nation.max_troops, nation.troops + returned)
	expansions.erase(eid)
	expansion_updated.emit()
	return {"ok": true, "returned_troops": returned}


func _cmd_cancel_ship(cmd: Dictionary) -> Dictionary:
	var nid: int = int(cmd.get("nation_id", 0))
	var sid: int = int(cmd.get("ship_id", 0))
	var ship: ShipUnit = ships.get(sid, null)
	if ship == null or ship.nation_id != nid or ship.kind != ShipUnit.KIND_LANDING:
		return _reject("Landing expedition vessel not found.")
	var nation: NationData = nations.get(nid, null)
	var refund: float = round(ship.troops_carried * 0.85)
	if nation != null and nation.alive:
		nation.troops = minf(nation.max_troops, nation.troops + refund)
	ships.erase(sid)
	expansion_updated.emit()
	return {"ok": true, "refunded_troops": refund}


func count_structures_of_type(nid: int, s_type: String) -> int:
	var nation: NationData = nations.get(nid, null)
	if nation == null:
		return 0
	var count := 0
	for sid: int in nation.structure_ids:
		var st: StructureData = structures.get(sid, null)
		if st != null and st.type == s_type:
			count += 1
	return count


func get_structure_build_cost(nid: int, s_type: String) -> float:
	return StructureData.get_scaled_build_cost(s_type, count_structures_of_type(nid, s_type))


func count_warships(nid: int) -> int:
	var count := 0
	for sid: int in ships.keys():
		var sh: ShipUnit = ships[sid]
		if sh.active and sh.nation_id == nid and sh.kind == ShipUnit.KIND_WARSHIP:
			count += 1
	return count


func get_warship_build_cost(nid: int) -> float:
	return ShipUnit.get_warship_cost(count_warships(nid))


func can_place_structure(nid: int, s_type: String, sx: int, sy: int) -> Dictionary:
	if not (s_type in [
		StructureData.TYPE_TOWN,
		StructureData.TYPE_PORT,
		StructureData.TYPE_FACTORY,
		StructureData.TYPE_DEFENSE_POST,
		StructureData.TYPE_MISSILE_SILO,
		StructureData.TYPE_SAM_LAUNCHER,
	]):
		return {"ok": false, "reason": "Unknown structure type."}
	if no_nukes and (s_type == StructureData.TYPE_MISSILE_SILO or s_type == StructureData.TYPE_SAM_LAUNCHER):
		return {"ok": false, "reason": "Silos and SAMs are disabled (Conventional Mode)."}
	var nation: NationData = nations.get(nid, null)
	if nation == null or not nation.alive:
		return {"ok": false, "reason": "Invalid nation."}
	if sx < 0 or sy < 0 or sx >= sim_width or sy >= sim_height:
		return {"ok": false, "reason": "Out of world map bounds."}
	var idx: int = sy * sim_width + sx
	if terrain_grid[idx] < T_PLAINS:
		return {"ok": false, "reason": "Must build on land."}
	if owner_grid[idx] != nid:
		return {"ok": false, "reason": "You must control this territory before building."}
	var cost: float = get_structure_build_cost(nid, s_type)
	if nation.gold < cost:
		return {"ok": false, "reason": "Need %s Pesos to build %s." % [StructureData.format_pesos(cost), s_type.replace("_", " ").capitalize()]}

	var cell := Vector2i(sx, sy)
	for sid: int in structures.keys():
		var existing: StructureData = structures[sid]
		if existing.cell.distance_to(cell) < float(MIN_STRUCTURE_SPACING_CELLS):
			return {"ok": false, "reason": "Too close to another structure."}

	if s_type == StructureData.TYPE_PORT:
		if coastal_grid[idx] != 1 and not _has_nearby_ocean(sx, sy, 4):
			return {"ok": false, "reason": "Ports must be built on an ocean coastline."}
		if sea_pathfinder.find_nearest_nav_cell(cell, 4).x < 0:
			return {"ok": false, "reason": "No navigable sea access nearby for ships."}

	return {"ok": true, "reason": ""}


func _has_nearby_ocean(sx: int, sy: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		var yy: int = sy + dy
		if yy < 0 or yy >= sim_height:
			continue
		for dx in range(-r, r + 1):
			var xx: int = sx + dx
			if xx >= 0 and xx < sim_width and terrain_grid[yy * sim_width + xx] == T_OCEAN:
				return true
	return false


func _cmd_build_structure(cmd: Dictionary) -> Dictionary:
	if match_phase != PHASE_PLAYING:
		return _reject("Match is not active.")
	var nid: int = int(cmd.get("nation_id", 0))
	var s_type: String = str(cmd.get("structure_type", ""))
	var sx: int = int(cmd.get("x", -1))
	var sy: int = int(cmd.get("y", -1))

	var check: Dictionary = can_place_structure(nid, s_type, sx, sy)
	if not bool(check.get("ok", false)):
		return _reject(str(check.get("reason", "Cannot build here.")))

	var nation: NationData = nations[nid]
	nation.gold -= get_structure_build_cost(nid, s_type)

	var st := StructureData.new()
	st.id = _next_structure_id
	_next_structure_id += 1
	st.nation_id = nid
	st.type = s_type
	st.cell = Vector2i(sx, sy)
	st.level = 0
	st.target_level = 1
	st.is_constructing = true
	st.progress_ticks = 0
	st.total_build_ticks = StructureData.get_build_ticks(1)
	if s_type == StructureData.TYPE_PORT:
		st.water_cell = sea_pathfinder.find_nearest_nav_cell(st.cell, 3)
	elif s_type == StructureData.TYPE_FACTORY:
		st.terrain_bonus = _factory_terrain_bonus(terrain_grid[sy * sim_width + sx])

	structures[st.id] = st
	nation.structure_ids.append(st.id)
	_recompute_all_economy_rates()
	structure_changed.emit(st.id)
	return {"ok": true, "structure_id": st.id}


func _cmd_upgrade_structure(cmd: Dictionary) -> Dictionary:
	"""Upgrades Town, Port, or Factory instantly (0 tick wait) up to Max Level 10."""
	if match_phase != PHASE_PLAYING:
		return _reject("Match is not active.")
	var nid: int = int(cmd.get("nation_id", 0))
	var sid: int = int(cmd.get("structure_id", 0))
	var st: StructureData = structures.get(sid, null)
	if st == null or st.nation_id != nid:
		return _reject("Structure not owned by your nation.")
	if st.is_constructing:
		return _reject("%s is still finishing initial construction." % st.get_display_name())
	var max_l: int = st.get_max_level()
	if st.level >= max_l:
		return _reject("%s is already at Max Level (%d)." % [st.get_display_name(), max_l])

	var cost: float = st.get_next_upgrade_cost()
	var nation: NationData = nations[nid]
	if nation.gold < cost:
		return _reject("Need %s Pesos to upgrade to Lv.%d." % [StructureData.format_pesos(cost), st.level + 1])

	nation.gold -= cost
	st.level += 1
	st.target_level = st.level
	st.is_constructing = false
	st.progress_ticks = 0
	_recompute_factory_links()
	_recompute_all_economy_rates()
	structure_upgraded.emit(st.id, st.level)
	structure_changed.emit(st.id)
	return {"ok": true, "level": st.level}


static func _factory_terrain_bonus(t: int) -> float:
	match t:
		T_MOUNTAINS:
			return 1.35
		T_HILLS:
			return 1.25
		T_FOREST, T_PLAINS:
			return 1.12
		_:
			return 1.0


func step_tick(tick: int) -> void:
	current_tick = tick
	if match_phase == PHASE_PLAYING:
		_step_structures()
		_step_economy_and_troops()
		_step_diplomacy()
		_step_port_trade_spawning()
		_step_trains()
		_step_ships()
		_step_sam_launchers()
		_step_missiles()
		_step_expansions()
		AIController.step_scheduled(self, tick)
		if _factory_links_dirty:
			_factory_links_dirty = false
			_economy_dirty = false
			_recompute_factory_links()
			_recompute_all_economy_rates()
		elif _economy_dirty and (tick % 6 == 0):
			_economy_dirty = false
			_recompute_all_economy_rates()
		for nid_t: int in nations.keys():
			var nt: NationData = nations[nid_t]
			if nt.alive and nt.territory_percent > nt.peak_territory_percent:
				nt.peak_territory_percent = nt.territory_percent
		if tick % 72 == 0 and match_history.size() < 180:
			var snap := {}
			for nid_s: int in nations.keys():
				var ns: NationData = nations[nid_s]
				if ns.alive or ns.territory_percent > 0.0:
					snap[nid_s] = ns.territory_percent
			match_history.append({"tick": tick, "nations": snap})
		_check_victory()
	simulation_ticked.emit(tick)


func _step_structures() -> void:
	var any_completed := false
	for sid: int in structures.keys():
		var st: StructureData = structures[sid]
		if st.is_constructing:
			st.progress_ticks += 1
			if st.progress_ticks >= st.total_build_ticks:
				st.level = mini(st.get_max_level(), st.target_level)
				st.is_constructing = false
				st.progress_ticks = 0
				if st.type == StructureData.TYPE_SAM_LAUNCHER:
					st.sam_ammo = StructureData.SAM_MAX_AMMO
					st.sam_reload_ticks = 0
				any_completed = true
				structure_changed.emit(sid)
		elif st.level > 0 and (st.type == StructureData.TYPE_TOWN or st.type == StructureData.TYPE_FACTORY):
			var owner_n: NationData = nations.get(st.nation_id, null)
			if owner_n != null and owner_n.alive:
				st.income_popup_accum += st.get_gold_per_sec() * TICK_DT
				if (current_tick + st.id * 19) % 96 == 0 and st.income_popup_accum >= 1.0:
					var amt: float = floor(st.income_popup_accum)
					st.income_popup_accum -= amt
					structure_income_popup.emit(st.nation_id, st.get_world_pos(), amt, st.type)
		if not st.is_constructing and st.type == StructureData.TYPE_SAM_LAUNCHER:
			if st.sam_reload_ticks > 0:
				st.sam_reload_ticks = maxi(0, st.sam_reload_ticks - 1)
			var half_cd: int = maxi(1, int(ceil(float(st.get_sam_cooldown_ticks()) * 0.5)))
			if st.sam_reload_ticks == 0:
				st.sam_ammo = StructureData.SAM_MAX_AMMO
			elif st.sam_reload_ticks <= half_cd:
				st.sam_ammo = 1
			else:
				st.sam_ammo = 0
		if st.trade_cooldown_ticks > 0:
			st.trade_cooldown_ticks -= 1
		if st.action_cooldown_ticks > 0:
			st.action_cooldown_ticks -= 1
		if st.train_cooldown_ticks > 0:
			st.train_cooldown_ticks -= 1
	if any_completed:
		_factory_links_dirty = true
		_economy_dirty = true


func _step_economy_and_troops() -> void:
	for nid: int in nations.keys():
		var n: NationData = nations[nid]
		if not n.alive:
			continue
		var betray_mult: float = 0.65 if n.is_betrayer(current_tick) else 1.0
		var earned: float = n.gold_per_sec * betray_mult * TICK_DT
		n.gold += earned
		n.total_gold_earned += earned

		# OpenFront 1:1 pow(fill, 0.73) * (1 - fill) curve peaking at ~42.2% pop cap
		var fill: float = clampf(n.troops / maxf(n.max_troops, 1.0), 0.0, 1.0)
		var peak_norm: float = pow(maxf(fill, 0.02), 0.73) * (1.0 - fill) / 0.307
		var curve: float = clampf(0.18 + 1.45 * peak_norm, 0.15, 1.65)
		n.effective_troops_per_sec = n.troops_per_sec * curve * betray_mult
		n.troops = minf(n.max_troops, n.troops + n.effective_troops_per_sec * TICK_DT)


func _count_active_trade_ships() -> int:
	var c := 0
	for sid: int in ships.keys():
		var sh: ShipUnit = ships[sid]
		if sh.active and sh.kind == ShipUnit.KIND_TRADE:
			c += 1
	return c


static func _compute_route_length(route: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(route.size() - 1):
		total += route[i].distance_to(route[i + 1])
	return total


func _step_port_trade_spawning() -> void:
	var global_trade := _count_active_trade_ships()
	if global_trade >= MAX_ACTIVE_TRADE_SHIPS:
		return

	var nation_ports_count: Dictionary = {}
	for sid: int in structures.keys():
		var s: StructureData = structures[sid]
		if s.type == StructureData.TYPE_PORT and s.level > 0:
			nation_ports_count[s.nation_id] = int(nation_ports_count.get(s.nation_id, 0)) + 1

	var spawned_this_tick := 0
	for sid: int in structures.keys():
		if global_trade >= MAX_ACTIVE_TRADE_SHIPS or spawned_this_tick >= 1:
			break
		var port: StructureData = structures[sid]
		if port.type != StructureData.TYPE_PORT or port.level <= 0:
			continue
		if port.water_cell.x < 0:
			continue
		if (current_tick + port.id * 7) % 24 != 0:
			continue
		for i in range(port.active_ship_ids.size() - 1, -1, -1):
			if not ships.has(port.active_ship_ids[i]):
				port.active_ship_ids.remove_at(i)

		var max_ships: int = StructureData.get_max_trade_ships(port.level)
		if port.active_ship_ids.size() >= max_ships:
			continue

		# OpenFront 1:1 port spawn roll: 10% * p^0.6 capped at 50% per second
		var p_owned: int = maxi(1, int(nation_ports_count.get(port.nation_id, 1)))
		var spawn_chance: float = minf(0.50, 0.10 * pow(float(p_owned), 0.6))
		if _rng.randf() > spawn_chance:
			continue

		var target_port: StructureData = _pick_trade_partner_port(port)
		if target_port == null:
			continue
		var lane_id: int = (_next_ship_id + port.id * 3 + target_port.id) % 5
		var route: PackedVector2Array = sea_pathfinder.find_trade_path(port.water_cell, target_port.water_cell, lane_id)
		if route.size() < 2:
			continue

		var dist_px: float = _compute_route_length(route)
		var is_foreign: bool = (target_port.nation_id != port.nation_id)
		var is_allied_tr: bool = is_foreign and are_allied(port.nation_id, target_port.nation_id)

		var ship := ShipUnit.new()
		ship.id = _next_ship_id
		_next_ship_id += 1
		ship.kind = ShipUnit.KIND_TRADE
		ship.nation_id = port.nation_id
		ship.source_port_id = port.id
		ship.dest_port_id = target_port.id
		ship.waypoints = route
		ship.position = route[0]
		ship.waypoint_index = 1
		ship.speed_px_per_sec = port.get_ship_speed()
		ship.is_foreign_trade = is_foreign
		ship.is_allied_trade = is_allied_tr
		ship.returning = false
		ship.captured = false
		var trade_gold: float = StructureData.get_distance_trade_payout(dist_px, port.level, port.factory_boost)
		if is_allied_tr:
			trade_gold = round(trade_gold * 1.40)
		ship.gold_value = trade_gold
		ships[ship.id] = ship
		port.active_ship_ids.append(ship.id)
		global_trade += 1
		spawned_this_tick += 1


func _pick_trade_partner_port(source_port: StructureData) -> StructureData:
	var cands: Array[StructureData] = []
	var weights: Array[float] = []
	var total_w := 0.0
	var src_pos: Vector2 = source_port.get_world_pos()
	for sid: int in structures.keys():
		if sid == source_port.id:
			continue
		var candidate: StructureData = structures[sid]
		if candidate.type != StructureData.TYPE_PORT or candidate.level <= 0 or candidate.water_cell.x < 0:
			continue
		if candidate.nation_id != source_port.nation_id and is_embargoed(source_port.nation_id, candidate.nation_id):
			continue
		var d: float = src_pos.distance_to(candidate.get_world_pos())
		if d < 12.0:
			continue
		var w: float = 1.0 / pow(maxf(d, 48.0), 0.35)
		if candidate.nation_id != source_port.nation_id:
			w *= 3.4 if are_allied(source_port.nation_id, candidate.nation_id) else 1.5
		cands.append(candidate)
		weights.append(w)
		total_w += w

	if cands.is_empty() or total_w <= 0.0:
		return null
	var pick: float = _rng.randf() * total_w
	var accum := 0.0
	for i in range(cands.size()):
		accum += weights[i]
		if pick <= accum:
			return cands[i]
	return cands[cands.size() - 1]


func _step_ships() -> void:
	var finished_ids: Array[int] = []
	var landing_events: Array = []

	for sid: int in ships.keys():
		var ship: ShipUnit = ships[sid]
		if not ship.active:
			finished_ids.append(sid)
			continue

		if ship.kind == ShipUnit.KIND_WARSHIP:
			if ship.fire_cooldown_ticks > 0:
				ship.fire_cooldown_ticks -= 1
			var owner_n: NationData = nations.get(ship.nation_id, null)
			if owner_n == null or not owner_n.alive:
				finished_ids.append(sid)
				continue
			_step_warship_ai(ship)
			if ship.waypoints.is_empty():
				continue
		elif ship.waypoints.is_empty():
			finished_ids.append(sid)
			continue

		var step_dist: float = ship.speed_px_per_sec * TICK_DT
		while step_dist > 0.0 and ship.waypoint_index < ship.waypoints.size():
			var target: Vector2 = ship.waypoints[ship.waypoint_index]
			var to_target: Vector2 = target - ship.position
			var dist: float = to_target.length()
			if dist <= step_dist:
				ship.position = target
				step_dist -= dist
				ship.waypoint_index += 1
			else:
				if ship.kind == ShipUnit.KIND_WARSHIP:
					ship.heading = lerp_angle(ship.heading, to_target.angle(), 0.36)
				else:
					ship.heading = to_target.angle()
				ship.position += (to_target / dist) * step_dist
				step_dist = 0.0

		if ship.waypoint_index >= ship.waypoints.size():
			if ship.kind == ShipUnit.KIND_TRADE:
				# OpenFront 1:1 one-way Port->Port settlement: BOTH trading partners receive full payout
				var dest_port: StructureData = structures.get(ship.dest_port_id, null)
				var src_port: StructureData = structures.get(ship.source_port_id, null)
				var src_n: NationData = nations.get(ship.nation_id, null)
				if dest_port != null and not is_embargoed(ship.nation_id, dest_port.nation_id):
					if ship.captured:
						if src_n != null and src_n.alive:
							src_n.gold += ship.gold_value
							trade_completed.emit(src_n.id, dest_port.get_world_pos(), ship.gold_value)
					elif dest_port.nation_id != ship.nation_id:
						var dest_n: NationData = nations.get(dest_port.nation_id, null)
						if src_n != null and src_n.alive:
							src_n.gold += ship.gold_value
							var src_pos: Vector2 = src_port.get_world_pos() if src_port != null else ship.position
							trade_completed.emit(src_n.id, src_pos, ship.gold_value)
						if dest_n != null and dest_n.alive:
							dest_n.gold += ship.gold_value
							trade_completed.emit(dest_n.id, dest_port.get_world_pos(), ship.gold_value)
					else:
						if src_n != null and src_n.alive:
							src_n.gold += ship.gold_value
							trade_completed.emit(src_n.id, dest_port.get_world_pos(), ship.gold_value)
				finished_ids.append(sid)
			elif ship.kind == ShipUnit.KIND_LANDING:
				landing_events.append(ship)
				finished_ids.append(sid)
			elif ship.kind == ShipUnit.KIND_WARSHIP:
				ship.manual_moving = false
				if ship.repair_retreating:
					var near_p: StructureData = find_structure_near(ship.position, 18.0)
					if near_p != null and near_p.type == StructureData.TYPE_PORT and near_p.nation_id == ship.nation_id and near_p.level > 0:
						ship.docked_port_id = near_p.id
						ship.waypoints = PackedVector2Array()
						continue
					ship.repair_retreating = false
				_assign_warship_patrol_wp(ship)

	_step_naval_shells()

	for fid: int in finished_ids:
		ships.erase(fid)

	var any_landed := false
	for l_ship: ShipUnit in landing_events:
		var n: NationData = nations.get(l_ship.nation_id, null)
		if n == null or not n.alive:
			continue
		var landing_lm: int = landmass_grid[l_ship.landing_cell.y * sim_width + l_ship.landing_cell.x]
		var hit_fallout: bool = is_fallout_at(l_ship.landing_cell.x, l_ship.landing_cell.y)
		var beach_claimed: int = _claim_organic_dot(n.id, l_ship.landing_cell, 12, l_ship.target_owner_id)
		if beach_claimed > 0 and player_nation_id != 0:
			if n.id == player_nation_id:
				player_land_conquered.emit(beach_claimed, l_ship.target_owner_id != 0)
			elif l_ship.target_owner_id == player_nation_id:
				last_player_threat_world_pos = sim_to_world(l_ship.landing_cell)
				player_territory_attacked.emit(n.id, beach_claimed)
		var rem: float = maxf(10.0, l_ship.troops_carried - (6.0 if hit_fallout else 3.0))
		var push_target: Vector2i = l_ship.target_cell if l_ship.target_cell.x >= 0 else l_ship.landing_cell
		var existing := _find_reinforceable_expansion(n.id, push_target, landing_lm, l_ship.target_owner_id)
		if existing != null:
			existing.remaining_troops += rem
			existing.initial_troops += rem
			existing.last_troop_delta = rem
			existing.troop_flash_timer = 0.65
			existing.target_cell = push_target
			_seed_expansion_arc(existing, n.id, push_target, landing_lm, 24)
		else:
			var ord := _start_land_expansion(n.id, push_target, rem, l_ship.target_owner_id)
			if ord == null:
				n.troops = minf(n.max_troops, n.troops + rem)
		any_landed = true
	if any_landed:
		_economy_dirty = true
		owner_dirty = true
		territory_changed.emit()
		expansion_updated.emit()


func _find_nearest_port_route_for_ship(from_pos: Vector2, nation_id: int) -> Dictionary:
	var n: NationData = nations.get(nation_id, null)
	if n == null:
		return {}
	var src_nav: Vector2i = sea_pathfinder.find_nearest_nav_cell(world_to_sim(from_pos), 4)
	if src_nav.x < 0:
		return {}
	var best_port: StructureData = null
	var best_d2 := 1e12
	for sid: int in n.structure_ids:
		var st: StructureData = structures.get(sid, null)
		if st == null or st.type != StructureData.TYPE_PORT or st.level <= 0 or st.water_cell.x < 0:
			continue
		var d2: float = from_pos.distance_squared_to(st.get_world_pos())
		if d2 < best_d2:
			best_d2 = d2
			best_port = st
	if best_port == null:
		return {}
	var route: PackedVector2Array = sea_pathfinder.find_path(src_nav, best_port.water_cell)
	if route.is_empty():
		return {}
	return {"port": best_port, "route": route}


func _step_warship_ai(ship: ShipUnit) -> void:
	# OpenFront 1:1 passive Port proximity healing & docked Port repair
	var owner_n: NationData = nations.get(ship.nation_id, null)
	if owner_n != null and ship.hp < ship.max_hp:
		for psid: int in owner_n.structure_ids:
			var pst: StructureData = structures.get(psid, null)
			if pst != null and pst.type == StructureData.TYPE_PORT and pst.level > 0:
				if ship.position.distance_squared_to(pst.get_world_pos()) <= 140.0 * 140.0:
					ship.hp = minf(ship.max_hp, ship.hp + 1.5 * TICK_DT)
					break

	if ship.docked_port_id > 0:
		var dock_p: StructureData = structures.get(ship.docked_port_id, null)
		if dock_p == null or dock_p.nation_id != ship.nation_id or dock_p.level <= 0:
			ship.docked_port_id = 0
			ship.repair_retreating = false
		else:
			ship.hp = minf(ship.max_hp, ship.hp + (14.0 + float(dock_p.level) * 5.0) * TICK_DT)
			if ship.hp >= ship.max_hp:
				ship.docked_port_id = 0
				ship.repair_retreating = false
				_assign_warship_patrol_wp(ship)
			else:
				ship.waypoints = PackedVector2Array()
				return

	var best_tgt: ShipUnit = null
	var best_score := 1e9
	var patrol_ctr: Vector2 = ship.patrol_center if ship.patrol_center != Vector2.ZERO else ship.position
	for tid: int in ships.keys():
		if tid == ship.id:
			continue
		var other: ShipUnit = ships[tid]
		if not other.active or other.nation_id == ship.nation_id or are_allied(ship.nation_id, other.nation_id):
			continue
		if other.kind == ShipUnit.KIND_WARSHIP and other.docked_port_id > 0:
			continue
		if (not ship.manual_moving) and other.position.distance_to(patrol_ctr) > ship.patrol_radius + 14.0:
			continue
		var d: float = ship.position.distance_to(other.position)
		if other.kind == ShipUnit.KIND_TRADE:
			if ship.repair_retreating:
				continue
			if d <= (26.0 if ship.manual_moving else ship.patrol_radius):
				var sc: float = d + 24.0
				if sc < best_score:
					best_score = sc
					best_tgt = other
		elif d <= 82.0:
			var prio: float = 0.0 if other.kind == ShipUnit.KIND_LANDING else 14.0
			var sc: float = d + prio
			if sc < best_score:
				best_score = sc
				best_tgt = other

	# OpenFront 1:1 auto-repair retreat at <= 75% HP when not in immediate combat
	if (
		not ship.manual_moving
		and not ship.repair_retreating
		and ship.docked_port_id == 0
		and current_tick - ship.last_manual_order_tick >= 48
		and ship.hp <= ship.max_hp * 0.75
		and (best_tgt == null or best_tgt.kind == ShipUnit.KIND_TRADE)
		and ((current_tick + ship.id) % 12 == 0)
	):
		var rep_route: Dictionary = _find_nearest_port_route_for_ship(ship.position, ship.nation_id)
		if not rep_route.is_empty():
			var r_pts: PackedVector2Array = rep_route["route"]
			var r_port: StructureData = rep_route["port"]
			if ship.position.distance_to(r_port.get_world_pos()) <= 12.0:
				ship.docked_port_id = r_port.id
				ship.repair_retreating = false
				ship.waypoints = PackedVector2Array()
				return
			ship.repair_retreating = true
			ship.target_ship_id = 0
			ship.waypoints = r_pts
			ship.waypoint_index = 1 if r_pts.size() > 1 and _is_water_segment_clear(ship.position, r_pts[1]) else 0
			return

	if best_tgt == null:
		ship.target_ship_id = 0
		return

	ship.target_ship_id = best_tgt.id
	var dist: float = ship.position.distance_to(best_tgt.position)
	if best_tgt.kind == ShipUnit.KIND_TRADE:
		if dist <= 22.0:
			var captor: NationData = nations.get(ship.nation_id, null)
			var redir: Dictionary = _find_nearest_port_route_for_ship(best_tgt.position, ship.nation_id)
			var raw_val: float = maxf(10000.0, best_tgt.gold_value)
			var instant_loot: float = maxf(2500.0, round(raw_val * 0.25))
			best_tgt.nation_id = ship.nation_id
			best_tgt.captured = true
			best_tgt.returning = false
			best_tgt.is_foreign_trade = false
			best_tgt.is_allied_trade = false
			if not redir.is_empty():
				best_tgt.gold_value = maxf(4000.0, round(raw_val * 0.40))
				if captor != null and captor.alive:
					captor.gold += instant_loot
				var cap_port: StructureData = redir["port"]
				var cap_route: PackedVector2Array = redir["route"]
				best_tgt.dest_port_id = cap_port.id
				if not _is_water_segment_clear(best_tgt.position, cap_route[0]):
					best_tgt.position = cap_route[0]
				best_tgt.waypoints = cap_route
				best_tgt.waypoint_index = 1 if cap_route.size() > 1 and _is_water_segment_clear(best_tgt.position, cap_route[1]) else 0
				trade_ship_captured.emit(ship.nation_id, best_tgt.position, instant_loot + best_tgt.gold_value)
			else:
				var full_loot: float = maxf(5000.0, round(raw_val * 0.65))
				best_tgt.gold_value = full_loot
				best_tgt.active = false
				if captor != null and captor.alive:
					captor.gold += full_loot
					trade_ship_captured.emit(captor.id, best_tgt.position, full_loot)
					trade_completed.emit(captor.id, best_tgt.position, full_loot)
			ship.add_xp(1)
		elif (not ship.manual_moving) and best_tgt.position.distance_to(patrol_ctr) <= ship.patrol_radius and sea_pathfinder.is_world_pos_navigable(best_tgt.position) and _is_water_segment_clear(ship.position, best_tgt.position):
			ship.waypoints = PackedVector2Array([ship.position, best_tgt.position])
			ship.waypoint_index = 1
	else:
		if dist <= 82.0 and ship.fire_cooldown_ticks <= 0:
			naval_shells.append({
				"id": _next_shell_id,
				"shooter_id": ship.id,
				"nation_id": ship.nation_id,
				"target_ship_id": best_tgt.id,
				"start_pos": ship.position,
				"target_pos": best_tgt.position,
				"progress": 0.0,
				"duration_ticks": clampi(int(round(dist * 0.45)), 16, 28),
				"damage": ship.get_shell_damage(),
			})
			_next_shell_id += 1
			ship.fire_cooldown_ticks = 52
			naval_shot_fired.emit(ship.position)
		elif (not ship.manual_moving) and dist > 44.0 and best_tgt.position.distance_to(patrol_ctr) <= ship.patrol_radius and sea_pathfinder.is_world_pos_navigable(best_tgt.position) and _is_water_segment_clear(ship.position, best_tgt.position):
			ship.waypoints = PackedVector2Array([ship.position, best_tgt.position])
			ship.waypoint_index = 1


func _assign_warship_patrol_wp(ship: ShipUnit) -> void:
	if ship.patrol_center == Vector2.ZERO:
		ship.patrol_center = ship.position
	for _attempt in range(10):
		var ang: float = _rng.randf_range(0.0, TAU)
		var rad: float = _rng.randf_range(24.0, ship.patrol_radius)
		var cand_w: Vector2 = ship.patrol_center + Vector2(cos(ang), sin(ang)) * rad
		cand_w.x = clampf(cand_w.x, 8.0, map_size.x - 8.0)
		cand_w.y = clampf(cand_w.y, 8.0, map_size.y - 8.0)
		if not sea_pathfinder.is_world_pos_navigable(cand_w):
			continue
		var mid_ang: float = ang - 0.55
		var mid_rad: float = clampf(rad * 0.78, 16.0, ship.patrol_radius)
		var mid_w: Vector2 = ship.patrol_center + Vector2(cos(mid_ang), sin(mid_ang)) * mid_rad
		mid_w.x = clampf(mid_w.x, 8.0, map_size.x - 8.0)
		mid_w.y = clampf(mid_w.y, 8.0, map_size.y - 8.0)
		if sea_pathfinder.is_world_pos_navigable(mid_w) and _is_water_segment_clear(ship.position, mid_w) and _is_water_segment_clear(mid_w, cand_w):
			ship.waypoints = PackedVector2Array([ship.position, mid_w, cand_w])
			ship.waypoint_index = 1
			return
		if _is_water_segment_clear(ship.position, cand_w):
			ship.waypoints = PackedVector2Array([ship.position, cand_w])
			ship.waypoint_index = 1
			return
	ship.waypoints = PackedVector2Array([ship.position])
	ship.waypoint_index = 1


func _is_water_segment_clear(a: Vector2, b: Vector2) -> bool:
	var dist: float = a.distance_to(b)
	var steps: int = maxi(4, int(ceil(dist / 0.5)))
	var inv_s: float = 1.0 / maxf(sim_scale, 0.25)
	for i in range(1, steps + 1):
		var pt: Vector2 = a.lerp(b, float(i) / float(steps))
		if not sea_pathfinder.is_world_pos_navigable(pt):
			return false
		var sx: int = clampi(int(floor(pt.x * inv_s)), 0, sim_width - 1)
		var sy: int = clampi(int(floor(pt.y * inv_s)), 0, sim_height - 1)
		if terrain_grid[sy * sim_width + sx] != T_OCEAN:
			return false
		var px_p: int = clampi(int(floor((pt.x + 0.15) * inv_s)), 0, sim_width - 1)
		var px_m: int = clampi(int(floor((pt.x - 0.15) * inv_s)), 0, sim_width - 1)
		var py_p: int = clampi(int(floor((pt.y + 0.15) * inv_s)), 0, sim_height - 1)
		var py_m: int = clampi(int(floor((pt.y - 0.15) * inv_s)), 0, sim_height - 1)
		if terrain_grid[sy * sim_width + px_p] != T_OCEAN or terrain_grid[sy * sim_width + px_m] != T_OCEAN or terrain_grid[py_p * sim_width + sx] != T_OCEAN or terrain_grid[py_m * sim_width + sx] != T_OCEAN:
			return false
	return true


func _step_naval_shells() -> void:
	if naval_shells.is_empty():
		return
	var any_sunk_landing := false
	for i in range(naval_shells.size() - 1, -1, -1):
		var sh_d: Dictionary = naval_shells[i]
		var dur: float = maxf(float(sh_d.get("duration_ticks", 8)), 1.0)
		var prog: float = float(sh_d.get("progress", 0.0)) + 1.0 / dur
		var tid: int = int(sh_d.get("target_ship_id", 0))
		var tgt: ShipUnit = ships.get(tid, null)
		if tgt != null and tgt.active:
			sh_d["target_pos"] = tgt.position
		if prog >= 1.0:
			if tgt != null and tgt.active:
				tgt.hp -= float(sh_d.get("damage", 26.0))
				if tgt.hp <= 0.0:
					tgt.active = false
					if tgt.kind == ShipUnit.KIND_LANDING:
						any_sunk_landing = true
					var shooter: ShipUnit = ships.get(int(sh_d.get("shooter_id", 0)), null)
					if shooter != null and shooter.active:
						shooter.add_xp(1)
					ship_destroyed.emit(tgt.position, tgt.kind)
			naval_shells.remove_at(i)
		else:
			sh_d["progress"] = prog
	if any_sunk_landing:
		expansion_updated.emit()


func _step_expansions() -> void:
	if expansions.is_empty():
		return
	var any_flipped := false
	var player_claimed_cells := 0
	var player_claimed_contested := false
	var player_lost_cells := 0
	var player_attacker_id := 0
	var done_ids: Array[int] = []

	for eid: int in expansions.keys():
		var order: ExpansionOrder = expansions[eid]
		var nation: NationData = nations.get(order.nation_id, null)
		if nation == null or not nation.alive or order.remaining_troops <= 0.5 or order.frontier_size() == 0:
			done_ids.append(eid)
			continue

		var troops_before: float = order.remaining_troops
		var base_rate: float = ((3.4 + order.remaining_troops / 22.0) / 1.45) * 4.0
		if order.is_contested:
			var en: NationData = nations.get(order.enemy_nation_id, null)
			var en_ref: float = maxf(en.troops * 0.25, 30.0) if en != null else 40.0
			var ratio_scale: float = clampf(order.remaining_troops / en_ref, 0.65, 1.55)
			base_rate *= ratio_scale
		var def_area_mult: float = get_defense_multiplier_at(order.enemy_nation_id, order.target_cell) if order.is_contested else 1.0
		if def_area_mult > 1.0:
			base_rate /= sqrt(def_area_mult)
		var max_claims: int = clampi(int(round(base_rate * order.supply_factor)), 8, 32 if order.is_contested else 40)
		var claimed_now := 0
		var pops_left: int = max_claims * 4
		var sum_x := 0.0
		var sum_y := 0.0

		while claimed_now < max_claims and pops_left > 0 and order.frontier_size() > 0 and order.remaining_troops > 0.5:
			pops_left -= 1
			var idx: int = order.pop_best()
			var t: int = terrain_grid[idx]
			var prev_owner: int = owner_grid[idx]
			if t < T_PLAINS or not _can_order_claim_owner(order.target_owner_id, prev_owner, order.nation_id):
				continue
			if fallout_grid[idx] > 0 and not order.allow_fallout:
				continue

			var cost: float = float(TERRAIN_COST.get(t, 1.0)) * 0.25
			if prev_owner == 0:
				cost *= NEUTRAL_EXPLORE_TROOP_COST_MULT
			else:
				var enemy: NationData = nations.get(prev_owner, null)
				var def_mult: float = 1.65
				if enemy != null:
					var eq_cells: float = maxf(float(enemy.owned_cell_count) * 0.25, 1.0)
					var density: float = enemy.troops / eq_cells
					def_mult += clampf(density * 0.16, 0.0, 0.95)
					enemy.troops = maxf(0.0, enemy.troops - clampf(0.55 + density * 0.04, 0.45, 1.4) * 0.25)
					def_mult *= get_defense_multiplier_at(prev_owner, Vector2i(idx % sim_width, int(idx / sim_width)))
					if enemy.is_betrayer(current_tick):
						def_mult *= 0.55
				if nation.is_betrayer(current_tick):
					def_mult *= 1.35
				cost *= def_mult
			if order.supply_factor < 1.0:
				cost *= 1.15
			if fallout_grid[idx] > 0:
				cost *= FALLOUT_TROOP_COST_MULT

			if order.remaining_troops < cost:
				order.remaining_troops = 0.0
				break

			order.remaining_troops -= cost
			_set_cell_owner(idx, order.nation_id)
			order.cells_claimed += 1
			claimed_now += 1
			if player_nation_id != 0:
				if order.nation_id == player_nation_id:
					player_claimed_cells += 1
					if prev_owner != 0:
						player_claimed_contested = true
				elif prev_owner == player_nation_id:
					player_lost_cells += 1
					player_attacker_id = order.nation_id
					last_player_threat_world_pos = Vector2(float(idx % sim_width) + 0.5, float(int(idx / sim_width)) + 0.5) * sim_scale
			sum_x += float(idx % sim_width)
			sum_y += float(int(idx / sim_width))
			any_flipped = true

			var parent_depth: float = order.get_cell_depth(idx)
			_push_adjacent_frontier(order, idx, order.nation_id, order.target_cell, parent_depth)

		if claimed_now > 0:
			var avg_w := Vector2((sum_x / float(claimed_now)) + 0.5, (sum_y / float(claimed_now)) + 0.5) * sim_scale
			order.front_world_pos = avg_w if order.front_world_pos == Vector2.ZERO else order.front_world_pos.lerp(avg_w, 0.35)
		elif order.front_world_pos == Vector2.ZERO and order.frontier_size() > 0:
			var p_idx: int = order.peek_best()
			order.front_world_pos = Vector2(float(p_idx % sim_width) + 0.5, float(int(p_idx / sim_width)) + 0.5) * sim_scale

		order.troop_flash_timer = maxf(0.0, order.troop_flash_timer - TICK_DT)
		if order.troop_flash_timer <= 0.0 and order.remaining_troops < troops_before:
			order.last_troop_delta = order.remaining_troops - troops_before

		order.eta_seconds = (order.remaining_troops * 4.0) / maxf(float(max_claims) * TICK_RATE_HZ, 1.0)
		if order.remaining_troops <= 0.5 or order.frontier_size() == 0:
			if order.remaining_troops > 0.5 and nation.alive:
				nation.troops = minf(nation.max_troops, nation.troops + order.remaining_troops)
			done_ids.append(eid)

	for did: int in done_ids:
		expansions.erase(did)

	if any_flipped:
		_economy_dirty = true
		owner_dirty = true
		territory_changed.emit()
		if player_claimed_cells > 0:
			player_land_conquered.emit(player_claimed_cells, player_claimed_contested)
		if player_lost_cells > 0:
			player_territory_attacked.emit(player_attacker_id, player_lost_cells)
	expansion_updated.emit()


func _set_cell_owner(idx: int, new_nid: int) -> void:
	var old_nid: int = owner_grid[idx]
	if old_nid == new_nid:
		return
	var y: int = int(idx / sim_width)
	var x: int = idx % sim_width
	var area: float = row_area_km2[y]
	var lm: int = landmass_grid[idx]
	var is_coast: bool = (coastal_grid[idx] == 1)

	if old_nid != 0 and nations.has(old_nid):
		var old_n: NationData = nations[old_nid]
		old_n.owned_cell_count = maxi(0, old_n.owned_cell_count - 1)
		old_n.cell_sum_x = maxf(0.0, old_n.cell_sum_x - float(x))
		old_n.cell_sum_y = maxf(0.0, old_n.cell_sum_y - float(y))
		old_n.label_dirty = true
		old_n.owned_area_km2 = maxf(0.0, old_n.owned_area_km2 - area)
		old_n.territory_percent = (old_n.owned_area_km2 / maxf(total_conquerable_area_km2, 1.0)) * 100.0
		(_nation_borders[old_nid] as Dictionary).erase(idx)
		if is_coast:
			(_nation_coasts[old_nid] as Dictionary).erase(idx)
		if lm > 0:
			var old_lms: Dictionary = _nation_landmasses[old_nid]
			var c: int = int(old_lms.get(lm, 0)) - 1
			if c <= 0:
				old_lms.erase(lm)
			else:
				old_lms[lm] = c
		if old_n.owned_cell_count == 0:
			old_n.alive = false
			if new_nid != 0 and nations.has(new_nid) and old_n.gold > 0.0:
				var spoils: float = old_n.gold if not old_n.is_player else floor(old_n.gold * 0.5)
				(nations[new_nid] as NationData).gold += spoils
				old_n.gold = 0.0
			nation_eliminated.emit(old_nid, new_nid)

	owner_grid[idx] = new_nid
	if new_nid != 0:
		if fallout_grid[idx] > 0:
			fallout_grid[idx] = 0
			fallout_cell_count = maxi(0, fallout_cell_count - 1)
		render_owner_grid[idx] = new_nid
	else:
		render_owner_grid[idx] = 255 if fallout_grid[idx] > 0 else 0

	if new_nid != 0 and nations.has(new_nid):
		var new_n: NationData = nations[new_nid]
		new_n.owned_cell_count += 1
		new_n.cell_sum_x += float(x)
		new_n.cell_sum_y += float(y)
		new_n.label_dirty = true
		new_n.owned_area_km2 += area
		new_n.territory_percent = (new_n.owned_area_km2 / maxf(total_conquerable_area_km2, 1.0)) * 100.0
		if is_coast:
			(_nation_coasts[new_nid] as Dictionary)[idx] = true
		if lm > 0:
			var new_lms: Dictionary = _nation_landmasses[new_nid]
			new_lms[lm] = int(new_lms.get(lm, 0)) + 1

		if old_nid != 0 and nations.has(old_nid):
			var old_nation: NationData = nations[old_nid]
			if not old_nation.structure_ids.is_empty():
				var cell_v := Vector2i(x, y)
				var captured_sids: Array[int] = []
				for sid: int in old_nation.structure_ids:
					var st: StructureData = structures.get(sid, null)
					if st != null and st.cell.distance_squared_to(cell_v) <= 8.0:
						captured_sids.append(sid)
				for sid: int in captured_sids:
					var st: StructureData = structures[sid]
					old_nation.structure_ids.erase(sid)
					if st.type == StructureData.TYPE_DEFENSE_POST:
						structures.erase(sid)
					else:
						st.nation_id = new_nid
						new_n.structure_ids.append(sid)
						_factory_links_dirty = true
					_economy_dirty = true
					structure_changed.emit(sid)

	_refresh_border_status_around(x, y, old_nid, new_nid)


func _refresh_border_status_around(x: int, y: int, old_nid: int, new_nid: int) -> void:
	for p: Vector2i in [
		Vector2i(x, y),
		Vector2i(x - 1, y),
		Vector2i(x + 1, y),
		Vector2i(x, y - 1),
		Vector2i(x, y + 1),
	]:
		var nx: int = p.x
		var ny: int = p.y
		if nx < 0 or nx >= sim_width or ny < 0 or ny >= sim_height:
			continue
		var n_idx: int = ny * sim_width + nx
		var o: int = owner_grid[n_idx]
		if o == 0 or (o != old_nid and o != new_nid):
			continue
		if _is_border_cell(nx, ny, o):
			(_nation_borders[o] as Dictionary)[n_idx] = true
		else:
			(_nation_borders[o] as Dictionary).erase(n_idx)


func _is_border_cell(x: int, y: int, nid: int) -> bool:
	if x > 0 and terrain_grid[y * sim_width + x - 1] >= T_PLAINS and owner_grid[y * sim_width + x - 1] != nid:
		return true
	if x < sim_width - 1 and terrain_grid[y * sim_width + x + 1] >= T_PLAINS and owner_grid[y * sim_width + x + 1] != nid:
		return true
	if y > 0 and terrain_grid[(y - 1) * sim_width + x] >= T_PLAINS and owner_grid[(y - 1) * sim_width + x] != nid:
		return true
	if y < sim_height - 1 and terrain_grid[(y + 1) * sim_width + x] >= T_PLAINS and owner_grid[(y + 1) * sim_width + x] != nid:
		return true
	return false


func _recompute_factory_links() -> void:
	"""OpenFront 1:1 rail/road network: computes Factory synergy for every in-range Town/Port/Factory,
	reuses all already-built roads in _road_cache across conquests, and builds multi-hop train routes."""
	factory_links.clear()
	_station_road_adj.clear()
	_factory_train_routes.clear()
	for sid: int in structures.keys():
		var st: StructureData = structures[sid]
		st.connection_bonus = 1.0
		st.factory_boost = 1.0
		st.connected_count = 0
		st.bridge_count = 0

	var new_keys := {}
	var created_regular := false
	var created_bridge := false
	# tgt_id -> Array of [fac: StructureData, dist: float]
	var in_range: Dictionary = {}
	var tgt_refs: Dictionary = {}
	var active_stations: Dictionary = {}

	for fid: int in structures.keys():
		var fac: StructureData = structures[fid]
		if fac.type != StructureData.TYPE_FACTORY or fac.level <= 0:
			continue
		var nation: NationData = nations.get(fac.nation_id, null)
		if nation == null or not nation.alive:
			continue
		active_stations[fac.id] = fac
		for tid: int in structures.keys():
			var tgt: StructureData = structures.get(tid, null)
			if tgt == null or tgt.id == fac.id or tgt.level <= 0:
				continue
			if tgt.type != StructureData.TYPE_TOWN and tgt.type != StructureData.TYPE_PORT and tgt.type != StructureData.TYPE_FACTORY:
				continue
			if tgt.nation_id != fac.nation_id:
				var tgt_n: NationData = nations.get(tgt.nation_id, null)
				if tgt_n == null or not tgt_n.alive or is_embargoed(fac.nation_id, tgt.nation_id):
					continue
			if tgt.type == StructureData.TYPE_FACTORY:
				if fac.id >= tgt.id:
					continue
				if not (fac.is_cell_in_factory_range(tgt.cell) or tgt.is_cell_in_factory_range(fac.cell)):
					continue
				active_stations[tid] = tgt
				fac.connected_count += 1
				fac.connection_bonus += 0.14 + float(fac.level) * 0.02
				tgt.connected_count += 1
				tgt.connection_bonus += 0.14 + float(tgt.level) * 0.02
				if not in_range.has(tid):
					in_range[tid] = []
					tgt_refs[tid] = tgt
				(in_range[tid] as Array).append([fac, Vector2(fac.cell - tgt.cell).length()])
				continue
			if not fac.is_cell_in_factory_range(tgt.cell):
				continue
			active_stations[tid] = tgt
			fac.connected_count += 1
			fac.connection_bonus += 0.14 + float(fac.level) * 0.02
			tgt.factory_boost += 0.12 + float(fac.level) * 0.02
			if not in_range.has(tid):
				in_range[tid] = []
				tgt_refs[tid] = tgt
			(in_range[tid] as Array).append([fac, Vector2(fac.cell - tgt.cell).length()])

	# Station adjacency graph (OpenFront 1:1 maxConnectionDistance = 4 hops)
	var adj: Dictionary = {}
	for st_id: int in active_stations.keys():
		adj[st_id] = []

	var added_road_keys: Dictionary = {}

	# 1. Preserve any existing road in _road_cache between active stations (including non-embargoed cross-border / factory-to-factory)
	for cache_key: String in _road_cache.keys():
		var parts: PackedStringArray = cache_key.split(":")
		if parts.size() != 2:
			continue
		var id_a: int = int(parts[0])
		var id_b: int = int(parts[1])
		if not active_stations.has(id_a) or not active_stations.has(id_b):
			continue
		var st_a: StructureData = active_stations[id_a]
		var st_b: StructureData = active_stations[id_b]
		if st_a.nation_id != st_b.nation_id and is_embargoed(st_a.nation_id, st_b.nation_id):
			continue
		var root_fac: StructureData = null
		var tgt_st: StructureData = null
		if st_a.type == StructureData.TYPE_FACTORY and st_b.type == StructureData.TYPE_FACTORY:
			root_fac = st_a if st_a.id < st_b.id else st_b
			tgt_st = st_b if st_a.id < st_b.id else st_a
		elif st_a.type == StructureData.TYPE_FACTORY and st_b.type != StructureData.TYPE_FACTORY:
			root_fac = st_a
			tgt_st = st_b
		elif st_b.type == StructureData.TYPE_FACTORY and st_a.type != StructureData.TYPE_FACTORY:
			root_fac = st_b
			tgt_st = st_a
		else:
			tgt_st = st_b if in_range.has(st_b.id) else st_a
			if in_range.has(tgt_st.id):
				root_fac = ((in_range[tgt_st.id] as Array)[0] as Array)[0]
		if root_fac == null or tgt_st == null:
			continue
		if root_fac.nation_id != tgt_st.nation_id and is_embargoed(root_fac.nation_id, tgt_st.nation_id):
			continue
		(adj[id_a] as Array).append(id_b)
		(adj[id_b] as Array).append(id_a)
		added_road_keys[cache_key] = true
		var road_c: Dictionary = _get_or_build_road(st_b, st_a) if st_b == root_fac else _get_or_build_road(st_a, st_b)
		var from_st: StructureData = st_b if st_b == root_fac else st_a
		var to_st: StructureData = st_a if st_b == root_fac else st_b
		var road_pts_c: PackedVector2Array = road_c["road_points"]
		var road_len_c: float = float(road_c["road_length"])
		var crosses_c: bool = bool(road_c["crosses_water"])
		factory_links.append({
			"factory_id": root_fac.id,
			"target_id": tgt_st.id,
			"nation_id": root_fac.nation_id,
			"from_cell": from_st.cell,
			"to_cell": to_st.cell,
			"from_world": from_st.get_world_pos(),
			"to_world": to_st.get_world_pos(),
			"road_points": road_pts_c,
			"road_length": road_len_c,
			"crosses_water": crosses_c,
			"water_spans": road_c["water_spans"],
		})
		_add_station_road_edge(from_st.id, to_st.id, road_pts_c, road_len_c, crosses_c)
		if crosses_c:
			root_fac.bridge_count += 1
		var k_c: String = "%d->%d" % [from_st.id, to_st.id]
		new_keys[k_c] = true
		if not _prev_link_keys.has(k_c):
			if crosses_c:
				created_bridge = true
			else:
				created_regular = true

	# 2. Connect any remaining station not yet within 4 hops of an in-range Factory
	for tid: int in in_range.keys():
		var tgt: StructureData = tgt_refs[tid]
		var best_fac: StructureData = null
		var best_d := 1e12
		var already_linked := false
		for entry: Array in in_range[tid]:
			var cf: StructureData = entry[0]
			var cd: float = entry[1]
			if cd < best_d:
				best_d = cd
				best_fac = cf
			if _are_stations_within_hops(adj, tid, cf.id, 4):
				already_linked = true
		if already_linked or best_fac == null:
			continue

		# Check if a nearby already-connected station (own or non-embargoed partner) is closer than best_fac
		var connect_from: StructureData = best_fac
		var connect_d: float = best_d
		for other_id: int in active_stations.keys():
			if other_id == tid:
				continue
			var other_st: StructureData = active_stations[other_id]
			if other_st.nation_id != tgt.nation_id:
				if other_st.nation_id != best_fac.nation_id or is_embargoed(other_st.nation_id, tgt.nation_id):
					continue
			if other_st.nation_id != best_fac.nation_id and is_embargoed(best_fac.nation_id, other_st.nation_id):
				continue
			if not _are_stations_within_hops(adj, other_id, best_fac.id, 3):
				continue
			var d_other: float = Vector2(other_st.cell - tgt.cell).length()
			if d_other < connect_d and d_other <= 84.0:
				connect_d = d_other
				connect_from = other_st

		var r_key: String = _road_key(connect_from.id, tgt.id)
		if added_road_keys.has(r_key):
			continue
		added_road_keys[r_key] = true
		(adj[connect_from.id] as Array).append(tgt.id)
		(adj[tgt.id] as Array).append(connect_from.id)

		var from_w: Vector2 = connect_from.get_world_pos()
		var to_w: Vector2 = tgt.get_world_pos()
		var road: Dictionary = _get_or_build_road(connect_from, tgt)
		var road_pts: PackedVector2Array = road["road_points"]
		var spans: Array = road["water_spans"]
		var crosses_water: bool = bool(road["crosses_water"])

		var road_len: float = float(road["road_length"])
		factory_links.append({
			"factory_id": best_fac.id,
			"target_id": tgt.id,
			"nation_id": best_fac.nation_id,
			"from_cell": connect_from.cell,
			"to_cell": tgt.cell,
			"from_world": from_w,
			"to_world": to_w,
			"road_points": road_pts,
			"road_length": road_len,
			"crosses_water": crosses_water,
			"water_spans": spans,
		})
		_add_station_road_edge(connect_from.id, tgt.id, road_pts, road_len, crosses_water)
		if crosses_water:
			best_fac.bridge_count += 1

		var key_str: String = "%d->%d" % [connect_from.id, tgt.id]
		new_keys[key_str] = true
		if not _prev_link_keys.has(key_str):
			if crosses_water:
				created_bridge = true
			else:
				created_regular = true

	_rebuild_factory_train_routes()
	_prev_link_keys = new_keys
	if created_bridge:
		factory_link_created.emit(true)
	elif created_regular:
		factory_link_created.emit(false)


static func _are_stations_within_hops(adj: Dictionary, start_id: int, goal_id: int, max_hops: int = 4) -> bool:
	if start_id == goal_id:
		return true
	var visited: Dictionary = {start_id: true}
	var frontier: Array[int] = [start_id]
	for _hop in range(max_hops):
		if frontier.is_empty():
			break
		var next_f: Array[int] = []
		for cur: int in frontier:
			var neighbors: Array = adj.get(cur, [])
			for nb_var in neighbors:
				var nb: int = int(nb_var)
				if nb == goal_id:
					return true
				if not visited.has(nb):
					visited[nb] = true
					next_f.append(nb)
		frontier = next_f
	return false


static func _road_key(id_a: int, id_b: int) -> String:
	return "%d:%d" % [mini(id_a, id_b), maxi(id_a, id_b)]


func _get_or_build_road(fac: StructureData, tgt: StructureData) -> Dictionary:
	"""Returns the cached road between two structures (canonical low-id -> high-id geometry),
	oriented fac -> tgt. Roads built before a conquest are reused as-is."""
	var key: String = _road_key(fac.id, tgt.id)
	if not _road_cache.has(key):
		var low: StructureData = fac if fac.id < tgt.id else tgt
		var high: StructureData = tgt if fac.id < tgt.id else fac
		var raw_pts: PackedVector2Array = _build_irregular_road_points(low, high)
		var shaped: Dictionary = _straighten_water_spans_in_road(raw_pts)
		var pts: PackedVector2Array = shaped["road_points"]
		var w_spans: Array = shaped["water_spans"]
		_road_cache[key] = {
			"road_points": pts,
			"road_length": _compute_route_length(pts),
			"water_spans": w_spans,
		}
	var entry: Dictionary = _road_cache[key]
	var canon: PackedVector2Array = entry["road_points"]
	var out_pts: PackedVector2Array = _reverse_polyline(canon) if fac.id > tgt.id else canon
	var spans: Array = entry["water_spans"]
	return {
		"road_points": out_pts,
		"road_length": entry["road_length"],
		"water_spans": spans,
		"crosses_water": not spans.is_empty(),
	}


static func _reverse_polyline(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in range(pts.size()):
		out[i] = pts[pts.size() - 1 - i]
	return out


func _add_station_road_edge(id_a: int, id_b: int, pts_a_to_b: PackedVector2Array, r_len: float, crosses_w: bool) -> void:
	if pts_a_to_b.size() < 2:
		return
	if not _station_road_adj.has(id_a):
		_station_road_adj[id_a] = []
	if not _station_road_adj.has(id_b):
		_station_road_adj[id_b] = []
	(_station_road_adj[id_a] as Array).append({
		"to_id": id_b,
		"road_points": pts_a_to_b,
		"road_length": r_len,
		"crosses_water": crosses_w,
	})
	(_station_road_adj[id_b] as Array).append({
		"to_id": id_a,
		"road_points": _reverse_polyline(pts_a_to_b),
		"road_length": r_len,
		"crosses_water": crosses_w,
	})


func _rebuild_factory_train_routes() -> void:
	"""Builds 1..8-hop BFS train routes from every active Factory across ALL connected roads."""
	for fid: int in structures.keys():
		var fac: StructureData = structures[fid]
		if fac.type != StructureData.TYPE_FACTORY or fac.level <= 0:
			continue
		var fac_n: NationData = nations.get(fac.nation_id, null)
		if fac_n == null or not fac_n.alive:
			continue
		var queue: Array[int] = [fid]
		var head := 0
		var hop_dist: Dictionary = {fid: 0}
		var parent_edge: Dictionary = {}
		var dest_order: Array[int] = []
		while head < queue.size():
			var cur: int = queue[head]
			head += 1
			var d_cur: int = int(hop_dist[cur])
			if d_cur >= 8:
				continue
			for edge: Dictionary in _station_road_adj.get(cur, []):
				var nxt_id: int = int(edge["to_id"])
				if hop_dist.has(nxt_id):
					continue
				var nxt_st: StructureData = structures.get(nxt_id, null)
				if nxt_st == null or nxt_st.level <= 0:
					continue
				var nxt_n: NationData = nations.get(nxt_st.nation_id, null)
				if nxt_n == null or not nxt_n.alive:
					continue
				if nxt_st.nation_id != fac.nation_id and is_embargoed(fac.nation_id, nxt_st.nation_id):
					continue
				hop_dist[nxt_id] = d_cur + 1
				parent_edge[nxt_id] = {"prev_id": cur, "edge": edge}
				queue.append(nxt_id)
				dest_order.append(nxt_id)
		if dest_order.is_empty():
			continue
		var routes: Array[Dictionary] = []
		for dest_id: int in dest_order:
			var chain: Array[Dictionary] = []
			var trace_id: int = dest_id
			while trace_id != fid and parent_edge.has(trace_id):
				var step_info: Dictionary = parent_edge[trace_id]
				chain.append(step_info["edge"])
				trace_id = int(step_info["prev_id"])
			chain.reverse()
			var hop_ids: Array[int] = [fid]
			var combined := PackedVector2Array()
			var total_len := 0.0
			var any_water := false
			for edge: Dictionary in chain:
				hop_ids.append(int(edge["to_id"]))
				var e_pts: PackedVector2Array = edge["road_points"]
				if combined.is_empty():
					combined.append_array(e_pts)
				elif e_pts.size() > 1:
					for pi in range(1, e_pts.size()):
						combined.append(e_pts[pi])
				total_len += float(edge["road_length"])
				any_water = any_water or bool(edge["crosses_water"])
			if combined.size() >= 2:
				routes.append({
					"target_id": dest_id,
					"hop_ids": hop_ids,
					"hops": hop_ids.size() - 1,
					"road_points": combined,
					"road_length": total_len,
					"crosses_water": any_water,
				})
		if not routes.is_empty():
			_factory_train_routes[fid] = routes


func _straighten_water_spans_in_road(raw_pts: PackedVector2Array) -> Dictionary:
	"""Preserves winding curves across land and replaces water crossings with straight Bridge spans."""
	var out_pts := PackedVector2Array()
	var spans: Array = []
	if raw_pts.is_empty():
		return {"road_points": out_pts, "water_spans": spans}
	out_pts.append(raw_pts[0])
	if raw_pts.size() < 2:
		return {"road_points": out_pts, "water_spans": spans}

	var in_water := false
	var span_entry: Vector2 = raw_pts[0]
	var prev_land: Vector2 = raw_pts[0]
	for seg_i in range(raw_pts.size() - 1):
		var p0: Vector2 = raw_pts[seg_i]
		var p1: Vector2 = raw_pts[seg_i + 1]
		var steps: int = maxi(4, int(ceil(p0.distance_to(p1))))
		for s in range(1, steps + 1):
			var w_pt: Vector2 = p0.lerp(p1, float(s) / float(steps))
			var sim_pt := world_to_sim(w_pt)
			var is_water: bool = terrain_grid[sim_pt.y * sim_width + sim_pt.x] < T_PLAINS
			if is_water:
				if not in_water:
					in_water = true
					if prev_land.distance_to(out_pts[out_pts.size() - 1]) > 0.25:
						out_pts.append(prev_land)
					span_entry = out_pts[out_pts.size() - 1]
			else:
				if in_water:
					in_water = false
					if w_pt.distance_to(out_pts[out_pts.size() - 1]) > 0.25:
						out_pts.append(w_pt)
					var span_exit: Vector2 = out_pts[out_pts.size() - 1]
					if span_entry.distance_to(span_exit) >= 1.2:
						spans.append([span_entry, span_exit])
				elif s == steps and w_pt.distance_to(out_pts[out_pts.size() - 1]) > 0.25:
					out_pts.append(w_pt)
				prev_land = w_pt

	var last_pt: Vector2 = raw_pts[raw_pts.size() - 1]
	if in_water:
		if last_pt.distance_to(out_pts[out_pts.size() - 1]) > 0.25:
			out_pts.append(last_pt)
		var final_exit: Vector2 = out_pts[out_pts.size() - 1]
		if span_entry.distance_to(final_exit) >= 1.2:
			spans.append([span_entry, final_exit])
	elif last_pt.distance_to(out_pts[out_pts.size() - 1]) > 0.25:
		out_pts.append(last_pt)
	return {"road_points": out_pts, "water_spans": spans}


func _prune_road_cache(structure_id: int) -> void:
	for key: String in _road_cache.keys():
		var parts: PackedStringArray = key.split(":")
		if int(parts[0]) == structure_id or int(parts[1]) == structure_id:
			_road_cache.erase(key)


func _build_irregular_road_points(fac: StructureData, tgt: StructureData) -> PackedVector2Array:
	var from_w: Vector2 = fac.get_world_pos()
	var to_w: Vector2 = tgt.get_world_pos()
	var d_vec: Vector2 = to_w - from_w
	var dist: float = d_vec.length()
	if dist < 2.0:
		return PackedVector2Array([from_w, to_w])

	var perp := Vector2(-d_vec.y, d_vec.x) / dist
	var h_seed: int = (fac.id * 73856093) ^ (tgt.id * 19349663) ^ (fac.cell.x * 83492791) ^ (tgt.cell.y * 297121507)
	var ph1: float = float(abs(h_seed) % 360) * 0.01745329
	var ph2: float = float(abs(h_seed >> 7) % 360) * 0.01745329
	var sgn: float = 1.0 if ((h_seed & 1) == 0) else -1.0
	var amp1: float = clampf(dist * 0.075, 1.8, 6.5) * sgn
	var amp2: float = clampf(dist * 0.03, 0.8, 2.8) * (-sgn)

	var num_segs: int = clampi(int(ceil(dist / 5.0)), 10, 28)
	var pts := PackedVector2Array()
	pts.resize(num_segs + 1)
	for i in range(num_segs + 1):
		if i == 0:
			pts[i] = from_w
		elif i == num_segs:
			pts[i] = to_w
		else:
			var t: float = float(i) / float(num_segs)
			var env: float = sin(PI * t)
			var off: float = env * (amp1 * sin(t * PI * 2.1 + ph1) + amp2 * cos(t * PI * 4.3 + ph2))
			var pt: Vector2 = from_w.lerp(to_w, t) + perp * off
			pt.x = clampf(pt.x, 2.0, map_size.x - 2.0)
			pt.y = clampf(pt.y, 2.0, map_size.y - 2.0)
			pts[i] = pt
	return pts


func _find_water_spans_along_road(road_pts: PackedVector2Array) -> Array:
	var spans: Array = []
	if road_pts.size() < 2:
		return spans
	var in_water := false
	var span_start := Vector2.ZERO
	var last_water := Vector2.ZERO

	for seg_i in range(road_pts.size() - 1):
		var p0: Vector2 = road_pts[seg_i]
		var p1: Vector2 = road_pts[seg_i + 1]
		var seg_dir: Vector2 = (p1 - p0).normalized()
		var steps: int = maxi(4, int(ceil(p0.distance_to(p1) / 1.0)))
		for s in range(steps + 1):
			var w_pt: Vector2 = p0.lerp(p1, float(s) / float(steps))
			var sim_pt := world_to_sim(w_pt)
			var is_water: bool = terrain_grid[sim_pt.y * sim_width + sim_pt.x] < T_PLAINS
			if is_water:
				if not in_water:
					in_water = true
					span_start = w_pt - seg_dir * 0.8
				last_water = w_pt + seg_dir * 0.8
			elif in_water:
				in_water = false
				if span_start.distance_to(last_water) >= 1.2:
					spans.append([span_start, last_water])
	if in_water and span_start.distance_to(last_water) >= 1.2:
		spans.append([span_start, last_water])
	return spans


static func _sample_polyline(pts: PackedVector2Array, frac: float, reverse: bool = false, precomputed_len: float = 0.0) -> Dictionary:
	if pts.size() < 2:
		var p0: Vector2 = pts[0] if pts.size() == 1 else Vector2.ZERO
		return {"pos": p0, "heading": 0.0}
	var total_len: float = precomputed_len
	if total_len <= 0.0:
		for i in range(pts.size() - 1):
			total_len += pts[i].distance_to(pts[i + 1])
	if total_len <= 0.01:
		return {"pos": pts[0], "heading": 0.0}
	var f: float = clampf(frac, 0.0, 1.0)
	var target_d: float = (1.0 - f if reverse else f) * total_len
	var accum := 0.0
	var last_i: int = pts.size() - 2
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg_d: float = a.distance_to(b)
		if accum + seg_d >= target_d or i == last_i:
			var t: float = clampf((target_d - accum) / maxf(seg_d, 0.001), 0.0, 1.0)
			var h: float = (b - a).angle()
			return {"pos": a.lerp(b, t), "heading": h + PI if reverse else h}
		accum += seg_d
	return {"pos": pts[pts.size() - 1], "heading": 0.0}


func _recompute_all_economy_rates() -> void:
	for nid: int in nations.keys():
		var n: NationData = nations[nid]
		if not n.alive:
			n.gold_per_sec = 0.0
			n.troops_per_sec = 0.0
			continue
		var c_cnt: float = maxf(float(n.owned_cell_count) * 0.25, 1.0)
		var g_rate: float = 140.0 + pow(c_cnt, 0.58) * 18.0
		var t_cap: float = 2600.0 + pow(c_cnt, 0.56) * 85.0
		var t_rate: float = 30.0 + pow(c_cnt, 0.52) * 1.15

		for sid: int in n.structure_ids:
			var st: StructureData = structures.get(sid, null)
			if st == null:
				continue
			g_rate += st.get_gold_per_sec()
			t_cap += st.get_max_troops_bonus()
			t_rate += st.get_troops_per_sec_bonus()

		n.gold_per_sec = g_rate
		n.max_troops = t_cap
		n.troops_per_sec = t_rate


func _check_victory() -> void:
	if winner_nation_id != 0:
		return
	var team_pcts: Dictionary = {}
	var team_leaders: Dictionary = {}
	for nid: int in nations.keys():
		var n: NationData = nations[nid]
		if n.alive and n.territory_percent >= VICTORY_THRESHOLD_PERCENT:
			winner_nation_id = n.id
			winner_team_id = n.team_id
			match_phase = PHASE_VICTORY
			victory_reached.emit(n.id, n.territory_percent)
			return
		if n.alive and n.team_id > 0:
			team_pcts[n.team_id] = float(team_pcts.get(n.team_id, 0.0)) + n.territory_percent
			var cur_lead: NationData = team_leaders.get(n.team_id, null)
			if cur_lead == null or n.territory_percent > cur_lead.territory_percent:
				team_leaders[n.team_id] = n
	for tid: int in team_pcts.keys():
		var total_pct: float = float(team_pcts[tid])
		if total_pct >= VICTORY_THRESHOLD_PERCENT:
			var lead: NationData = team_leaders[tid]
			winner_nation_id = lead.id
			winner_team_id = tid
			match_phase = PHASE_VICTORY
			victory_reached.emit(lead.id, total_pct)
			return


func _reject(reason: String) -> Dictionary:
	command_rejected.emit(reason)
	return {"ok": false, "reason": reason}


func get_nation_borders(nid: int) -> Dictionary:
	return _nation_borders.get(nid, {})


func count_active_expansions(nid: int) -> int:
	var c := 0
	for eid: int in expansions.keys():
		if (expansions[eid] as ExpansionOrder).nation_id == nid:
			c += 1
	return c


func get_player_nation() -> NationData:
	return nations.get(player_nation_id, null)


func get_nation(nid: int) -> NationData:
	return nations.get(nid, null)


func get_nation_label_cell(nid: int) -> Vector2i:
	var n: NationData = nations.get(nid, null)
	if n == null:
		return Vector2i(-1, -1)
	if not n.alive or n.owned_cell_count <= 0:
		return n.capital_cell
	if n.label_cell.x >= 0 and get_owner_at(n.label_cell.x, n.label_cell.y) == nid and (not n.label_dirty or current_tick - n.label_recompute_tick < 8):
		return n.label_cell
	n.label_recompute_tick = current_tick

	var cx: int = clampi(int(round(n.cell_sum_x / float(n.owned_cell_count))), 0, sim_width - 1)
	var cy: int = clampi(int(round(n.cell_sum_y / float(n.owned_cell_count))), 0, sim_height - 1)
	var best_cell := Vector2i(-1, -1)
	if get_owner_at(cx, cy) == nid:
		best_cell = Vector2i(cx, cy)
	else:
		var fallback_owned := Vector2i(-1, -1)
		var r := 4
		while r <= 96 and best_cell.x < 0:
			for s_i in range(16):
				var ang: float = float(s_i) * (TAU / 16.0)
				var sx: int = clampi(cx + int(round(cos(ang) * float(r))), 0, sim_width - 1)
				var sy: int = clampi(cy + int(round(sin(ang) * float(r))), 0, sim_height - 1)
				if get_owner_at(sx, sy) != nid:
					continue
				if fallback_owned.x < 0:
					fallback_owned = Vector2i(sx, sy)
				var interior := (
					get_owner_at(sx - 1, sy) == nid and get_owner_at(sx + 1, sy) == nid
					and get_owner_at(sx, sy - 1) == nid and get_owner_at(sx, sy + 1) == nid
				)
				if interior:
					best_cell = Vector2i(sx, sy)
					break
			r += 6
		if best_cell.x < 0:
			if fallback_owned.x >= 0:
				best_cell = fallback_owned
			elif n.capital_cell.x >= 0 and get_owner_at(n.capital_cell.x, n.capital_cell.y) == nid:
				best_cell = n.capital_cell
			else:
				var borders: Dictionary = _nation_borders.get(nid, {})
				if not borders.is_empty():
					var b_idx: int = int(borders.keys()[0])
					best_cell = Vector2i(b_idx % sim_width, int(b_idx / sim_width))
				else:
					best_cell = n.capital_cell

	n.label_cell = best_cell
	n.label_dirty = false
	return best_cell


func get_nation_label_scale(nid: int) -> float:
	var n: NationData = nations.get(nid, null)
	if n == null or n.owned_cell_count <= 0:
		return 0.72
	return clampf(0.55 + sqrt(maxf(float(n.owned_cell_count) * 0.25, 20.0)) / 36.0, NATION_LABEL_MIN_SCALE, NATION_LABEL_MAX_SCALE)


func get_structure(sid: int) -> StructureData:
	return structures.get(sid, null)


func find_structure_near(world_pos: Vector2, max_dist_px: float = 14.0) -> StructureData:
	var best: StructureData = null
	var best_d := max_dist_px
	for sid: int in structures.keys():
		var st: StructureData = structures[sid]
		var d: float = st.get_world_pos().distance_to(world_pos)
		if d <= best_d:
			best_d = d
			best = st
	return best


func get_cell_info(sx: int, sy: int) -> Dictionary:
	var t: int = get_terrain_at(sx, sy)
	var own: int = get_owner_at(sx, sy)
	var region_name := "Open Waters"
	if t >= T_PLAINS and not region_labels.is_empty():
		var best_d2 := 1e12
		for r: Dictionary in region_labels:
			var dx: float = float(sx) - float(r.get("x", 0.0))
			var dy: float = float(sy) - float(r.get("y", 0.0))
			var d2: float = dx * dx + dy * dy
			if d2 < best_d2:
				best_d2 = d2
				region_name = str(r.get("name", "Earth"))
	elif t == T_LAKE:
		region_name = "Inland Lake"
	return {
		"terrain": t,
		"terrain_name": str(TERRAIN_NAMES.get(t, "Unknown")),
		"owner_id": own,
		"fallout": is_fallout_at(sx, sy),
		"coastal": (coastal_grid[sy * sim_width + sx] == 1) if (sx >= 0 and sy >= 0 and sx < sim_width and sy < sim_height) else false,
		"region_hint": region_name,
	}


func get_leaderboard() -> Array[NationData]:
	var list: Array[NationData] = []
	for nid: int in nations.keys():
		list.append(nations[nid])
	list.sort_custom(func(a: NationData, b: NationData) -> bool:
		if not is_equal_approx(a.owned_area_km2, b.owned_area_km2):
			return a.owned_area_km2 > b.owned_area_km2
		return a.id < b.id
	)
	return list


func get_claimed_percent() -> float:
	if total_conquerable_area_km2 <= 0.0:
		return 0.0
	var total := 0.0
	for nid: int in nations.keys():
		total += (nations[nid] as NationData).owned_area_km2
	return (total / total_conquerable_area_km2) * 100.0


func get_defense_multiplier_at(owner_nid: int, cell: Vector2i) -> float:
	var owner_n: NationData = nations.get(owner_nid, null)
	if owner_n == null or owner_n.structure_ids.is_empty():
		return 1.0
	var best_mult := 1.0
	for sid: int in owner_n.structure_ids:
		var st: StructureData = structures.get(sid, null)
		if st != null and st.type == StructureData.TYPE_DEFENSE_POST and not st.is_constructing and st.level > 0:
			if st.cell.distance_to(cell) <= st.get_defense_radius():
				best_mult = maxf(best_mult, st.get_defense_multiplier())
	return best_mult


func are_allied(a: int, b: int) -> bool:
	if a <= 0 or b <= 0 or a == b:
		return false
	var na: NationData = nations.get(a, null)
	if na == null or not na.alive:
		return false
	if na.team_id > 0:
		var nb: NationData = nations.get(b, null)
		if nb != null and nb.alive and nb.team_id == na.team_id:
			return true
	return na.alliances.has(b) and int(na.alliances[b]) > current_tick


func is_embargoed(a: int, b: int) -> bool:
	if a <= 0 or b <= 0 or a == b:
		return false
	var na: NationData = nations.get(a, null)
	var nb: NationData = nations.get(b, null)
	return (na != null and na.embargoes.has(b)) or (nb != null and nb.embargoes.has(a))


func find_warship_near(world_pos: Vector2, max_dist_px: float = 16.0, only_nation_id: int = 0) -> ShipUnit:
	var best: ShipUnit = null
	var best_d := max_dist_px
	for sid: int in ships.keys():
		var sh: ShipUnit = ships[sid]
		if not sh.active or sh.kind != ShipUnit.KIND_WARSHIP:
			continue
		if only_nation_id > 0 and sh.nation_id != only_nation_id:
			continue
		var d: float = sh.position.distance_to(world_pos)
		if d <= best_d:
			best_d = d
			best = sh
	return best


func _cmd_build_warship(cmd: Dictionary) -> Dictionary:
	if match_phase != PHASE_PLAYING:
		return _reject("Match is not active.")
	var nid: int = int(cmd.get("nation_id", 0))
	var port_id: int = int(cmd.get("port_id", 0))
	var nation: NationData = nations.get(nid, null)
	if nation == null or not nation.alive:
		return _reject("Invalid nation.")
	var port: StructureData = structures.get(port_id, null)
	if port == null or port.nation_id != nid or port.type != StructureData.TYPE_PORT:
		return _reject("Select one of your Ports to commission a Warship.")
	if port.is_constructing or port.level <= 0:
		return _reject("Port must finish construction before commissioning Warships.")
	if port.action_cooldown_ticks > 0:
		return _reject("Port drydock preparing next hull (%.1fs)." % (float(port.action_cooldown_ticks) / float(TICK_RATE_HZ)))
	if port.water_cell.x < 0:
		return _reject("No navigable water exit at this Port.")

	var cost: float = get_warship_build_cost(nid)
	if nation.gold < cost:
		return _reject("Need %s Pesos to commission a Warship." % StructureData.format_pesos(cost))

	nation.gold -= cost
	port.action_cooldown_ticks = 36

	var ship := ShipUnit.new()
	ship.id = _next_ship_id
	_next_ship_id += 1
	ship.kind = ShipUnit.KIND_WARSHIP
	ship.nation_id = nid
	ship.source_port_id = port.id
	var start_w: Vector2 = sea_pathfinder.nav_to_world(port.water_cell)
	ship.position = start_w
	ship.patrol_center = start_w
	ship.base_speed_px_per_sec = (18.5 + float(port.level) * 0.55) * 0.55
	ship.refresh_warship_speed()
	ship.hp = 100.0
	ship.max_hp = 100.0
	ship.manual_moving = false

	if cmd.has("x") and cmd.has("y"):
		var tgt_cell := Vector2i(clampi(int(cmd["x"]), 0, sim_width - 1), clampi(int(cmd["y"]), 0, sim_height - 1))
		var dst_nav: Vector2i = sea_pathfinder.find_nearest_nav_cell(tgt_cell, 8)
		if dst_nav.x >= 0:
			var route: PackedVector2Array = sea_pathfinder.find_path(port.water_cell, dst_nav)
			if not route.is_empty():
				ship.waypoints = route
				ship.waypoint_index = 1 if route.size() > 1 and _is_water_segment_clear(ship.position, route[1]) else 0
				ship.patrol_center = route[route.size() - 1]
				ship.manual_moving = true

	if ship.waypoints.is_empty():
		_assign_warship_patrol_wp(ship)

	ships[ship.id] = ship
	ship_launched.emit(ship.id)
	return {"ok": true, "ship_id": ship.id, "cost": cost}


func _cmd_command_warship(cmd: Dictionary) -> Dictionary:
	if match_phase != PHASE_PLAYING:
		return _reject("Match is not active.")
	var nid: int = int(cmd.get("nation_id", 0))
	var sid: int = int(cmd.get("ship_id", 0))
	var ship: ShipUnit = ships.get(sid, null)
	if ship == null or not ship.active or ship.nation_id != nid or ship.kind != ShipUnit.KIND_WARSHIP:
		return _reject("Warship not found.")
	var sx: int = clampi(int(cmd.get("x", 0)), 0, sim_width - 1)
	var sy: int = clampi(int(cmd.get("y", 0)), 0, sim_height - 1)
	var dst_nav: Vector2i = sea_pathfinder.find_nearest_nav_cell(Vector2i(sx, sy), 8)
	if dst_nav.x < 0:
		return _reject("Select navigable ocean waters for Warship patrol.")
	var cur_sim: Vector2i = world_to_sim(ship.position)
	var src_nav: Vector2i = sea_pathfinder.find_nearest_nav_cell(cur_sim, 4)
	if src_nav.x < 0:
		return _reject("Warship cannot chart route from current waters.")
	var route: PackedVector2Array = sea_pathfinder.find_path(src_nav, dst_nav)
	if route.is_empty():
		return _reject("No navigable sea route to that patrol point.")
	if not _is_water_segment_clear(ship.position, route[0]):
		ship.position = route[0]
	ship.waypoints = route
	if route.size() > 1 and _is_water_segment_clear(ship.position, route[1]):
		ship.waypoint_index = 1
	else:
		ship.waypoint_index = 0
	ship.manual_moving = true
	ship.repair_retreating = false
	ship.docked_port_id = 0
	ship.last_manual_order_tick = current_tick
	ship.target_ship_id = 0
	ship.patrol_center = route[route.size() - 1]
	return {"ok": true, "ship_id": ship.id}


func find_ready_silo(nid: int, target_cell: Vector2i, preferred_sid: int = 0) -> StructureData:
	if preferred_sid > 0:
		var pref: StructureData = structures.get(preferred_sid, null)
		if pref != null and pref.nation_id == nid and pref.type == StructureData.TYPE_MISSILE_SILO and not pref.is_constructing and pref.level >= 1:
			return pref
		return null
	var nation: NationData = nations.get(nid, null)
	if nation == null:
		return null
	var best_ready: StructureData = null
	var best_d2 := 1e12
	var any_silo: StructureData = null
	for sid: int in nation.structure_ids:
		var st: StructureData = structures.get(sid, null)
		if st == null or st.type != StructureData.TYPE_MISSILE_SILO or st.is_constructing or st.level <= 0:
			continue
		if any_silo == null or st.action_cooldown_ticks < any_silo.action_cooldown_ticks:
			any_silo = st
		if st.action_cooldown_ticks == 0:
			var d2: float = Vector2(st.cell - target_cell).length_squared()
			if d2 < best_d2:
				best_d2 = d2
				best_ready = st
	return best_ready if best_ready != null else any_silo


func _cmd_launch_missile(cmd: Dictionary) -> Dictionary:
	if match_phase != PHASE_PLAYING:
		return _reject("Match is not active.")
	if no_nukes:
		return _reject("Nuclear missiles are disabled (Conventional Mode).")
	var nid: int = int(cmd.get("nation_id", 0))
	var nation: NationData = nations.get(nid, null)
	if nation == null or not nation.alive:
		return _reject("Invalid nation.")
	var kind: String = str(cmd.get("missile_kind", MissileUnit.KIND_ATOM))
	if not (kind in [MissileUnit.KIND_ATOM, MissileUnit.KIND_HYDROGEN, MissileUnit.KIND_MIRV]):
		return _reject("Unsupported strategic warhead type.")

	var sx: int = clampi(int(cmd.get("x", -1)), 0, sim_width - 1)
	var sy: int = clampi(int(cmd.get("y", -1)), 0, sim_height - 1)
	var target_owner: int = get_owner_at(sx, sy)
	if target_owner == nid:
		return _reject("Cannot launch warheads onto your own territory.")
	if target_owner > 0 and are_allied(nid, target_owner):
		return _reject("Cannot launch warheads onto an allied nation.")
	if kind == MissileUnit.KIND_MIRV:
		if target_owner <= 0:
			return _reject("MIRV can only target a conquered nation's territory (cannot target unconquered land).")
		if target_owner == nid:
			return _reject("Cannot target your own territory with a MIRV.")

	# Always launch from the nearest ready completed Silo to the target (infinite range)
	var silo: StructureData = find_ready_silo(nid, Vector2i(sx, sy), 0)
	if silo == null:
		return _reject("Build and finish a Missile Silo first.")
	if silo.action_cooldown_ticks > 0:
		return _reject("Missile Silo reloading (%.1fs)." % (float(silo.action_cooldown_ticks) / float(TICK_RATE_HZ)))

	var cost: float = MissileUnit.get_cost(kind)
	if nation.gold < cost:
		return _reject("Need %s Pesos to launch %s." % [StructureData.format_pesos(cost), kind.to_upper()])

	nation.gold -= cost
	silo.action_cooldown_ticks = silo.get_silo_cooldown_ticks()

	var m := MissileUnit.new()
	m.id = _next_missile_id
	_next_missile_id += 1
	m.kind = kind
	m.nation_id = nid
	m.source_structure_id = silo.id
	m.start_pos = silo.get_world_pos()
	m.pos = m.start_pos
	m.ground_pos = m.start_pos
	m.target_cell = Vector2i(sx, sy)
	m.target_nation_id = target_owner
	m.target_pos = sim_to_world(m.target_cell)
	m.speed_px_sec = MissileUnit.get_speed(kind)
	m.blast_radius_sim = MissileUnit.get_blast_radius(kind)
	m.compute_ballistic_curve(false)
	missiles[m.id] = m
	var shooter_n: NationData = nations.get(nid, null)
	if shooter_n != null:
		shooter_n.nukes_launched += 1
	if m.target_nation_id == player_nation_id and nid != player_nation_id:
		last_player_threat_world_pos = m.target_pos
	missile_launched.emit(m.id, m.kind)
	return {"ok": true, "missile_id": m.id, "silo_id": silo.id}


func _step_sam_launchers() -> void:
	if missiles.is_empty():
		return
	var targeted_ids: Dictionary = {}
	for mid: int in missiles.keys():
		var m_ex: MissileUnit = missiles[mid]
		if m_ex.active and m_ex.kind == MissileUnit.KIND_SAM and m_ex.target_missile_id > 0:
			targeted_ids[m_ex.target_missile_id] = true

	for sid: int in structures.keys():
		var sam: StructureData = structures[sid]
		if sam.type != StructureData.TYPE_SAM_LAUNCHER or sam.is_constructing or sam.level <= 0 or sam.action_cooldown_ticks > 0 or sam.sam_ammo <= 0:
			continue
		var sam_pos: Vector2 = sam.get_world_pos()
		var max_r_w: float = sam.get_sam_radius()
		var best_m: MissileUnit = null
		var best_d := max_r_w
		for mid: int in missiles.keys():
			var inc: MissileUnit = missiles[mid]
			if not inc.active or inc.kind == MissileUnit.KIND_SAM:
				continue
			if inc.nation_id == sam.nation_id or are_allied(sam.nation_id, inc.nation_id):
				continue
			if targeted_ids.has(inc.id):
				continue
			var d: float = sam_pos.distance_to(inc.pos)
			if d <= best_d:
				best_d = d
				best_m = inc

		if best_m != null:
			var sam_m := MissileUnit.new()
			sam_m.id = _next_missile_id
			_next_missile_id += 1
			sam_m.kind = MissileUnit.KIND_SAM
			sam_m.nation_id = sam.nation_id
			sam_m.source_structure_id = sam.id
			sam_m.start_pos = sam_pos
			sam_m.pos = sam_pos
			sam_m.target_pos = best_m.pos
			sam_m.target_missile_id = best_m.id
			sam_m.speed_px_sec = MissileUnit.get_speed(MissileUnit.KIND_SAM)
			missiles[sam_m.id] = sam_m
			targeted_ids[best_m.id] = true
			var full_cd: int = sam.get_sam_cooldown_ticks()
			var half_cd: int = maxi(1, int(ceil(float(full_cd) * 0.5)))
			sam.sam_reload_ticks = mini(full_cd, sam.sam_reload_ticks + half_cd)
			sam.sam_ammo = 2 if sam.sam_reload_ticks == 0 else (1 if sam.sam_reload_ticks <= half_cd else 0)
			sam.action_cooldown_ticks = 14
			missile_launched.emit(sam_m.id, MissileUnit.KIND_SAM)


func _step_missiles() -> void:
	if missiles.is_empty():
		return
	var done_ids: Array[int] = []
	var detonations: Array[MissileUnit] = []
	var intercepts: Array[Vector2] = []

	for mid: int in missiles.keys():
		var m: MissileUnit = missiles[mid]
		if not m.active:
			done_ids.append(mid)
			continue
		if m.kind == MissileUnit.KIND_SAM:
			var tgt: MissileUnit = missiles.get(m.target_missile_id, null)
			if tgt == null or not tgt.active:
				m.active = false
				done_ids.append(mid)
				continue
			var tgt_vis: Vector2 = tgt.pos
			var to_tgt: Vector2 = tgt_vis - m.pos
			var d: float = to_tgt.length()
			var step_px: float = m.speed_px_sec * TICK_DT
			if d <= maxf(12.0, step_px):
				tgt.active = false
				m.active = false
				var sam_n: NationData = nations.get(m.nation_id, null)
				if sam_n != null:
					sam_n.nukes_intercepted += 1
				intercepts.append(tgt_vis)
				done_ids.append(mid)
				done_ids.append(tgt.id)
			else:
				m.pos += (to_tgt / d) * step_px
				m.altitude = lerpf(m.altitude, tgt.altitude, 0.25)
		else:
			var total_dist: float = maxf(m.start_pos.distance_to(m.target_pos), 12.0)
			m.progress = minf(1.0, m.progress + (m.speed_px_sec * TICK_DT) / total_dist)
			m.ground_pos = m.start_pos.lerp(m.target_pos, m.progress)
			m.pos = m.get_curve_point(m.progress)
			m.heading = m.get_curve_heading(m.progress)
			m.altitude = 0.0
			if m.kind == MissileUnit.KIND_MIRV and not m.has_split and m.progress >= 0.62:
				m.has_split = true
				m.active = false
				_split_mirv(m)
				done_ids.append(mid)
			elif m.progress >= 1.0:
				m.active = false
				detonations.append(m)
				done_ids.append(mid)

	for did: int in done_ids:
		missiles.erase(did)

	for pos_i: Vector2 in intercepts:
		missile_intercepted.emit(pos_i)

	for det: MissileUnit in detonations:
		_detonate_missile(det)


func _split_mirv(m: MissileUnit) -> void:
	var tgt_owner: int = m.target_nation_id if m.target_nation_id > 0 else get_owner_at(m.target_cell.x, m.target_cell.y)
	var en: NationData = nations.get(tgt_owner, null)
	var target_cells: Array[Vector2i] = []
	if en != null and en.alive and en.owned_cell_count > 0:
		var cands: Array[Vector2i] = []
		if get_owner_at(m.target_cell.x, m.target_cell.y) == tgt_owner:
			cands.append(m.target_cell)
		if en.capital_cell.x >= 0 and get_owner_at(en.capital_cell.x, en.capital_cell.y) == tgt_owner:
			cands.append(en.capital_cell)
		for sid: int in en.structure_ids:
			var st: StructureData = structures.get(sid, null)
			if st != null:
				cands.append(st.cell)
		var center: Vector2i = get_nation_label_cell(tgt_owner)
		var borders: Dictionary = _nation_borders.get(tgt_owner, {})
		var b_keys: Array = borders.keys()
		var stride: int = maxi(1, int(ceil(float(b_keys.size()) / 64.0)))
		var bi := 0
		while bi < b_keys.size():
			var b_idx: int = int(b_keys[bi])
			var bc := Vector2i(b_idx % sim_width, int(b_idx / sim_width))
			cands.append(bc)
			for frac: float in [0.25, 0.5, 0.75]:
				var ic := Vector2i(int(round(lerpf(float(bc.x), float(center.x), frac))), int(round(lerpf(float(bc.y), float(center.y), frac))))
				if get_owner_at(ic.x, ic.y) == tgt_owner:
					cands.append(ic)
			bi += stride
		var warhead_count: int = clampi(8 + int(en.owned_cell_count / 60), 10, 20)
		# Greedy farthest-point selection spreads mini warheads across the whole nation
		for c: Vector2i in cands:
			if get_owner_at(c.x, c.y) == tgt_owner and terrain_grid[c.y * sim_width + c.x] >= T_PLAINS:
				target_cells.append(c)
				break
		while target_cells.size() < warhead_count and not cands.is_empty():
			var best_c := Vector2i(-1, -1)
			var best_d := -1.0
			for c: Vector2i in cands:
				if get_owner_at(c.x, c.y) != tgt_owner:
					continue
				var min_d := 1e12
				for t: Vector2i in target_cells:
					min_d = minf(min_d, Vector2(c - t).length_squared())
				if min_d > best_d:
					best_d = min_d
					best_c = c
			if best_c.x < 0 or best_d < 16.0:
				break
			target_cells.append(best_c)
	if target_cells.is_empty():
		if get_owner_at(m.target_cell.x, m.target_cell.y) > 0:
			target_cells.append(m.target_cell)
		else:
			return

	for c: Vector2i in target_cells:
		var sub := MissileUnit.new()
		sub.id = _next_missile_id
		_next_missile_id += 1
		sub.kind = MissileUnit.KIND_MIRV_WARHEAD
		sub.nation_id = m.nation_id
		sub.source_structure_id = m.source_structure_id
		sub.start_pos = m.pos
		sub.pos = m.pos
		sub.ground_pos = m.ground_pos
		sub.target_cell = c
		sub.target_nation_id = tgt_owner
		sub.target_pos = sim_to_world(c)
		sub.speed_px_sec = MissileUnit.get_speed(MissileUnit.KIND_MIRV_WARHEAD)
		sub.blast_radius_sim = MissileUnit.get_blast_radius(MissileUnit.KIND_MIRV_WARHEAD)
		sub.compute_ballistic_curve(true)
		missiles[sub.id] = sub


func _detonate_missile(m: MissileUnit) -> void:
	var r: int = maxi(4, m.blast_radius_sim)
	var r2: int = r * r
	var struct_r2: float = float(r2)
	var cx: int = m.target_cell.x
	var cy: int = m.target_cell.y

	var destroyed_sids: Array[int] = []
	for sid: int in structures.keys():
		var st: StructureData = structures[sid]
		if Vector2(st.cell - m.target_cell).length_squared() <= struct_r2:
			destroyed_sids.append(sid)

	for sid: int in destroyed_sids:
		var st: StructureData = structures[sid]
		var st_n: NationData = nations.get(st.nation_id, null)
		if st_n != null:
			st_n.structure_ids.erase(sid)
		structures.erase(sid)
		_prune_road_cache(sid)
		for ti in range(trains.size() - 1, -1, -1):
			var tr: Dictionary = trains[ti]
			if int(tr.get("factory_id", 0)) == sid or int(tr.get("target_id", 0)) == sid:
				trains.remove_at(ti)
		_factory_links_dirty = true
		_economy_dirty = true
		structure_changed.emit(sid)

	# OpenFront 1:1 smoothed undulating blast ring (16 angular samples, 0.6/0.2/0.2 smoothing)
	var inner_r: float = float(r) * 0.80
	var inner_r2: float = inner_r * inner_r
	var outer_r2: float = float(r2)
	var num_samples := 16
	var raw_r2 := PackedFloat32Array()
	raw_r2.resize(num_samples)
	for s_i in range(num_samples):
		var h_s: int = ((m.id * 73856093) ^ (s_i * 19349663) ^ (cx * 83492791) ^ (cy * 297121507)) & 1023
		raw_r2[s_i] = lerpf(inner_r2, outer_r2, float(h_s) / 1023.0)
	var radii_sq := PackedFloat32Array()
	radii_sq.resize(num_samples)
	for s_i in range(num_samples):
		var l_i: int = (s_i - 1 + num_samples) % num_samples
		var r_i: int = (s_i + 1) % num_samples
		radii_sq[s_i] = raw_r2[s_i] * 0.6 + raw_r2[l_i] * 0.2 + raw_r2[r_i] * 0.2

	var hit_counts: Dictionary = {}
	for dy in range(-r, r + 1):
		var yy: int = cy + dy
		if yy < 0 or yy >= sim_height:
			continue
		for dx in range(-r, r + 1):
			var d2_i: int = dx * dx + dy * dy
			if d2_i > r2:
				continue
			var d2_f: float = float(d2_i)
			if d2_f > inner_r2:
				var ang: float = atan2(float(dy), float(dx)) + PI
				var t_ang: float = (ang / TAU) * float(num_samples)
				var i0: int = int(floor(t_ang)) % num_samples
				var i1: int = (i0 + 1) % num_samples
				var frac: float = t_ang - floor(t_ang)
				var thresh_r2: float = radii_sq[i0] * (1.0 - frac) + radii_sq[i1] * frac
				if d2_f > thresh_r2:
					continue
			var xx: int = cx + dx
			if xx < 0 or xx >= sim_width:
				continue
			var idx: int = yy * sim_width + xx
			if terrain_grid[idx] < T_PLAINS:
				continue
			var own: int = owner_grid[idx]
			if own != 0:
				hit_counts[own] = int(hit_counts.get(own, 0)) + 1
				_set_cell_owner(idx, 0)
			if fallout_grid[idx] == 0:
				fallout_grid[idx] = 1
				fallout_cell_count += 1
			render_owner_grid[idx] = 255

	# OpenFront 1:1 nukeDeathFactor across standing troops, active attacks, and transport boats
	for nid_v in hit_counts.keys():
		var vn: NationData = nations.get(int(nid_v), null)
		if vn != null:
			var impacted: int = int(hit_counts[nid_v])
			var tiles_before: int = maxi(1, vn.owned_cell_count + impacted)
			var loss_ratio: float = clampf((2.2 * float(impacted)) / float(tiles_before), 0.04, 0.72)
			vn.troops = maxf(0.0, vn.troops - maxf(float(impacted) * 0.4, vn.troops * loss_ratio))
			for eid_k: int in expansions.keys():
				var eo: ExpansionOrder = expansions[eid_k]
				if eo.nation_id == vn.id and eo.remaining_troops > 1.0:
					eo.remaining_troops = maxf(1.0, eo.remaining_troops * (1.0 - loss_ratio * 0.65))
			for sid_k: int in ships.keys():
				var sh_u: ShipUnit = ships[sid_k]
				if sh_u.active and sh_u.nation_id == vn.id and sh_u.kind == ShipUnit.KIND_LANDING and sh_u.troops_carried > 2.0:
					sh_u.troops_carried = maxf(2.0, sh_u.troops_carried * (1.0 - loss_ratio * 0.65))
			if not vn.alive and not vn.structure_ids.is_empty():
				for orphan_sid: int in vn.structure_ids.duplicate():
					structures.erase(orphan_sid)
				vn.structure_ids.clear()
				_factory_links_dirty = true

	_economy_dirty = true
	owner_dirty = true
	territory_changed.emit()
	missile_detonated.emit(m.target_pos, float(r) * sim_scale, m.kind)


func _cmd_request_alliance(cmd: Dictionary) -> Dictionary:
	if match_phase != PHASE_PLAYING:
		return _reject("Match is not active.")
	var nid: int = int(cmd.get("nation_id", 0))
	var tgt_id: int = int(cmd.get("target_nation_id", 0))
	var nation: NationData = nations.get(nid, null)
	var target: NationData = nations.get(tgt_id, null)
	if nation == null or target == null or not nation.alive or not target.alive or nid == tgt_id:
		return _reject("Select another living nation for diplomacy.")
	if are_allied(nid, tgt_id):
		return _reject("Already allied with %s." % target.name)
	if nation.is_betrayer(current_tick):
		return _reject("Betrayal penalty active — cannot form alliances yet.")

	if not target.is_player:
		var being_attacked := false
		for eid: int in expansions.keys():
			var o: ExpansionOrder = expansions[eid]
			if o.nation_id == nid and o.enemy_nation_id == tgt_id:
				being_attacked = true
				break
		if not target.is_betrayer(current_tick) and not being_attacked and target.alliances.size() < 2:
			_establish_alliance(nid, tgt_id)
			diplomacy_changed.emit()
			diplomacy_event.emit("Alliance formed with %s (5m)!" % target.name, false)
			return {"ok": true, "accepted": true}
		diplomacy_event.emit("%s declined your alliance proposal." % target.name, false)
		return {"ok": true, "accepted": false}

	target.incoming_alliances[nid] = current_tick + ALLIANCE_REQUEST_TTL_TICKS
	alliance_requested.emit(nid, tgt_id)
	diplomacy_event.emit("%s proposed an Alliance!" % nation.name, false)
	return {"ok": true, "pending": true}


func _cmd_respond_alliance(cmd: Dictionary) -> Dictionary:
	var nid: int = int(cmd.get("nation_id", 0))
	var from_id: int = int(cmd.get("from_nation_id", 0))
	var accept: bool = bool(cmd.get("accept", false))
	var nation: NationData = nations.get(nid, null)
	var from_n: NationData = nations.get(from_id, null)
	if nation == null or from_n == null:
		return _reject("Nation not found.")
	nation.incoming_alliances.erase(from_id)
	if not accept or not nation.alive or not from_n.alive:
		diplomacy_changed.emit()
		return {"ok": true, "accepted": false}
	if nation.is_betrayer(current_tick) or from_n.is_betrayer(current_tick):
		return _reject("Betrayer nations cannot enter alliances.")
	_establish_alliance(nid, from_id)
	diplomacy_changed.emit()
	diplomacy_event.emit("Alliance ratified with %s!" % from_n.name, false)
	return {"ok": true, "accepted": true}


func _establish_alliance(a_id: int, b_id: int) -> void:
	var na: NationData = nations.get(a_id, null)
	var nb: NationData = nations.get(b_id, null)
	if na == null or nb == null:
		return
	var expiry: int = current_tick + ALLIANCE_DURATION_TICKS
	na.alliances[b_id] = expiry
	nb.alliances[a_id] = expiry
	na.embargoes.erase(b_id)
	nb.embargoes.erase(a_id)
	na.incoming_alliances.erase(b_id)
	nb.incoming_alliances.erase(a_id)
	for eid: int in expansions.keys().duplicate():
		var o: ExpansionOrder = expansions[eid]
		if (o.nation_id == a_id and o.enemy_nation_id == b_id) or (o.nation_id == b_id and o.enemy_nation_id == a_id):
			var ow_n: NationData = nations.get(o.nation_id, null)
			if ow_n != null and ow_n.alive:
				ow_n.troops = minf(ow_n.max_troops, ow_n.troops + o.remaining_troops)
			expansions.erase(eid)
			expansion_updated.emit()


func _cmd_break_alliance(cmd: Dictionary) -> Dictionary:
	var nid: int = int(cmd.get("nation_id", 0))
	var tgt_id: int = int(cmd.get("target_nation_id", 0))
	var nation: NationData = nations.get(nid, null)
	var target: NationData = nations.get(tgt_id, null)
	if nation == null or target == null or not are_allied(nid, tgt_id):
		return _reject("No active alliance with this nation.")
	if nation.team_id > 0 and nation.team_id == target.team_id:
		return _reject("Cannot break permanent Team %d pact." % nation.team_id)
	nation.alliances.erase(tgt_id)
	target.alliances.erase(nid)
	nation.embargoes[tgt_id] = true
	target.embargoes[nid] = true
	nation.betrayal_until_tick = current_tick + BETRAYAL_DURATION_TICKS
	diplomacy_changed.emit()
	diplomacy_event.emit("BETRAYAL! %s broke alliance with %s (-35%% economy/troops)!" % [nation.name, target.name], true)
	return {"ok": true}


func _cmd_toggle_embargo(cmd: Dictionary) -> Dictionary:
	var nid: int = int(cmd.get("nation_id", 0))
	var tgt_id: int = int(cmd.get("target_nation_id", 0))
	var nation: NationData = nations.get(nid, null)
	var target: NationData = nations.get(tgt_id, null)
	if nation == null or target == null or nid == tgt_id:
		return _reject("Invalid embargo target.")
	if nation.embargoes.has(tgt_id):
		nation.embargoes.erase(tgt_id)
		diplomacy_event.emit("Trade embargo against %s lifted." % target.name, false)
	else:
		nation.embargoes[tgt_id] = true
		diplomacy_event.emit("Trade embargo placed on %s." % target.name, false)
	_factory_links_dirty = true
	diplomacy_changed.emit()
	return {"ok": true, "embargoed": nation.embargoes.has(tgt_id)}


func _cmd_donate_gold(cmd: Dictionary) -> Dictionary:
	var nid: int = int(cmd.get("nation_id", 0))
	var tgt_id: int = int(cmd.get("target_nation_id", 0))
	var amount: float = maxf(0.0, float(cmd.get("amount", 100000.0)))
	var nation: NationData = nations.get(nid, null)
	var target: NationData = nations.get(tgt_id, null)
	if nation == null or target == null or not are_allied(nid, tgt_id):
		return _reject("Peso aid requires an active Alliance (FFA pact or shared Team).")
	if amount < 1000.0 or nation.gold < amount:
		return _reject("Need %s Pesos to send aid." % StructureData.format_pesos(maxf(amount, 1000.0)))
	nation.gold -= amount
	target.gold += amount
	diplomacy_changed.emit()
	diplomacy_event.emit("%s sent %s Pesos aid to %s." % [nation.name, StructureData.format_pesos(amount), target.name], false)
	return {"ok": true, "amount": amount}


func _cmd_donate_troops(cmd: Dictionary) -> Dictionary:
	var nid: int = int(cmd.get("nation_id", 0))
	var tgt_id: int = int(cmd.get("target_nation_id", 0))
	var ratio: float = clampf(float(cmd.get("ratio", 0.25)), 0.10, 0.50)
	var nation: NationData = nations.get(nid, null)
	var target: NationData = nations.get(tgt_id, null)
	if nation == null or target == null or not are_allied(nid, tgt_id):
		return _reject("Troop aid requires an active Alliance (FFA pact or shared Team).")
	var send_amt: float = floor(nation.troops * ratio)
	if send_amt < 15.0:
		return _reject("Need at least 15 troops available to reinforce ally.")
	nation.troops -= send_amt
	target.troops = minf(target.max_troops, target.troops + send_amt)
	diplomacy_changed.emit()
	diplomacy_event.emit("%s sent %d troop aid to %s." % [nation.name, int(round(send_amt)), target.name], false)
	return {"ok": true, "troops_sent": send_amt}


func _step_diplomacy() -> void:
	if current_tick % 12 != 0:
		return
	var changed := false
	for nid: int in nations.keys():
		var n: NationData = nations[nid]
		for other_id in n.alliances.keys().duplicate():
			var other_n: NationData = nations.get(int(other_id), null)
			if other_n == null or not other_n.alive or int(n.alliances[other_id]) <= current_tick:
				n.alliances.erase(other_id)
				changed = true
		for from_id in n.incoming_alliances.keys().duplicate():
			if int(n.incoming_alliances[from_id]) <= current_tick:
				n.incoming_alliances.erase(from_id)
				changed = true
	if changed:
		diplomacy_changed.emit()


func _step_trains() -> void:
	# 1. Advance active trains along Factory -> Town/Port tracks & bridges
	for i in range(trains.size() - 1, -1, -1):
		var tr: Dictionary = trains[i]
		var fac_id: int = int(tr.get("factory_id", 0))
		var tgt_id: int = int(tr.get("target_id", 0))
		var fac: StructureData = structures.get(fac_id, null)
		var tgt: StructureData = structures.get(tgt_id, null)
		var nid: int = int(tr.get("nation_id", 0))
		var owner_n: NationData = nations.get(nid, null)
		var tgt_n: NationData = nations.get(tgt.nation_id, null) if tgt != null else null
		var link_allowed: bool = (
			fac != null and tgt != null
			and owner_n != null and owner_n.alive
			and tgt_n != null and tgt_n.alive
			and fac.nation_id == nid
			and (tgt.nation_id == nid or not is_embargoed(nid, tgt.nation_id))
		)
		if link_allowed:
			var hop_ids: Array = tr.get("hop_ids", [])
			for h_var in hop_ids:
				var h_st: StructureData = structures.get(int(h_var), null)
				var h_n: NationData = nations.get(h_st.nation_id, null) if h_st != null else null
				if h_st == null or h_n == null or not h_n.alive or (h_st.nation_id != nid and is_embargoed(nid, h_st.nation_id)):
					link_allowed = false
					break
		if not link_allowed:
			trains.remove_at(i)
			continue
		var p_a: Vector2 = tr["from_pos"]
		var p_b: Vector2 = tr["to_pos"]
		var r_pts: PackedVector2Array = tr.get("road_points", PackedVector2Array([p_a, p_b]))
		var dist: float = maxf(float(tr.get("road_length", p_a.distance_to(p_b))), 8.0)
		var prog: float = float(tr["progress"]) + (float(tr["speed"]) * TICK_DT) / dist
		if prog >= 1.0:
			if not bool(tr["returning"]):
				var payout: float = float(tr["gold"])
				owner_n.gold += payout
				structure_income_popup.emit(nid, p_b, payout, "train")
				if tgt.nation_id != nid and tgt_n != null and tgt_n.alive:
					tgt_n.gold += payout
					structure_income_popup.emit(tgt.nation_id, p_b, payout, "train")
				tr["returning"] = true
				tr["progress"] = 0.0
				var samp_ret: Dictionary = _sample_polyline(r_pts, 0.0, true, dist)
				tr["pos"] = samp_ret["pos"]
				tr["heading"] = samp_ret["heading"]
				_update_train_cars(tr, r_pts, 0.0, true, dist)
			else:
				trains.remove_at(i)
		else:
			tr["progress"] = prog
			var is_ret: bool = bool(tr["returning"])
			var samp: Dictionary = _sample_polyline(r_pts, prog, is_ret, dist)
			tr["pos"] = samp["pos"]
			tr["heading"] = samp["heading"]
			_update_train_cars(tr, r_pts, prog, is_ret, dist)

	# 2. Spawn new trains from completed Factories across ALL connected roads (1-hop & extended)
	if _factory_train_routes.is_empty():
		return
	var per_fac_count: Dictionary = {}
	for tr: Dictionary in trains:
		var fid: int = int(tr.get("factory_id", 0))
		per_fac_count[fid] = int(per_fac_count.get(fid, 0)) + 1

	for fid: int in _factory_train_routes.keys():
		var fac: StructureData = structures.get(fid, null)
		if fac == null or fac.is_constructing or fac.level <= 0 or fac.train_cooldown_ticks > 0:
			continue
		var routes: Array = _factory_train_routes[fid]
		if routes.is_empty():
			continue
		if int(per_fac_count.get(fid, 0)) >= mini(4, routes.size()):
			continue
		var cursor: int = int(_factory_route_cursor.get(fid, 0))
		var route: Dictionary = routes[cursor % routes.size()]
		_factory_route_cursor[fid] = cursor + 1
		var dest_id: int = int(route["target_id"])
		var r_pts: PackedVector2Array = route["road_points"]
		var r_len: float = float(route["road_length"])
		var hops: int = int(route["hops"])
		var crosses_w: bool = bool(route["crosses_water"])
		var from_w: Vector2 = r_pts[0]
		var to_w: Vector2 = r_pts[r_pts.size() - 1]
		var gold_amt: float = round((1800.0 + float(fac.level) * 1250.0) * (1.25 if crosses_w else 1.0) * (1.0 + 0.15 * float(mini(hops - 1, 4))))
		var samp0: Dictionary = _sample_polyline(r_pts, 0.0, false, r_len)
		var new_tr: Dictionary = {
			"id": _next_train_id,
			"nation_id": fac.nation_id,
			"factory_id": fid,
			"target_id": dest_id,
			"hop_ids": route["hop_ids"],
			"from_pos": from_w,
			"to_pos": to_w,
			"road_points": r_pts,
			"road_length": r_len,
			"pos": from_w,
			"heading": float(samp0["heading"]),
			"num_cars": 3,
			"car_positions": PackedVector2Array(),
			"car_headings": PackedFloat32Array(),
			"progress": 0.0,
			"returning": false,
			"speed": 38.0 + float(fac.level) * 2.0,
			"gold": gold_amt,
			"crosses_water": crosses_w,
		}
		_update_train_cars(new_tr, r_pts, 0.0, false, r_len)
		trains.append(new_tr)
		_next_train_id += 1
		per_fac_count[fid] = int(per_fac_count.get(fid, 0)) + 1
		fac.train_cooldown_ticks = 72


static func _update_train_cars(tr: Dictionary, r_pts: PackedVector2Array, prog: float, is_ret: bool, dist: float) -> void:
	var n_cars: int = int(tr.get("num_cars", 3))
	var step_frac: float = clampf(6.8 / maxf(dist, 12.0), 0.04, 0.22)
	var c_pos := PackedVector2Array()
	var c_hdg := PackedFloat32Array()
	c_pos.resize(n_cars)
	c_hdg.resize(n_cars)
	for c_i in range(n_cars):
		var c_f: float = maxf(0.0, prog - float(c_i + 1) * step_frac)
		var c_s: Dictionary = _sample_polyline(r_pts, c_f, is_ret, dist)
		c_pos[c_i] = c_s["pos"]
		c_hdg[c_i] = float(c_s["heading"])
	tr["car_positions"] = c_pos
	tr["car_headings"] = c_hdg


func compute_state_hash() -> int:
	var h: int = 2166136261
	h = ((h ^ (current_tick & 0x7FFFFFFF)) * 16777619) & 0x7FFFFFFF
	var sorted_ids: Array = nations.keys()
	sorted_ids.sort()
	for nid_v in sorted_ids:
		var n: NationData = nations[int(nid_v)]
		h = ((h ^ n.id) * 16777619) & 0x7FFFFFFF
		h = ((h ^ n.owned_cell_count) * 16777619) & 0x7FFFFFFF
		h = ((h ^ int(round(n.gold))) * 16777619) & 0x7FFFFFFF
		h = ((h ^ int(round(n.troops))) * 16777619) & 0x7FFFFFFF
		h = ((h ^ (1 if n.alive else 0)) * 16777619) & 0x7FFFFFFF
	h = ((h ^ structures.size()) * 16777619) & 0x7FFFFFFF
	h = ((h ^ ships.size()) * 16777619) & 0x7FFFFFFF
	h = ((h ^ missiles.size()) * 16777619) & 0x7FFFFFFF
	h = ((h ^ fallout_cell_count) * 16777619) & 0x7FFFFFFF
	return h
