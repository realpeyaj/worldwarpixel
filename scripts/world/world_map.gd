class_name WorldMap
extends Node2D
## Coordinates all 7 rendering layers, GPU owner_tex sync, cursor queries, and camera input.

signal cell_hovered(cell: Vector2i)
signal spawn_requested(cell: Vector2i)
signal expand_requested(cell: Vector2i)
signal build_requested(structure_type: String, cell: Vector2i)
signal structure_selected(structure_id: int)
signal build_mode_cleared
signal warship_selected(ship_id: int)
signal warship_move_requested(ship_id: int, cell: Vector2i)
signal missile_target_staged(kind: String, cell: Vector2i)
signal missile_launch_requested(kind: String, cell: Vector2i)
signal missile_mode_cleared
signal map_ping_requested(cell: Vector2i, kind: String)
signal context_menu_requested(screen_pos: Vector2, world_pos: Vector2, cell: Vector2i)

const LUT_WIDTH := 256
const TERRAIN_TEX_PATH := "res://assets/map/world_terrain.png"

@onready var layer1_terrain: Sprite2D = $Layer1_BaseTerrain
@onready var layer2_boundaries: Sprite2D = $Layer2_ProvinceBoundaries
@onready var layer3_political: Sprite2D = $Layer3_PoliticalOwnership
@onready var layer4_cities: CapitalMarkersLayer = $Layer4_CitiesAndInfrastructure
@onready var layer5_units: UnitsLayer = $Layer5_Units
@onready var layer6_selection: SelectionOverlayLayer = $Layer6_SelectionOverlay
@onready var layer7_decor: EnvironmentDecor = $Layer7_EnvironmentDecor
@onready var camera: WorldCamera = $WorldCamera

var _world_state: WorldState
var _owner_image: Image
var _owner_texture: ImageTexture
var _lut_image: Image
var _lut_texture: ImageTexture

var _political_mode: bool = true
var _build_mode: String = ""
var _missile_mode: String = ""
var _selected_structure_id: int = 0
var _selected_ship_id: int = 0
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _staged_missile_cell: Vector2i = Vector2i(-1, -1)
var _staged_missile_ms: int = 0
var _owner_sync_accum: float = 0.033


func _ready() -> void:
	_setup_textures_and_shaders()


func _setup_textures_and_shaders() -> void:
	var terrain_tex: Texture2D = load(TERRAIN_TEX_PATH)
	layer1_terrain.texture = terrain_tex

	_owner_image = Image.create(2048, 1024, false, Image.FORMAT_R8)
	_owner_image.fill(Color(0, 0, 0, 1))
	_owner_texture = ImageTexture.create_from_image(_owner_image)

	_lut_image = Image.create(LUT_WIDTH, 1, false, Image.FORMAT_RGBA8)
	_lut_image.fill(Color(0, 0, 0, 0))
	_lut_texture = ImageTexture.create_from_image(_lut_image)

	layer2_boundaries.texture = _owner_texture
	layer2_boundaries.scale = Vector2.ONE
	layer3_political.texture = _owner_texture
	layer3_political.scale = Vector2.ONE

	if layer2_boundaries.material is ShaderMaterial:
		var mat2 := layer2_boundaries.material as ShaderMaterial
		mat2.set_shader_parameter("owner_tex", _owner_texture)
		mat2.set_shader_parameter("nation_lut", _lut_texture)

	if layer3_political.material is ShaderMaterial:
		var mat3 := layer3_political.material as ShaderMaterial
		mat3.set_shader_parameter("owner_tex", _owner_texture)
		mat3.set_shader_parameter("nation_lut", _lut_texture)


func bind_world_state(world_state: WorldState) -> void:
	_world_state = world_state
	var sim_sz := Vector2(float(_world_state.sim_width), float(_world_state.sim_height))
	var sc := Vector2(_world_state.sim_scale, _world_state.sim_scale)
	layer2_boundaries.scale = sc
	layer3_political.scale = sc
	if layer2_boundaries.material is ShaderMaterial:
		(layer2_boundaries.material as ShaderMaterial).set_shader_parameter("sim_size", sim_sz)
	if layer3_political.material is ShaderMaterial:
		(layer3_political.material as ShaderMaterial).set_shader_parameter("sim_size", sim_sz)
	if not _world_state.nation_spawned.is_connected(_on_nation_spawned):
		_world_state.nation_spawned.connect(_on_nation_spawned)
	if not _world_state.structure_changed.is_connected(_on_structure_changed):
		_world_state.structure_changed.connect(_on_structure_changed)
	_refresh_lut()
	sync_owner_texture()
	_world_state.owner_dirty = false
	layer4_cities.setup(_world_state, camera)
	layer5_units.setup(_world_state, camera)
	layer6_selection.setup(_world_state, camera)


