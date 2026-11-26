class_name CapitalMarkersLayer
extends Node2D
## Layer 4 renderer: grounded nation-colored Banners (above growing names + standby troops),
## zoom-gated level labels, winding Factory roads, Bridges, and Peso popups.

const STRUCTURE_LEVEL_MIN_ZOOM := 1.65
const STRUCTURE_ICON_SIZE_PX := 18.0

var _tex_banner: Texture2D = preload("res://assets/sprites/icon_banner.png")
var _tex_banner_mask: Texture2D = preload("res://assets/sprites/icon_banner_mask.png")
var _tex_town: Texture2D = preload("res://assets/sprites/icon_town.png")
var _tex_town_mask: Texture2D = preload("res://assets/sprites/icon_town_mask.png")
var _tex_port: Texture2D = preload("res://assets/sprites/icon_port.png")
var _tex_port_mask: Texture2D = preload("res://assets/sprites/icon_port_mask.png")
var _tex_factory: Texture2D = preload("res://assets/sprites/icon_factory.png")
var _tex_factory_mask: Texture2D = preload("res://assets/sprites/icon_factory_mask.png")
var _tex_defense: Texture2D = preload("res://assets/sprites/icon_defense_post.png")
var _tex_defense_mask: Texture2D = preload("res://assets/sprites/icon_defense_post_mask.png")
var _tex_silo: Texture2D = preload("res://assets/sprites/icon_silo.png")
var _tex_silo_mask: Texture2D = preload("res://assets/sprites/icon_silo_mask.png")
var _tex_sam: Texture2D = preload("res://assets/sprites/icon_sam.png")
var _tex_sam_mask: Texture2D = preload("res://assets/sprites/icon_sam_mask.png")

var _world_state: WorldState
var _camera: Camera2D
var _popups: Array = []
var _upgrade_pulses: Dictionary = {}  # structure_id -> age
var _label_visual_pos: Dictionary = {}  # nation_id -> Vector2
var _label_visual_scale: Dictionary = {}  # nation_id -> float
var _nation_avatars: Dictionary = {}  # nation_id -> {"frames": Array, "delay_ms": int}
var _avatar_elapsed_ms: float = 0.0
var _last_avatar_tick: int = -1
var _dirty: bool = true
var _last_zoom: float = -1.0
var _troop_label_timer: float = 0.0


func set_nation_avatar(nation_id: int, frames: Array, delay_ms: int = 100) -> void:
	if nation_id <= 0 or frames.is_empty():
		_nation_avatars.erase(nation_id)
	else:
		_nation_avatars[nation_id] = {"frames": frames, "delay_ms": clampi(delay_ms, 40, 1000)}
	_dirty = true
	queue_redraw()


func clear_nation_avatars() -> void:
	_nation_avatars.clear()
	_dirty = true
	queue_redraw()


func setup(world_state: WorldState, camera: Camera2D) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_world_state = world_state
	_camera = camera
	_label_visual_pos.clear()
	_label_visual_scale.clear()
	if not _world_state.trade_completed.is_connected(_on_trade_completed):
		_world_state.trade_completed.connect(_on_trade_completed)
	if not _world_state.structure_income_popup.is_connected(_on_structure_income_popup):
		_world_state.structure_income_popup.connect(_on_structure_income_popup)
	if not _world_state.structure_upgraded.is_connected(_on_structure_upgraded):
		_world_state.structure_upgraded.connect(_on_structure_upgraded)
	if not _world_state.structure_changed.is_connected(_on_visual_dirty_arg):
		_world_state.structure_changed.connect(_on_visual_dirty_arg)
	if not _world_state.factory_link_created.is_connected(_on_visual_dirty_arg):
		_world_state.factory_link_created.connect(_on_visual_dirty_arg)
	if not _world_state.nation_spawned.is_connected(_on_visual_dirty_arg):
		_world_state.nation_spawned.connect(_on_visual_dirty_arg)
	if not _world_state.diplomacy_changed.is_connected(_on_visual_dirty_noarg):
		_world_state.diplomacy_changed.connect(_on_visual_dirty_noarg)
	if not _world_state.expansion_updated.is_connected(_on_visual_dirty_noarg):
		_world_state.expansion_updated.connect(_on_visual_dirty_noarg)
	if not _world_state.missile_detonated.is_connected(_on_visual_dirty_det):
		_world_state.missile_detonated.connect(_on_visual_dirty_det)
	_dirty = true
	queue_redraw()


func _on_visual_dirty_arg(_arg: Variant) -> void:
	_dirty = true


func _on_visual_dirty_det(_pos: Vector2, _rad: float, _kind: String) -> void:
	_dirty = true


func _on_visual_dirty_noarg() -> void:
	_dirty = true


func _on_trade_completed(nation_id: int, world_pos: Vector2, gold_amount: float) -> void:
	if _world_state != null and nation_id == _world_state.player_nation_id and gold_amount >= 1.0:
		_push_gold_popup(world_pos, gold_amount, Color(1.0, 0.90, 0.30))


func _on_structure_income_popup(nation_id: int, world_pos: Vector2, gold_amount: float, structure_type: String) -> void:
	if _world_state != null and nation_id == _world_state.player_nation_id and gold_amount >= 1.0:
		var col := Color(0.95, 0.96, 0.58)
		if structure_type == "train":
			col = Color(0.62, 0.96, 0.60)
		elif structure_type != StructureData.TYPE_TOWN:
			col = Color(1.0, 0.78, 0.34)
		_push_gold_popup(world_pos, gold_amount, col)


func _push_gold_popup(world_pos: Vector2, gold_amount: float, col: Color) -> void:
	if _popups.size() >= 40:
		_popups.remove_at(0)
	_popups.append({
		"pos": world_pos + Vector2(0.0, -11.0),
		"text": "+%s" % StructureData.format_pesos(gold_amount),
		"age": 0.0,
		"duration": 1.6,
		"color": col,
	})
	_dirty = true


func _on_structure_upgraded(sid: int, _new_level: int) -> void:
	_upgrade_pulses[sid] = 0.0
	_dirty = true


func _process(delta: float) -> void:
	if _world_state == null:
		return
	if not _nation_avatars.is_empty():
		_avatar_elapsed_ms += delta * 1000.0
		for nid_k: int in _nation_avatars.keys():
			var av_entry: Dictionary = _nation_avatars[nid_k]
			var frames_arr: Array = av_entry.get("frames", [])
			if frames_arr.size() > 1:
				var dms: int = maxi(40, int(av_entry.get("delay_ms", 100)))
				var frame_step: int = int(_avatar_elapsed_ms / float(dms))
				if frame_step != _last_avatar_tick:
					_last_avatar_tick = frame_step
					_dirty = true
				break
	var anim_active := (not _popups.is_empty()) or (not _upgrade_pulses.is_empty())
	for i in range(_popups.size() - 1, -1, -1):
		var p: Dictionary = _popups[i]
		p["age"] = float(p["age"]) + delta
		p["pos"] = (p["pos"] as Vector2) + Vector2(0.0, -13.0 * delta)
		if float(p["age"]) >= float(p["duration"]):
			_popups.remove_at(i)

	for sid: int in _upgrade_pulses.keys().duplicate():
		var age: float = float(_upgrade_pulses[sid]) + delta
		if age >= 0.65:
			_upgrade_pulses.erase(sid)
		else:
			_upgrade_pulses[sid] = age

	if not _dirty:
		for st: StructureData in _world_state.structures.values():
			if st.is_constructing or (st.type == StructureData.TYPE_MISSILE_SILO and st.action_cooldown_ticks > 0) or (st.type == StructureData.TYPE_SAM_LAUNCHER and st.sam_reload_ticks > 0):
				anim_active = true
				break

	var lerp_t: float = minf(1.0, delta * 6.0)
	for stale_id in _label_visual_pos.keys().duplicate():
		if not _world_state.nations.has(stale_id):
			_label_visual_pos.erase(stale_id)
			_label_visual_scale.erase(stale_id)
	for nid: int in _world_state.nations.keys():
		var nation: NationData = _world_state.nations[nid]
		if not nation.alive or nation.owned_cell_count <= 0:
			_label_visual_pos.erase(nid)
			_label_visual_scale.erase(nid)
			continue
		var tgt_pos: Vector2 = _world_state.sim_to_world(_world_state.get_nation_label_cell(nid))
		var tgt_sc: float = _world_state.get_nation_label_scale(nid)
		if not _label_visual_pos.has(nid):
			_label_visual_pos[nid] = tgt_pos
			_label_visual_scale[nid] = tgt_sc
		else:
			var cur_pos: Vector2 = _label_visual_pos[nid]
			var cur_sc: float = float(_label_visual_scale.get(nid, tgt_sc))
			if cur_pos.distance_to(tgt_pos) > 0.25:
				_label_visual_pos[nid] = cur_pos.lerp(tgt_pos, lerp_t)
				anim_active = true
			else:
				_label_visual_pos[nid] = tgt_pos
			if absf(cur_sc - tgt_sc) > 0.005:
				_label_visual_scale[nid] = lerpf(cur_sc, tgt_sc, lerp_t)
				anim_active = true
			else:
				_label_visual_scale[nid] = tgt_sc

	var z: float = _camera.zoom.x if _camera != null else 1.0
	if _world_state.match_phase == WorldState.PHASE_PLAYING:
		_troop_label_timer += delta
		if _troop_label_timer >= 0.25:
			_troop_label_timer = 0.0
			_dirty = true
	if _dirty or anim_active or absf(z - _last_zoom) > 1e-4:
		_last_zoom = z
		_dirty = false
		queue_redraw()