func _process(delta: float) -> void:
	if _world_state != null and _world_state.owner_dirty:
		_owner_sync_accum += delta
		if _owner_sync_accum >= 0.033:
			_owner_sync_accum = 0.0
			_world_state.owner_dirty = false
			sync_owner_texture()
	else:
		_owner_sync_accum = 0.033


func _unhandled_input(event: InputEvent) -> void:
	if _world_state == null or camera.auto_pan_enabled:
		return

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_ESCAPE:
			if _missile_mode != "":
				set_missile_mode("")
				missile_mode_cleared.emit()
			elif _build_mode != "":
				set_build_mode("")
				build_mode_cleared.emit()
			elif _selected_ship_id > 0:
				set_selected_ship(0)
			else:
				set_selected_structure(0)
			get_viewport().set_input_as_handled()
			return

	var consumed_by_cam: bool = camera.handle_map_input(event)
	if consumed_by_cam:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if get_viewport().gui_get_hovered_control() != null:
			_update_hover_cell(Vector2i(-1, -1))
			return
		var world_pos: Vector2 = get_global_mouse_position()
		if world_pos.x < 0.0 or world_pos.y < 0.0 or world_pos.x >= _world_state.map_size.x or world_pos.y >= _world_state.map_size.y:
			_update_hover_cell(Vector2i(-1, -1))
			return
		_update_hover_cell(_world_state.world_to_sim(world_pos))

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.alt_pressed and not mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			if get_viewport().gui_get_hovered_control() == null and _world_state.match_phase == WorldState.PHASE_PLAYING:
				var p_world: Vector2 = get_global_mouse_position()
				if p_world.x >= 0.0 and p_world.y >= 0.0 and p_world.x < _world_state.map_size.x and p_world.y < _world_state.map_size.y:
					var p_kind := "attack" if mb.button_index == MOUSE_BUTTON_LEFT else "defend"
					map_ping_requested.emit(_world_state.world_to_sim(p_world), p_kind)
					get_viewport().set_input_as_handled()
					return
		if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			if _missile_mode != "":
				set_missile_mode("")
				missile_mode_cleared.emit()
				get_viewport().set_input_as_handled()
				return
			if _build_mode != "":
				set_build_mode("")
				build_mode_cleared.emit()
				get_viewport().set_input_as_handled()
				return
			if _selected_ship_id > 0:
				set_selected_ship(0)
				get_viewport().set_input_as_handled()
				return
			if get_viewport().gui_get_hovered_control() == null and _world_state.match_phase == WorldState.PHASE_PLAYING:
				var w_pos: Vector2 = get_global_mouse_position()
				if w_pos.x >= 0.0 and w_pos.y >= 0.0 and w_pos.x < _world_state.map_size.x and w_pos.y < _world_state.map_size.y:
					context_menu_requested.emit(mb.position, w_pos, _world_state.world_to_sim(w_pos))
					get_viewport().set_input_as_handled()
					return

		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if get_viewport().gui_get_hovered_control() != null:
				return
			var world_pos: Vector2 = get_global_mouse_position()
			if world_pos.x < 0.0 or world_pos.y < 0.0 or world_pos.x >= _world_state.map_size.x or world_pos.y >= _world_state.map_size.y:
				return
			_handle_map_click(world_pos, _world_state.world_to_sim(world_pos), mb.double_click)


func _handle_map_click(world_pos: Vector2, cell: Vector2i, is_double_click: bool = false) -> void:
	if _world_state.match_phase == WorldState.PHASE_SPAWN_SELECT:
		spawn_requested.emit(cell)
		return
	if _world_state.match_phase != WorldState.PHASE_PLAYING:
		return

	if _missile_mode != "":
		if _world_state.get_owner_at(cell.x, cell.y) == _world_state.player_nation_id:
			_world_state.command_rejected.emit("Cannot launch warheads onto your own territory.")
			return
		var now_ms: int = Time.get_ticks_msec()
		var confirmed: bool = is_double_click or (
			_staged_missile_cell.x >= 0
			and Vector2(_staged_missile_cell - cell).length() <= 14.0
			and (now_ms - _staged_missile_ms) <= 6000
		)
		if confirmed:
			var kind_to_fire: String = _missile_mode
			var launch_cell: Vector2i = _staged_missile_cell if _staged_missile_cell.x >= 0 else cell
			set_missile_mode("")
			missile_mode_cleared.emit()
			missile_launch_requested.emit(kind_to_fire, launch_cell)
		else:
			_staged_missile_cell = cell
			_staged_missile_ms = now_ms
			layer6_selection.set_staged_missile_cell(cell)
			missile_target_staged.emit(_missile_mode, cell)
		return

	if _build_mode != "":
		if _build_mode == "warship":
			build_requested.emit("warship", cell)
			if not Input.is_key_pressed(KEY_SHIFT):
				set_build_mode("")
				build_mode_cleared.emit()
			return
		build_requested.emit(_build_mode, cell)
		if not Input.is_key_pressed(KEY_SHIFT):
			set_build_mode("")
			build_mode_cleared.emit()
		return

	var pick_r: float = 12.0 / maxf(camera.zoom.x, 0.5)
	if _selected_ship_id > 0 and _world_state.get_terrain_at(cell.x, cell.y) == WorldState.T_OCEAN:
		var sel_sh: ShipUnit = _world_state.ships.get(_selected_ship_id, null)
		if sel_sh != null and sel_sh.active and sel_sh.kind == ShipUnit.KIND_WARSHIP:
			var other_ship: ShipUnit = _world_state.find_warship_near(world_pos, pick_r, _world_state.player_nation_id)
			if other_ship != null and other_ship.id != _selected_ship_id:
				set_selected_ship(other_ship.id)
				return
			warship_move_requested.emit(_selected_ship_id, cell)
			return

	var hit_ship: ShipUnit = _world_state.find_warship_near(world_pos, pick_r, _world_state.player_nation_id)
	if hit_ship != null:
		set_selected_structure(0)
		set_selected_ship(hit_ship.id)
		return

	var hit_struct: StructureData = _world_state.find_structure_near(world_pos, pick_r)
	if hit_struct != null:
		set_selected_ship(0)
		set_selected_structure(hit_struct.id)
		return

	set_selected_ship(0)
	set_selected_structure(0)
	expand_requested.emit(cell)