func _draw() -> void:
	if _world_state == null:
		return
	var z: float = _camera.zoom.x if _camera != null else 1.0
	var icon_scale: float = 1.0 / maxf(z, 1.0)
	var inv_z: float = icon_scale
	var font: Font = ThemeDB.fallback_font

	# 1. Draw subtle thin Factory roads on land and straight low-opacity pixel Bridges ONLY over water spans
	for link: Dictionary in _world_state.factory_links:
		var nation: NationData = _world_state.get_nation(int(link.get("nation_id", 0)))
		var col: Color = nation.color if nation != null else Color.WHITE
		var from_w: Vector2 = link["from_world"]
		var to_w: Vector2 = link["to_world"]
		var road_pts: PackedVector2Array = link.get("road_points", PackedVector2Array([from_w, to_w]))
		var water_spans: Array = link.get("water_spans", [])
		var road_dark := Color(0.08, 0.09, 0.11, 0.36)
		var road_light := Color(0.58, 0.55, 0.48, 0.54).lerp(col, 0.16)
		if water_spans.is_empty():
			if road_pts.size() >= 2:
				draw_polyline(road_pts, road_dark, 1.85 * inv_z, true)
				draw_polyline(road_pts, road_light, 1.0 * inv_z, true)
		elif road_pts.size() >= 2:
			for seg_i in range(road_pts.size() - 1):
				var pa: Vector2 = road_pts[seg_i]
				var pb: Vector2 = road_pts[seg_i + 1]
				var seg_is_water := false
				for sp: Array in water_spans:
					if sp.size() >= 2:
						var s0: Vector2 = sp[0]
						var s1: Vector2 = sp[1]
						if (pa.distance_squared_to(s0) < 0.25 and pb.distance_squared_to(s1) < 0.25) or (pa.distance_squared_to(s1) < 0.25 and pb.distance_squared_to(s0) < 0.25):
							seg_is_water = true
							break
				if seg_is_water:
					_draw_pixel_bridge(pa, pb, inv_z, col)
				else:
					draw_line(pa, pb, road_dark, 1.85 * inv_z, true)
					draw_line(pa, pb, road_light, 1.0 * inv_z, true)

	# 2. Draw dynamic territory-tracking national banner ON TOP of growing nation name & standby armies
	var zoom_comp: float = minf(1.0, 1.4 / maxf(z, 1.0))
	for nid: int in _world_state.nations.keys():
		var nation: NationData = _world_state.nations[nid]
		if not nation.alive or nation.owned_cell_count <= 0:
			continue
		if nation.capital_cell.x >= 0 and _world_state.get_owner_at(nation.capital_cell.x, nation.capital_cell.y) == nid:
			var cap_pos: Vector2 = _world_state.sim_to_world(nation.capital_cell)
			draw_circle(cap_pos, 2.0 * inv_z, Color(0.04, 0.06, 0.10, 0.85))
			draw_circle(cap_pos, 1.15 * inv_z, nation.color)

		var anchor_pos: Vector2 = _label_visual_pos.get(nid, _world_state.sim_to_world(_world_state.get_nation_label_cell(nid)))
		var vis_scale: float = float(_label_visual_scale.get(nid, _world_state.get_nation_label_scale(nid)))
		var eff: float = vis_scale * zoom_comp

		var tag_suffix := ""
		if nid != _world_state.player_nation_id and _world_state.are_allied(_world_state.player_nation_id, nid):
			tag_suffix = " [ALLY]"
		elif nation.is_betrayer(_world_state.current_tick):
			tag_suffix = " [BETRAYER]"
		var full_name: String = nation.name + tag_suffix
		var txt_sz: Vector2 = font.get_string_size(full_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var name_col := Color(0.56, 0.96, 0.88, 0.98) if tag_suffix == " [ALLY]" else (Color(1.0, 0.54, 0.50, 0.98) if tag_suffix == " [BETRAYER]" else Color(0.96, 0.98, 1.0, 0.96))
		draw_set_transform(anchor_pos + Vector2(0.0, 9.5 * eff), 0.0, Vector2(eff * 0.82, eff * 0.82))
		draw_string(font, Vector2(-txt_sz.x * 0.5 + 1.0, 1.0), full_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.03, 0.04, 0.07, 0.92))
		draw_string(font, Vector2(-txt_sz.x * 0.5, 0.0), full_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, name_col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		var troop_txt: String = _format_troops(nation.troops)
		var trp_sz: Vector2 = font.get_string_size(troop_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var trp_col := Color(0.86, 0.95, 1.0, 0.90) if nid == _world_state.player_nation_id else Color(0.95, 0.90, 0.72, 0.88)
		draw_set_transform(anchor_pos + Vector2(0.0, 19.5 * eff), 0.0, Vector2(eff * 0.68, eff * 0.68))
		draw_string(font, Vector2(-trp_sz.x * 0.5 + 1.0, 1.0), troop_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.02, 0.03, 0.06, 0.90))
		draw_string(font, Vector2(-trp_sz.x * 0.5, 0.0), troop_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, trp_col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		var b_sz: float = 12.0 * eff
		var banner_center: Vector2 = anchor_pos + Vector2(0.0, -7.0 * eff)
		if _nation_avatars.has(nid):
			var av_d: Dictionary = _nation_avatars[nid]
			var av_frames: Array = av_d.get("frames", [])
			if not av_frames.is_empty():
				var pfp_sz: float = 14.0 * eff
				var dms: float = maxf(40.0, float(av_d.get("delay_ms", 100)))
				var f_idx: int = int(_avatar_elapsed_ms / dms) % av_frames.size()
				var pfp_tex: Texture2D = av_frames[f_idx] as Texture2D
				var pfp_rect := Rect2(banner_center - Vector2(pfp_sz * 0.5, pfp_sz * 0.5), Vector2(pfp_sz, pfp_sz))
				draw_rect(pfp_rect.grow(1.4 * eff), Color(0.03, 0.05, 0.08, 0.92), true)
				if pfp_tex != null:
					draw_texture_rect(pfp_tex, pfp_rect, false, Color.WHITE)
				draw_rect(pfp_rect.grow(0.7 * eff), nation.color.lightened(0.22), false, 1.35 * eff)
				continue
		var banner_rect := Rect2(banner_center - Vector2(b_sz * 0.5, b_sz * 0.5), Vector2(b_sz, b_sz))
		draw_texture_rect(_tex_banner, banner_rect, false, Color(1.0, 1.0, 1.0, 0.96))
		draw_texture_rect(_tex_banner_mask, banner_rect, false, nation.color.lightened(0.22))

	# 3. Draw all 6 minimalist structure types + team-colored mask sprites (no zoom-out enlargement; hide L# when zoomed out)
	for sid: int in _world_state.structures.keys():
		var st: StructureData = _world_state.structures[sid]
		var nation: NationData = _world_state.get_nation(st.nation_id)
		var col: Color = nation.color if nation != null else Color.WHITE
		var pos: Vector2 = st.get_world_pos()
		var sz: float = STRUCTURE_ICON_SIZE_PX * icon_scale
		var tex: Texture2D = _tex_town
		var mask_tex: Texture2D = _tex_town_mask
		match st.type:
			StructureData.TYPE_PORT:
				tex = _tex_port
				mask_tex = _tex_port_mask
			StructureData.TYPE_FACTORY:
				tex = _tex_factory
				mask_tex = _tex_factory_mask
			StructureData.TYPE_DEFENSE_POST:
				tex = _tex_defense
				mask_tex = _tex_defense_mask
			StructureData.TYPE_MISSILE_SILO:
				tex = _tex_silo
				mask_tex = _tex_silo_mask
			StructureData.TYPE_SAM_LAUNCHER:
				tex = _tex_sam
				mask_tex = _tex_sam_mask

		# Soft elliptical terrain contact shadow (no hard opaque sticker disc)
		draw_set_transform(pos + Vector2(0.0, sz * 0.34), 0.0, Vector2(1.0, 0.40))
		draw_circle(Vector2.ZERO, sz * 0.48, Color(0.03, 0.05, 0.07, 0.30))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		var st_rect := Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
		draw_texture_rect(tex, st_rect, false, Color(1.0, 1.0, 1.0, 0.96))
		draw_texture_rect(mask_tex, st_rect, false, col.lightened(0.18))

		if st.is_constructing:
			var prog: float = st.get_progress_ratio()
			draw_arc(pos, sz * 0.65, -PI * 0.5, -PI * 0.5 + TAU * prog, 24, Color(1.0, 0.90, 0.35, 0.95), 1.8 * inv_z)

		if st.type == StructureData.TYPE_MISSILE_SILO and not st.is_constructing and st.action_cooldown_ticks > 0:
			var cd_ratio: float = clampf(1.0 - float(st.action_cooldown_ticks) / float(maxi(st.get_silo_cooldown_ticks(), 1)), 0.0, 1.0)
			draw_arc(pos, sz * 0.62, -PI * 0.5, -PI * 0.5 + TAU * cd_ratio, 24, Color(1.0, 0.46, 0.22, 0.92), 1.6 * inv_z)
		elif st.type == StructureData.TYPE_SAM_LAUNCHER and not st.is_constructing and st.sam_reload_ticks > 0:
			var sam_cd_ratio: float = clampf(1.0 - float(st.sam_reload_ticks) / float(maxi(st.get_sam_cooldown_ticks(), 1)), 0.0, 1.0)
			var sam_col := Color(0.32, 0.94, 1.0, 0.92) if st.sam_ammo > 0 else Color(1.0, 0.48, 0.24, 0.92)
			draw_arc(pos, sz * 0.62, -PI * 0.5, -PI * 0.5 + TAU * sam_cd_ratio, 24, sam_col, 1.6 * inv_z)

		if _upgrade_pulses.has(sid):
			var t: float = float(_upgrade_pulses[sid]) / 0.65
			draw_arc(pos, (sz * 0.65) + t * (12.0 * inv_z), 0.0, TAU, 24, Color(1.0, 0.90, 0.36, 1.0 - t), 2.0 * inv_z)

		if z >= STRUCTURE_LEVEL_MIN_ZOOM:
			var lvl_txt := "L%d" % st.level if st.level > 0 else ".."
			draw_set_transform(pos + Vector2(-14.0 * icon_scale, -sz * 0.5 - 2.0 * icon_scale), 0.0, Vector2(icon_scale * 0.72, icon_scale * 0.72))
			draw_string(font, Vector2(1, 1), lvl_txt, HORIZONTAL_ALIGNMENT_CENTER, 38, 11, Color(0.02, 0.03, 0.05, 0.92))
			draw_string(font, Vector2.ZERO, lvl_txt, HORIZONTAL_ALIGNMENT_CENTER, 38, 11, Color(0.98, 0.95, 0.80, 0.98))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Draw floating gold popups on top of Ports, Towns, and Factories
	for p: Dictionary in _popups:
		var t: float = clampf(1.0 - float(p["age"]) / float(p["duration"]), 0.0, 1.0)
		var p_pos: Vector2 = p["pos"]
		var base_c: Color = p.get("color", Color(1.0, 0.88, 0.32))
		var p_txt: String = str(p["text"])
		draw_set_transform(p_pos + Vector2(-18.0 * inv_z, 0.0), 0.0, Vector2(inv_z * 0.85, inv_z * 0.85))
		draw_string(font, Vector2(1.0, 1.0), p_txt, HORIZONTAL_ALIGNMENT_CENTER, 44, 12, Color(0.02, 0.03, 0.05, 0.90 * t))
		draw_string(font, Vector2.ZERO, p_txt, HORIZONTAL_ALIGNMENT_CENTER, 44, 12, Color(base_c.r, base_c.g, base_c.b, t))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pixel_bridge(a: Vector2, b: Vector2, inv_z: float, col: Color = Color.WHITE) -> void:
	var dir: Vector2 = (b - a)
	var dist: float = dir.length()
	if dist < 1.0:
		return
	var u: Vector2 = dir / dist
	var perp := Vector2(-u.y, u.x)

	# Straight, low-opacity road-style causeway bridge (not overly bright or thick)
	draw_line(a, b, Color(0.08, 0.10, 0.14, 0.34), 2.0 * inv_z)
	draw_line(a, b, Color(0.62, 0.58, 0.50, 0.48).lerp(col, 0.14), 1.05 * inv_z)

	var step_px: float = maxf(6.0 * inv_z, 4.0)
	var count: int = int(floor(dist / step_px))
	for i in range(1, count):
		var pt: Vector2 = a + u * minf(float(i) * step_px, dist)
		draw_line(pt - perp * (1.4 * inv_z), pt + perp * (1.4 * inv_z), Color(0.24, 0.28, 0.34, 0.28), 0.75 * inv_z)


static func _format_troops(amount: float) -> String:
	var n: int = int(round(maxf(0.0, amount)))
	if n >= 1000:
		return "%.1fk" % (float(n) / 1000.0)
	return "%d" % n