func _update_hover_cell(cell: Vector2i) -> void:
	if _hover_cell == cell:
		return
	_hover_cell = cell
	layer6_selection.set_hover_cell(cell)
	cell_hovered.emit(cell)


func set_build_mode(mode: String) -> void:
	_build_mode = mode
	if mode != "" and _missile_mode != "":
		set_missile_mode("")
		missile_mode_cleared.emit()
	layer6_selection.set_build_mode(mode)


func set_missile_mode(kind: String) -> void:
	_missile_mode = kind
	_staged_missile_cell = Vector2i(-1, -1)
	_staged_missile_ms = 0
	if kind != "" and _build_mode != "":
		set_build_mode("")
		build_mode_cleared.emit()
	layer6_selection.set_staged_missile_cell(Vector2i(-1, -1))
	layer6_selection.set_missile_mode(kind)


func set_selected_ship(sid: int) -> void:
	if _selected_ship_id == sid:
		return
	_selected_ship_id = sid
	layer6_selection.set_selected_ship(sid)
	layer5_units.set_selected_ship(sid)
	warship_selected.emit(sid)


func set_selected_structure(sid: int) -> void:
	if _selected_structure_id == sid:
		return
	_selected_structure_id = sid
	layer6_selection.set_selected_structure(sid)
	structure_selected.emit(sid)


func set_political_mode(enabled: bool) -> void:
	_political_mode = enabled
	if layer3_political.material is ShaderMaterial:
		(layer3_political.material as ShaderMaterial).set_shader_parameter(
			"political_opacity", 0.42 if _political_mode else 0.12
		)


func reset_camera_view() -> void:
	camera.reset_view()


func focus_world_pos(world_pos: Vector2, min_zoom: float = -1.0) -> void:
	camera.focus_world_pos(world_pos, min_zoom)


func save_camera_bookmark(slot: int) -> void:
	camera.save_bookmark(slot)


func jump_camera_bookmark(slot: int) -> bool:
	return camera.jump_bookmark(slot)


func add_map_ping(cell: Vector2i, kind: String, sender: String = "") -> void:
	layer6_selection.add_map_ping(cell, kind, sender)


func set_home_pan_active(active: bool, preserve_view: bool = false) -> void:
	camera.set_auto_pan(active, preserve_view)


func _on_nation_spawned(_nid: int) -> void:
	_refresh_lut()


func _on_structure_changed(sid: int) -> void:
	if _selected_structure_id > 0 and sid == _selected_structure_id and _world_state != null and _world_state.get_structure(sid) == null:
		set_selected_structure(0)


func _refresh_lut() -> void:
	if _world_state == null:
		return
	_lut_image.fill(Color(0, 0, 0, 0))
	for nid: int in _world_state.nations.keys():
		if nid <= 0 or nid >= 255:
			continue
		var n: NationData = _world_state.nations[nid]
		_lut_image.set_pixel(nid, 0, Color(n.color.r, n.color.g, n.color.b, 1.0))
	_lut_texture.update(_lut_image)


func sync_owner_texture() -> void:
	if _world_state == null or _world_state.owner_grid.is_empty():
		return
	var tex_bytes: PackedByteArray = _world_state.render_owner_grid if not _world_state.render_owner_grid.is_empty() else _world_state.owner_grid
	_owner_image.set_data(
		_world_state.sim_width,
		_world_state.sim_height,
		false,
		Image.FORMAT_R8,
		tex_bytes
	)
	_owner_texture.update(_owner_image)
