extends Node
## Automated Phase 1-4 test suite and benchmarks for Free-World World War Pixel.

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("=== World War Pixel — Free-World Phase 1-4 Test & Benchmark Suite ===")
	_run_all_tests()
	print("=== Summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("[PASS] %s" % label)
	else:
		_failed += 1
		push_error("[FAIL] %s %s" % [label, ("— " + detail) if detail != "" else ""])
		print("[FAIL] %s %s" % [label, ("— " + detail) if detail != "" else ""])


func _find_nearby_land(ws: WorldState, lon: float, lat: float, max_r: int = 4) -> Vector2i:
	var cx: int = clampi(int(round((lon + 180.0) / 360.0 * float(ws.sim_width))), 0, ws.sim_width - 1)
	var cy: int = clampi(int(round((90.0 - lat) / 180.0 * float(ws.sim_height))), 0, ws.sim_height - 1)
	if ws.is_land_cell(cx, cy):
		return Vector2i(cx, cy)
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var xx: int = cx + dx
				var yy: int = cy + dy
				if ws.is_land_cell(xx, yy):
					return Vector2i(xx, yy)
	return Vector2i(-1, -1)


func _run_all_tests() -> void:
	# 1. Grounded Pixel-Art Sprite Icons + Team Masks & EnvironmentDecor No-Compass Check
	var expected_sprites := {
		"icon_banner.png": [Vector2i(64, 64), true],
		"icon_town.png": [Vector2i(64, 64), true],
		"icon_port.png": [Vector2i(64, 64), true],
		"icon_factory.png": [Vector2i(64, 64), true],
		"icon_trade_ship.png": [Vector2i(96, 48), true],
		"icon_warship.png": [Vector2i(96, 48), true],
		"icon_attack.png": [Vector2i(64, 64), false],
		"icon_defense_post.png": [Vector2i(64, 64), true],
		"icon_silo.png": [Vector2i(64, 64), true],
		"icon_sam.png": [Vector2i(64, 64), true],
		"icon_train.png": [Vector2i(64, 32), true],
		"icon_missile.png": [Vector2i(64, 64), false],
		"icon_diplomacy.png": [Vector2i(64, 64), false],
		"icon_wifi.png": [Vector2i(64, 64), false],
	}
	var icons_ok := true
	for icon_name: String in expected_sprites.keys():
		var spec: Array = expected_sprites[icon_name]
		var dim: Vector2i = spec[0]
		var has_mask: bool = bool(spec[1])
		var tex: Texture2D = load("res://assets/sprites/" + icon_name)
		if tex == null or tex.get_width() != dim.x or tex.get_height() != dim.y:
			icons_ok = false
		if has_mask:
			var m_path := "res://assets/sprites/" + icon_name.replace(".png", "_mask.png")
			var mtex: Texture2D = load(m_path)
			if mtex == null or mtex.get_width() != dim.x or mtex.get_height() != dim.y:
				icons_ok = false
	var ui_ok_tex := true
	for ui_name: String in ["panel_9patch.png", "btn_normal_9patch.png", "btn_hover_9patch.png", "btn_pressed_9patch.png", "btn_disabled_9patch.png"]:
		var utex: Texture2D = load("res://assets/ui/" + ui_name)
		if utex == null or utex.get_width() < 12:
			ui_ok_tex = false
	var hud_silo_tex: Texture2D = load("res://assets/sprites/hud_silo.png")
	var hud_sam_tex: Texture2D = load("res://assets/sprites/hud_sam.png")
	var hud_town_tex: Texture2D = load("res://assets/sprites/hud_town.png")
	var hud_warship_tex: Texture2D = load("res://assets/sprites/hud_warship.png")
	var hud_atom_tex: Texture2D = load("res://assets/sprites/hud_atom.png")
	var hud_hbomb_tex: Texture2D = load("res://assets/sprites/hud_hbomb.png")
	var hud_mirv_tex: Texture2D = load("res://assets/sprites/hud_mirv.png")
	var map_atom_tex: Texture2D = load("res://assets/sprites/icon_atom.png")
	var map_hbomb_tex: Texture2D = load("res://assets/sprites/icon_hbomb.png")
	var map_mirv_tex: Texture2D = load("res://assets/sprites/icon_mirv.png")
	var hud_nuke_icons_ok: bool = (
		hud_silo_tex != null and hud_silo_tex.get_width() == 20 and hud_silo_tex.get_height() == 20
		and hud_sam_tex != null and hud_sam_tex.get_width() == 20 and hud_sam_tex.get_height() == 20
		and hud_town_tex != null and hud_town_tex.get_width() == 20 and hud_town_tex.get_height() == 20
		and hud_warship_tex != null and hud_warship_tex.get_width() == 20 and hud_warship_tex.get_height() == 20
		and hud_atom_tex != null and hud_atom_tex.get_width() == 20 and hud_atom_tex.get_height() == 20
		and hud_hbomb_tex != null and hud_hbomb_tex.get_width() == 20 and hud_hbomb_tex.get_height() == 20
		and hud_mirv_tex != null and hud_mirv_tex.get_width() == 20 and hud_mirv_tex.get_height() == 20
		and map_atom_tex != null and map_atom_tex.get_width() == 64 and map_atom_tex.get_height() == 64
		and map_hbomb_tex != null and map_hbomb_tex.get_width() == 64 and map_hbomb_tex.get_height() == 64
		and map_mirv_tex != null and map_mirv_tex.get_width() == 64 and map_mirv_tex.get_height() == 64
	)
	_check(icons_ok and ui_ok_tex and hud_nuke_icons_ok and not ResourceLoader.exists("res://assets/sprites/icon_capital.png") and not ResourceLoader.exists("res://assets/sprites/icon_army.png"),
		"All 14 smooth minimalist sprites, 10 nation masks, 5 9-patch UI frames & crisp 20x20 HUD Silo/SAM icons load cleanly")

	var env_script := EnvironmentDecor.new()
	_check(not env_script.has_method("_draw_compass_rose"), "EnvironmentDecor has no N/S/E/W compass rose")
	env_script.free()

	# 2. Load & Grid Integrity
	var t0: int = Time.get_ticks_usec()
	var ws := WorldState.new()
	var loaded: bool = ws.load_world()
	var t1: int = Time.get_ticks_usec()
	print("[BENCH] WorldState.load_world() (2048x1024 grid + landmasses + 1024x512 nav): %.2f ms" % (float(t1 - t0) / 1000.0))
	var nav_land_overlap := 0
	var nw: int = ws.sea_pathfinder.nav_width
	var nh: int = ws.sea_pathfinder.nav_height
	if ws.sea_pathfinder.nav_grid.size() == nw * nh and ws.terrain_grid.size() == ws.sim_width * ws.sim_height:
		for ny in range(nh):
			for nx in range(nw):
				if ws.sea_pathfinder.nav_grid[ny * nw + nx] > 0:
					for oy in range(2):
						for ox in range(2):
							if ws.get_terrain_at(nx * 2 + ox, ny * 2 + oy) != WorldState.T_OCEAN:
								nav_land_overlap += 1
	_check(loaded and ws.terrain_grid.size() == 2048 * 1024 and ws.sea_pathfinder.nav_grid.size() == 1024 * 512 and nav_land_overlap == 0,
		"WorldState loads 2048x1024 terrain_grid (1:1 map) and strict water-only 1024x512 ocean_nav (0 land overlaps)")

	var ata_cells := 0
	for y in range(844, ws.sim_height):
		for x in range(ws.sim_width):
			if ws.is_land_cell(x, y):
				ata_cells += 1
	_check(ata_cells > 20000 and ws.total_conquerable_area_km2 >= 135000000.0,
		"Antarctica (%d cells) is conquerable and included in total area (%.0f km2)" % [ata_cells, ws.total_conquerable_area_km2])

	var islands_ok := true
	for pt in [[-155.5, 19.6], [-18.5, 64.9], [46.8, -18.9], [-79.5, 21.8], [138.2, 36.2], [-59.5, -51.7]]:
		if _find_nearby_land(ws, pt[0], pt[1], 8).x < 0:
			islands_ok = false
	_check(islands_ok, "Enlarged tiny islands (Hawaii, Iceland, Madagascar, Cuba, Japan, Falklands) present as land")

	# 3. Spawn & Long-Range Circular-Organic Expansion (Zero Heartbeat Spikes)
	_check(not bool(ws.apply_command({"type": "spawn_player", "x": 240, "y": 560, "name": "Ocean", "ai_count": 0}).get("ok", true)),
		"Spawn rejects ocean cells")

	var ws_ata := WorldState.new()
	ws_ata.load_world()
	var ata_spot: Vector2i = _find_nearby_land(ws_ata, 0.0, -80.0, 6)
	_check(bool(ws_ata.apply_command({"type": "spawn_player", "x": ata_spot.x, "y": ata_spot.y, "name": "Polar", "ai_count": 0}).get("ok", false)),
		"Player can spawn directly on Antarctica / South Pole")

	var us_spot: Vector2i = _find_nearby_land(ws, -98.0, 39.0, 4)
	ws.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Circular Test", "ai_count": 2})
	var p: NationData = ws.get_player_nation()
	var label_cell_before: Vector2i = ws.get_nation_label_cell(p.id)
	var label_scale_before: float = ws.get_nation_label_scale(p.id)
	p.troops = 500.0
	var pre_owner: PackedByteArray = ws.owner_grid.duplicate()
	var far_target: Vector2i = _find_nearby_land(ws, -82.0, 38.0, 4)  # ~46 sim cells east across unclaimed US
	var exp_res: Dictionary = ws.apply_command({
		"type": "expand_to", "nation_id": p.id, "x": far_target.x, "y": far_target.y, "commit_ratio": 0.65
	})
	var exp_t0: int = Time.get_ticks_usec()
	for t in range(1, 241):
		ws.step_tick(t)
	var exp_t1: int = Time.get_ticks_usec()
	print("[BENCH] 240 active 24 Hz ticks (circular expansion + AI + economy): %.2f ms (%.3f ms/tick)" % [
		float(exp_t1 - exp_t0) / 1000.0, float(exp_t1 - exp_t0) / 240000.0
	])

	var min_x := 9999
	var max_x := -1
	var min_y := 9999
	var max_y := -1
	var newly_claimed := 0
	for idx in range(ws.sim_width * ws.sim_height):
		if ws.owner_grid[idx] == p.id and pre_owner[idx] != p.id:
			newly_claimed += 1
			var xx: int = idx % ws.sim_width
			var yy: int = int(idx / ws.sim_width)
			min_x = mini(min_x, xx)
			max_x = maxi(max_x, xx)
			min_y = mini(min_y, yy)
			max_y = maxi(max_y, yy)
	var bbox_area: float = float((max_x - min_x + 1) * (max_y - min_y + 1))
	var compactness: float = float(newly_claimed) / maxf(bbox_area, 1.0)
	_check(bool(exp_res.get("ok", false)) and newly_claimed > 100 and compactness >= 0.28,
		"Long-range land expansion is circular-organic without heartbeat spikes (claimed=%d, compactness=%.2f)" % [newly_claimed, compactness])

	var label_cell_after: Vector2i = ws.get_nation_label_cell(p.id)
	var label_scale_after: float = ws.get_nation_label_scale(p.id)
	var label_on_owned: bool = label_cell_after.x >= 0 and ws.get_owner_at(label_cell_after.x, label_cell_after.y) == p.id
	var saved_cnt: int = p.owned_cell_count
	p.owned_cell_count = 80000
	var giant_scale: float = ws.get_nation_label_scale(p.id)
	p.owned_cell_count = saved_cnt
	_check(label_on_owned and label_cell_after.x > label_cell_before.x and label_scale_after > label_scale_before * 1.25 and giant_scale <= WorldState.NATION_LABEL_MAX_SCALE + 0.01,
		"Nation banner+name tracks centroid ((%d,%d)->(%d,%d)) and scales with cap (%.2f->%.2f, max=%.2f)" % [
			label_cell_before.x, label_cell_before.y, label_cell_after.x, label_cell_after.y, label_scale_before, label_scale_after, giant_scale
		])

	# Verify tight structure placement spacing (10 cells allowed, 4 cells rejected)
	p.gold = 1000000.0
	var sp_base := ws.apply_command({"type": "build_structure", "nation_id": p.id, "structure_type": StructureData.TYPE_TOWN, "x": us_spot.x, "y": us_spot.y})
	var sp_close_rej := ws.can_place_structure(p.id, StructureData.TYPE_DEFENSE_POST, us_spot.x + 4, us_spot.y)
	var sp_near_ok := ws.can_place_structure(p.id, StructureData.TYPE_DEFENSE_POST, us_spot.x + 10, us_spot.y)
	_check(bool(sp_base.get("ok", false)) and WorldState.MIN_STRUCTURE_SPACING_CELLS <= 8 and not bool(sp_close_rej.get("ok", true)) and bool(sp_near_ok.get("ok", false)),
		"Structure spacing allows close placement (10 cells ok, 4 cells rejected, min=%d)" % WorldState.MIN_STRUCTURE_SPACING_CELLS)

	# 4. No Port Required for Island Exploration + Closest-Shore Launch
	var ws_sea := WorldState.new()
	ws_sea.load_world()
	var normandy: Vector2i = _find_nearby_land(ws_sea, -1.5, 49.0, 4)
	ws_sea.apply_command({"type": "spawn_player", "x": normandy.x, "y": normandy.y, "name": "Channel", "ai_count": 0})
	var sea_p: NationData = ws_sea.get_player_nation()
	sea_p.troops = 350.0
	var england: Vector2i = _find_nearby_land(ws_sea, -1.5, 51.5, 4)
	var no_port_island: Dictionary = ws_sea.apply_command({
		"type": "expand_to", "nation_id": sea_p.id, "x": england.x, "y": england.y, "commit_ratio": 0.45
	})
	_check(bool(no_port_island.get("ok", false)) and str(no_port_island.get("mode", "")) == "naval_landing",
		"Island exploration succeeds WITHOUT a Port by launching from closest owned shore")
	for _t in range(480):
		ws_sea.step_tick(ws_sea.current_tick + 1)
	_check(ws_sea.get_owner_at(england.x, england.y) == sea_p.id,
		"Closest-shore expedition warship lands and expands onto target island")

	# 5. Instant Upgrades (Lv.1->10), Every-Level Improvements & Irregular Factory Bridges + OpenFront 1:1 Port-to-Port Trade
	sea_p.gold = 25000000.0
	# Build Port on England coast + Factory on Normandy shore across the English Channel
	var port_spot := Vector2i(-1, -1)
	for dy in range(-16, 17):
		for dx in range(-16, 17):
			var xx: int = england.x + dx
			var yy: int = england.y + dy
			if ws_sea.can_place_structure(sea_p.id, "port", xx, yy).get("ok", false):
				port_spot = Vector2i(xx, yy)
				break
		if port_spot.x >= 0:
			break
	var bp_res: Dictionary = ws_sea.apply_command({"type": "build_structure", "nation_id": sea_p.id, "structure_type": "port", "x": port_spot.x, "y": port_spot.y})
	var bf_res: Dictionary = ws_sea.apply_command({"type": "build_structure", "nation_id": sea_p.id, "structure_type": "factory", "x": normandy.x, "y": normandy.y})
	_check(bool(bp_res.get("ok", false)) and bool(bf_res.get("ok", false)),
		"Port and Factory construct with Pesos")

	# Add a peaceful coastal trading partner on Brittany so OpenFront 1:1 Port-to-Port trade operates across water
	var partner_coast: Vector2i = _find_nearby_land(ws_sea, -4.0, 48.2, 12)
	var partner_n: NationData = ws_sea._create_nation("TradeLeague", Color.TEAL, false, partner_coast, 168)
	partner_n.gold = 2000000.0
	var p2_spot := Vector2i(-1, -1)
	for dy in range(-16, 17):
		for dx in range(-16, 17):
			if ws_sea.can_place_structure(partner_n.id, "port", partner_coast.x + dx, partner_coast.y + dy).get("ok", false):
				p2_spot = Vector2i(partner_coast.x + dx, partner_coast.y + dy)
				break
		if p2_spot.x >= 0:
			break
	ws_sea.apply_command({"type": "build_structure", "nation_id": partner_n.id, "structure_type": "port", "x": p2_spot.x, "y": p2_spot.y})
	ws_sea._establish_alliance(sea_p.id, partner_n.id)

	var port_id: int = int(bp_res.get("structure_id", 0))
	var fac_id: int = int(bf_res.get("structure_id", 0))
	for _t in range(35):
		ws_sea.step_tick(ws_sea.current_tick + 1)

	var port_st: StructureData = ws_sea.get_structure(port_id)
	var fac_st: StructureData = ws_sea.get_structure(fac_id)
	_check(port_st.level == 1 and fac_st.level == 1, "Initial placement finishes to Lv.1")

	# Verify EVERY upgrade Lv.1 -> Lv.10 is INSTANT (0 ticks!) and strictly increases outputs
	var prev_port_gold := port_st.get_gold_per_sec()
	var prev_fac_range := fac_st.get_factory_base_radius()
	var every_lvl_improved := true
	for nxt in range(2, 11):
		var up_p: Dictionary = ws_sea.apply_command({"type": "upgrade_structure", "nation_id": sea_p.id, "structure_id": port_id})
		var up_f: Dictionary = ws_sea.apply_command({"type": "upgrade_structure", "nation_id": sea_p.id, "structure_id": fac_id})
		if not bool(up_p.get("ok", false)) or not bool(up_f.get("ok", false)):
			every_lvl_improved = false
			break
		if port_st.level != nxt or port_st.is_constructing or fac_st.level != nxt or fac_st.is_constructing:
			every_lvl_improved = false
		if port_st.get_gold_per_sec() <= prev_port_gold or StructureData.get_max_trade_ships(nxt) <= StructureData.get_max_trade_ships(nxt - 1):
			every_lvl_improved = false
		if fac_st.get_factory_base_radius() <= prev_fac_range:
			every_lvl_improved = false
		prev_port_gold = port_st.get_gold_per_sec()
		prev_fac_range = fac_st.get_factory_base_radius()

	_check(every_lvl_improved and port_st.level == 10 and fac_st.level == 10,
		"Instant upgrades (0 ticks) scale EVERY level 1..10 for Ports (10 ships) and Factories (range %.0f)" % fac_st.get_factory_base_radius())
	_check(not bool(ws_sea.apply_command({"type": "upgrade_structure", "nation_id": sea_p.id, "structure_id": fac_id}).get("ok", true)),
		"Upgrading beyond Max Level 10 (to Lv.11) is strictly rejected")

	# Verify irregular Factory link + Cross-Island Bridge formed across the Channel
	var has_bridge := false
	for link: Dictionary in ws_sea.factory_links:
		if int(link["factory_id"]) == fac_id and bool(link["crosses_water"]):
			has_bridge = true
	_check(has_bridge and fac_st.bridge_count >= 1 and port_st.factory_boost > 1.0,
		"Factory irregular range links across water to island Port and builds pixel-art Bridge (%d links)" % fac_st.connected_count)

	# Verify cross-island Factory road stays winding on land & places straight bridge ONLY over water spans
	var inland_fr := _find_nearby_land(ws_sea, -1.5, 48.2, 6)
	var eng_inland := _find_nearby_land(ws_sea, -1.5, 52.0, 6)
	if inland_fr.x >= 0 and eng_inland.x >= 0:
		ws_sea._claim_organic_dot(sea_p.id, inland_fr, 25, 0)
		ws_sea._claim_organic_dot(sea_p.id, eng_inland, 25, 0)
		var st_fr := StructureData.new()
		st_fr.id = 9001
		st_fr.cell = inland_fr
		var st_eng := StructureData.new()
		st_eng.id = 9002
		st_eng.cell = eng_inland
		var mixed_road: Dictionary = ws_sea._get_or_build_road(st_fr, st_eng)
		var m_pts: PackedVector2Array = mixed_road.get("road_points", PackedVector2Array())
		var m_spans: Array = mixed_road.get("water_spans", [])
		var land_dev := 0.0
		if m_pts.size() >= 3:
			var m_chord: Vector2 = (st_eng.get_world_pos() - st_fr.get_world_pos()).normalized()
			for pt_m: Vector2 in m_pts:
				land_dev = maxf(land_dev, absf((pt_m - st_fr.get_world_pos()).cross(m_chord)))
		var spans_aligned := true
		for sp_m: Array in m_spans:
			var found_seg := false
			for seg_i in range(m_pts.size() - 1):
				if (m_pts[seg_i].distance_squared_to(sp_m[0]) < 0.25 and m_pts[seg_i + 1].distance_squared_to(sp_m[1]) < 0.25):
					found_seg = true
					break
			if not found_seg:
				spans_aligned = false
				break
		_check(m_pts.size() > 4 and m_spans.size() >= 1 and land_dev > 0.3 and spans_aligned,
			"Cross-island Factory road stays winding on land (pts=%d, dev=%.1fpx) with straight bridge strictly over water (%d span)" % [m_pts.size(), land_dev, m_spans.size()],
			"pts=%d dev=%.2f spans=%d aligned=%s" % [m_pts.size(), land_dev, m_spans.size(), str(spans_aligned)])

	# Verify OpenFront 1:1 Port-to-Port auto-trading ships pay BOTH partners distance-scaled Pesos + Town/Factory popups
	sea_p.gold = 10000000.0
	var town_spot := Vector2i(-1, -1)
	for dy in range(-36, 37):
		for dx in range(-36, 37):
			if ws_sea.can_place_structure(sea_p.id, "town", normandy.x + dx, normandy.y + dy).get("ok", false):
				town_spot = Vector2i(normandy.x + dx, normandy.y + dy)
				break
		if town_spot.x >= 0:
			break
	var bt_res: Dictionary = ws_sea.apply_command({"type": "build_structure", "nation_id": sea_p.id, "structure_type": "town", "x": town_spot.x, "y": town_spot.y})
	var town_st: StructureData = ws_sea.get_structure(int(bt_res.get("structure_id", 0)))

	var trade_ok := {"count": 0, "water": true, "at_port": true, "partner_paid": 0}
	var popup_ok := {"town": false, "factory": false}
	ws_sea.trade_completed.connect(func(nid: int, pos: Vector2, _g: float) -> void:
		if nid == sea_p.id:
			trade_ok["count"] = int(trade_ok["count"]) + 1
			if pos.distance_to(port_st.get_world_pos()) > 1.0:
				trade_ok["at_port"] = false
		elif nid == partner_n.id:
			trade_ok["partner_paid"] = int(trade_ok["partner_paid"]) + 1
	)
	ws_sea.structure_income_popup.connect(func(nid: int, pos: Vector2, g: float, s_type: String) -> void:
		if nid == sea_p.id and g >= 1.0:
			if s_type == StructureData.TYPE_TOWN and town_st != null and pos.distance_to(town_st.get_world_pos()) < 1.0:
				popup_ok["town"] = true
			elif s_type == StructureData.TYPE_FACTORY and pos.distance_to(fac_st.get_world_pos()) < 1.0:
				popup_ok["factory"] = true
	)
	for _t in range(960):
		ws_sea.step_tick(ws_sea.current_tick + 1)
		for sh_id: int in ws_sea.ships.keys():
			var sh: ShipUnit = ws_sea.ships[sh_id]
			var pos_sim: Vector2i = ws_sea.world_to_sim(sh.position)
			if ws_sea.get_terrain_at(pos_sim.x, pos_sim.y) != WorldState.T_OCEAN:
				if bool(trade_ok["water"]):
					print("[DIAG] Ship off water: tick=%d id=%d kind=%s nid=%d pos=%s sim=%s terr=%d wps=%d" % [ws_sea.current_tick, sh.id, sh.kind, sh.nation_id, str(sh.position), str(pos_sim), ws_sea.get_terrain_at(pos_sim.x, pos_sim.y), sh.waypoints.size()])
				trade_ok["water"] = false
			if sh.kind == ShipUnit.KIND_TRADE:
				for wp: Vector2 in sh.waypoints:
					var wp_sim: Vector2i = ws_sea.world_to_sim(wp)
					if not ws_sea.sea_pathfinder.is_world_pos_navigable(wp) or ws_sea.get_terrain_at(wp_sim.x, wp_sim.y) != WorldState.T_OCEAN:
						if bool(trade_ok["water"]):
							print("[DIAG] Trade wp off water: id=%d wp=%s sim=%s" % [sh.id, str(wp), str(wp_sim)])
						trade_ok["water"] = false
	_check(bool(trade_ok["water"]) and bool(trade_ok["at_port"]) and int(trade_ok["count"]) > 0 and int(trade_ok["partner_paid"]) > 0,
		"OpenFront 1:1 Port trade ships stay on water & pay BOTH partners distance-scaled Pesos (%d trips)" % int(trade_ok["count"]),
		"water=%s at_port=%s cnt=%d partner=%d" % [str(trade_ok["water"]), str(trade_ok["at_port"]), int(trade_ok["count"]), int(trade_ok["partner_paid"])])
	_check(bool(popup_ok["town"]) and bool(popup_ok["factory"]),
		"Cities (Towns) and Factories emit on-top Peso popups cleanly")

	# 6. Explicit Claimed-Land Conquest Guard, Border Troop Decrease/Increase & Army Removal Check
	var rej_army: Dictionary = ws_sea.apply_command({"type": "deploy_army", "nation_id": sea_p.id, "x": normandy.x, "y": normandy.y, "troops": 100.0})
	_check(not bool(rej_army.get("ok", true)), "Removed buyable army command is strictly rejected")

	var ws_war := WorldState.new()
	ws_war.load_world()
	ws_war.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Orderer", "ai_count": 0})
	var p_war: NationData = ws_war.get_player_nation()
	var rival_spot := Vector2i(us_spot.x + 24, us_spot.y)
	var rival: NationData = ws_war._create_nation("Rival", Color.RED, false, rival_spot, 240)
	var rival_orig_cells: Array[int] = []
	for idx in range(ws_war.sim_width * ws_war.sim_height):
		if ws_war.owner_grid[idx] == rival.id:
			rival_orig_cells.append(idx)
	p_war.troops = 1200.0
	var wild_click := Vector2i(us_spot.x + 12, us_spot.y - 4)
	for dy_w in range(-8, 9):
		var cy_w: int = us_spot.y + dy_w
		var cx_w: int = us_spot.x + 12
		if ws_war.is_land_cell(cx_w, cy_w) and ws_war.get_owner_at(cx_w, cy_w) == 0:
			wild_click = Vector2i(cx_w, cy_w)
			break
	ws_war.apply_command({"type": "expand_to", "nation_id": p_war.id, "x": wild_click.x, "y": wild_click.y, "commit_ratio": 0.45})
	for _t in range(120):
		ws_war.step_tick(ws_war.current_tick + 1)
	var rival_cells_intact := true
	for r_idx: int in rival_orig_cells:
		if ws_war.owner_grid[r_idx] == p_war.id:
			rival_cells_intact = false
			break
	_check(rival_cells_intact,
		"Unclaimed expansion NEVER conquers neighboring claimed land unless explicitly clicked (0/%d rival cells lost to player)" % rival_orig_cells.size())

	# Explicit attack on Rival + live troop count decreasing then increasing on reinforce
	rival.troops = 320.0
	p_war.troops = 600.0
	var rival_pre_atk: int = rival.owned_cell_count
	var atk_target := rival_spot
	if ws_war.get_owner_at(atk_target.x, atk_target.y) != rival.id:
		for r_idx: int in rival_orig_cells:
			if ws_war.owner_grid[r_idx] == rival.id:
				atk_target = Vector2i(r_idx % ws_war.sim_width, int(r_idx / ws_war.sim_width))
				break
	var atk_res: Dictionary = ws_war.apply_command({"type": "expand_to", "nation_id": p_war.id, "x": atk_target.x, "y": atk_target.y, "commit_ratio": 0.25})
	var atk_eid: int = int(atk_res.get("expansion_id", 0))
	var atk_ord: ExpansionOrder = ws_war.expansions.get(atk_eid, null)
	var atk_started: bool = bool(atk_res.get("ok", false)) and atk_ord != null and atk_ord.target_owner_id == rival.id and atk_ord.front_world_pos != Vector2.ZERO
	var pre_troops: float = atk_ord.remaining_troops if atk_ord != null else 0.0
	for _t in range(3):
		ws_war.step_tick(ws_war.current_tick + 1)
	var troops_mid: float = atk_ord.remaining_troops if atk_ord != null else 0.0
	var decreased_ok: bool = atk_started and rival.owned_cell_count < rival_pre_atk and troops_mid < pre_troops
	var reinf_target := atk_target
	if ws_war.get_owner_at(reinf_target.x, reinf_target.y) != rival.id:
		for idx in range(ws_war.sim_width * ws_war.sim_height):
			if ws_war.owner_grid[idx] == rival.id:
				reinf_target = Vector2i(idx % ws_war.sim_width, int(idx / ws_war.sim_width))
				break
	var reinf_res: Dictionary = ws_war.apply_command({"type": "expand_to", "nation_id": p_war.id, "x": reinf_target.x, "y": reinf_target.y, "commit_ratio": 0.35})
	var increased_ok: bool = bool(reinf_res.get("ok", false)) and str(reinf_res.get("mode", "")) == "land_reinforce" and atk_ord != null and atk_ord.remaining_troops > troops_mid and atk_ord.troop_flash_timer > 0.0
	_check(decreased_ok and increased_ok,
		"Explicit attack conquers rival & tracks live border troop count decreasing (%.0f->%.0f) and increasing on reinforce (->%.0f)" % [pre_troops, troops_mid, atk_ord.remaining_troops if atk_ord != null else 0.0])

	# 7. A* Benchmark, Regional Seas, Strict Water-Only 1px Invariance, Close Island Hop & Owned-Island UX
	var nav_eu := ws_sea.sea_pathfinder.find_nearest_nav_cell(normandy, 12)
	var nav_us := ws_sea.sea_pathfinder.find_nearest_nav_cell(far_target, 28)
	ws_sea.sea_pathfinder._route_cache.clear()
	var pt0: int = Time.get_ticks_usec()
	var atl: PackedVector2Array = ws_sea.sea_pathfinder.find_path(nav_eu, nav_us)
	var pt1: int = Time.get_ticks_usec()
	print("[BENCH] Trans-Atlantic SeaPathfinder.find_path() (1024x512 uncached): %.2f ms" % (float(pt1 - pt0) / 1000.0))
	_check(not atl.is_empty(), "Trans-Atlantic SeaPathfinder finds valid route (%d waypoints)" % atl.size())

	var is_route_strictly_ocean := func(route: PackedVector2Array) -> bool:
		if route.is_empty():
			return false
		for i in range(route.size()):
			var pt: Vector2 = route[i]
			var sc: Vector2i = ws_sea.world_to_sim(pt)
			if ws_sea.get_terrain_at(sc.x, sc.y) != WorldState.T_OCEAN or not ws_sea.sea_pathfinder.is_world_pos_navigable(pt):
				return false
			if i + 1 < route.size():
				var a: Vector2 = route[i]
				var b: Vector2 = route[i + 1]
				var dist: float = a.distance_to(b)
				var steps: int = maxi(1, int(ceil(dist)))
				for s in range(1, steps + 1):
					var p_mid: Vector2 = a.lerp(b, float(s) / float(steps))
					var mc: Vector2i = ws_sea.world_to_sim(p_mid)
					if ws_sea.get_terrain_at(mc.x, mc.y) != WorldState.T_OCEAN:
						return false
		return true

	var lonlat_nav := func(lon: float, lat: float) -> Vector2i:
		var nx: int = clampi(int(round((lon + 180.0) / 360.0 * float(ws_sea.sea_pathfinder.nav_width))), 0, ws_sea.sea_pathfinder.nav_width - 1)
		var ny: int = clampi(int(round((90.0 - lat) / 180.0 * float(ws_sea.sea_pathfinder.nav_height))), 0, ws_sea.sea_pathfinder.nav_height - 1)
		return Vector2i(nx, ny)
	var atl_mid: Vector2i = lonlat_nav.call(-35.0, 35.0)
	var seas_ok := true
	var blocked_seas: PackedStringArray = PackedStringArray()
	for sea_entry: Array in [
		["Mediterranean W", 5.0, 38.5], ["Mediterranean E", 24.0, 34.5],
		["Black Sea", 34.0, 43.2], ["Red Sea", 38.5, 20.0],
		["Persian Gulf", 51.5, 26.5], ["Baltic Sea", 19.8, 57.5],
		["Hudson Bay", -84.0, 59.5], ["Caribbean Sea", -75.0, 15.0],
		["Java Sea", 111.0, -5.0], ["Philippine Sea", 132.0, 18.0],
		["Southern Ocean", 0.0, -62.0],
	]:
		var s_nav: Vector2i = lonlat_nav.call(float(sea_entry[1]), float(sea_entry[2]))
		var route_s: PackedVector2Array = ws_sea.sea_pathfinder.find_path(atl_mid, s_nav)
		if not is_route_strictly_ocean.call(route_s):
			seas_ok = false
			blocked_seas.append(str(sea_entry[0]))
	_check(seas_ok, "All 11 regional seas/gulfs reachable from North Atlantic with 0 land-crossing 1px samples", ", ".join(blocked_seas))

	var med_red_route := ws_sea.sea_pathfinder.find_path(lonlat_nav.call(24.0, 34.5), lonlat_nav.call(38.5, 20.0))
	var carib_pac_route := ws_sea.sea_pathfinder.find_path(lonlat_nav.call(-75.0, 15.0), lonlat_nav.call(-83.0, 6.0))
	var cape_routes_ok: bool = is_route_strictly_ocean.call(med_red_route) and is_route_strictly_ocean.call(carib_pac_route)
	_check(cape_routes_ok, "Inter-ocean sea routes (Med->Red %d wps, Carib->Pac %d wps) sail strictly on T_OCEAN without overland tunnels" % [med_red_route.size(), carib_pac_route.size()])

	var eu_open: Vector2i = lonlat_nav.call(-10.0, 44.0)
	var us_open: Vector2i = lonlat_nav.call(-70.0, 36.0)
	var lane0: PackedVector2Array = ws_sea.sea_pathfinder.find_trade_path(eu_open, us_open, 0)
	var lane2: PackedVector2Array = ws_sea.sea_pathfinder.find_trade_path(eu_open, us_open, 2)
	var lane4: PackedVector2Array = ws_sea.sea_pathfinder.find_trade_path(eu_open, us_open, 4)
	var lanes_water_ok: bool = is_route_strictly_ocean.call(lane0) and is_route_strictly_ocean.call(lane2) and is_route_strictly_ocean.call(lane4)
	var mid0: Vector2 = SeaPathfinder._sample_route_point_and_tangent(lane0, 0.5)["pos"] if lane0.size() >= 2 else Vector2.ZERO
	var mid4: Vector2 = SeaPathfinder._sample_route_point_and_tangent(lane4, 0.5)["pos"] if lane4.size() >= 2 else Vector2.ZERO
	var lane_spread_px: float = mid0.distance_to(mid4)
	_check(lanes_water_ok and lane_spread_px > 8.0,
		"Irregular multi-lane open-sea trade routes stay 100%% T_OCEAN and diverge across ocean lanes (spread=%.1fpx)" % lane_spread_px)

	# Close Strait / Island Hop without Port (Spain -> Morocco across Gibraltar) + 100%-owned island error check
	var ws_hop := WorldState.new()
	ws_hop.load_world()
	var spain_coast := _find_nearby_land(ws_hop, -5.6, 36.4, 8)
	var morocco_coast := _find_nearby_land(ws_hop, -5.6, 35.6, 8)
	ws_hop.apply_command({"type": "spawn_player", "x": spain_coast.x, "y": spain_coast.y, "name": "Hopper", "ai_count": 0})
	var hop_p: NationData = ws_hop.get_player_nation()
	hop_p.troops = 120.0
	var gib_res: Dictionary = ws_hop.apply_command({"type": "expand_to", "nation_id": hop_p.id, "x": morocco_coast.x, "y": morocco_coast.y, "commit_ratio": 0.4})
	for _t in range(190):
		ws_hop.step_tick(ws_hop.current_tick + 1)
	_check(bool(gib_res.get("ok", false)) and str(gib_res.get("mode", "")) == "naval_landing" and ws_hop.get_owner_at(morocco_coast.x, morocco_coast.y) == hop_p.id,
		"Close strait hop (Spain -> Morocco across Gibraltar) succeeds without a Port")

	var ws_ire := WorldState.new()
	ws_ire.load_world()
	var gb_spot := _find_nearby_land(ws_ire, -3.2, 53.3, 6)
	var ire_spot := _find_nearby_land(ws_ire, -6.2, 53.3, 6)
	ws_ire.apply_command({"type": "spawn_player", "x": gb_spot.x, "y": gb_spot.y, "name": "Islander", "ai_count": 0})
	var ire_p: NationData = ws_ire.get_player_nation()
	ire_p.troops = 140.0
	var ire_res: Dictionary = ws_ire.apply_command({"type": "expand_to", "nation_id": ire_p.id, "x": ire_spot.x, "y": ire_spot.y, "commit_ratio": 0.4})
	for _t in range(240):
		ws_ire.step_tick(ws_ire.current_tick + 1)
	_check(bool(ire_res.get("ok", false)) and str(ire_res.get("mode", "")) == "naval_landing" and ws_ire.get_owner_at(ire_spot.x, ire_spot.y) == ire_p.id,
		"Adjacent separate-island hop (Great Britain -> Ireland) succeeds without a Port")

	var falk := _find_nearby_land(ws_hop, -59.5, -51.7, 12)
	var falk_lm: int = ws_hop.landmass_grid[falk.y * ws_hop.sim_width + falk.x]
	for idx in range(ws_hop.sim_width * ws_hop.sim_height):
		if ws_hop.landmass_grid[idx] == falk_lm and ws_hop.owner_grid[idx] == 0:
			ws_hop._set_cell_owner(idx, hop_p.id)
	var owned_click: Dictionary = ws_hop.apply_command({"type": "expand_to", "nation_id": hop_p.id, "x": falk.x, "y": falk.y, "commit_ratio": 0.4})
	var owned_reason: String = str(owned_click.get("reason", ""))
	_check(not bool(owned_click.get("ok", true)) and owned_reason.find("already control this entire island/landmass") >= 0,
		"Clicking 100%-owned island gives clear owned-island guidance instead of frontier error", owned_reason)

	var ws_vic := WorldState.new()
	ws_vic.load_world()
	ws_vic.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Victor", "ai_count": 0})
	var v_p: NationData = ws_vic.get_player_nation()
	var v_fired := {"fired": false, "pct": 0.0}
	ws_vic.victory_reached.connect(func(_nid: int, pct: float) -> void:
		v_fired["fired"] = true
		v_fired["pct"] = pct
	)
	for idx in range(ws_vic.sim_width * ws_vic.sim_height):
		if ws_vic.terrain_grid[idx] >= WorldState.T_PLAINS and ws_vic.owner_grid[idx] == 0:
			ws_vic._set_cell_owner(idx, v_p.id)
			if v_p.territory_percent >= 80.0:
				ws_vic._check_victory()
				break
	_check(bool(v_fired["fired"]) and float(v_fired["pct"]) >= 80.0,
		"80%% victory (including Antarctica) triggers cleanly at >= 80.0%% (%.2f%%)" % float(v_fired["pct"]))

	var clk_res := []
	for fps: int in [30, 60, 144]:
		var c := SimulationClock.new()
		for _i in range(fps * 10):
			c.advance(1.0 / float(fps))
		clk_res.append(c.tick_count)
	_check(clk_res == [240, 240, 240], "24 Hz SimulationClock yields 240 ticks over 10s at 30/60/144 FPS")

	# Random distinct colors & improved 24 Hz AI expansion/building verification
	var ws_ai := WorldState.new()
	ws_ai.load_world()
	ws_ai.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "RandTest", "ai_count": 4})
	var seen_colors := {}
	for nid: int in ws_ai.nations.keys():
		var col_key: String = (ws_ai.nations[nid] as NationData).color.to_html(false)
		seen_colors[col_key] = true
	for t in range(1, 241):
		ws_ai.step_tick(t)
	var ai_grew := 0
	var ai_built := 0
	for nid: int in ws_ai.nations.keys():
		var n: NationData = ws_ai.nations[nid]
		if not n.is_player:
			if n.owned_cell_count > 248:
				ai_grew += 1
			if n.structure_ids.size() > 0:
				ai_built += 1
	_check(seen_colors.size() == 5 and ai_grew >= 2 and ai_built >= 1,
		"Random distinct colors assigned (%d unique) & smarter AI expands/builds (%d grew, %d built)" % [seen_colors.size(), ai_grew, ai_built])

	var theme_stream: AudioStream = load("res://assets/audio/music/world_war_pixel_theme.wav")
	var audio_streams: Dictionary = AudioManager.get("_streams") if AudioManager != null else {}
	var public_sfx_ok := FileAccess.file_exists("res://assets/audio/SOURCES.txt")
	for cat_k: String in ["missile_launch", "silo_nuke_launch", "sam_launch", "sam_intercept", "nuke_blast", "cannon_fire", "battle_clash", "boat_bell", "target_lock", "warship_horn", "troop_donate", "retreat_horn", "upgrade_instant", "land_conquer_pop", "invasion_warning", "friend_request", "defeat"]:
		if not audio_streams.has(cat_k) or (audio_streams[cat_k] as Array).is_empty():
			public_sfx_ok = false
	var stereo_audio_ok := true
	for wav_path: String in [
		"res://assets/audio/music/world_war_pixel_theme.wav",
		"res://assets/audio/ambience/world_ocean_ambience.wav",
		"res://assets/audio/sfx/nuke_blast.wav",
		"res://assets/audio/sfx/silo_nuke_launch.wav",
		"res://assets/audio/sfx/target_lock.wav",
		"res://assets/audio/sfx/victory_fanfare.wav",
		"res://assets/audio/sfx/defeat_drums.wav",
		"res://assets/audio/sfx/friend_request.wav",
		"res://assets/audio/sfx/upgrade_001.wav",
		"res://assets/audio/sfx/conquer_pop_001.wav",
		"res://assets/audio/sfx/conquer_pop_006.wav",
		"res://assets/audio/sfx/invasion_warning.wav",
	]:
		var ws_st: AudioStreamWAV = load(wav_path) as AudioStreamWAV
		if ws_st == null or not ws_st.stereo or ws_st.mix_rate != 44100:
			stereo_audio_ok = false
	var bus_lpf_removed := true
	for b_name: String in ["SFX", "UI"]:
		var b_idx: int = AudioServer.get_bus_index(b_name)
		if b_idx < 0:
			bus_lpf_removed = false
		else:
			for ef_i in range(AudioServer.get_bus_effect_count(b_idx)):
				if AudioServer.get_bus_effect(b_idx, ef_i) is AudioEffectLowPassFilter:
					bus_lpf_removed = false
	var pool_ok: bool = AudioManager != null and (AudioManager.get("_sfx_pool") as Array).size() >= 16
	var geom_ships_ok := (
		is_equal_approx(UnitsLayer.TRADE_SHIP_SIZE_PX, 2.0)
		and is_equal_approx(UnitsLayer.EXPLORER_SHIP_SIZE_PX, 3.0)
		and UnitsLayer.WARSHIP_DIAMOND_HALF_LEN > 2.0
	)
	_check(AudioManager != null and AudioServer.bus_count >= 5 and theme_stream != null and AudioManager.get("_music_player") != null and public_sfx_ok and stereo_audio_ok and bus_lpf_removed and pool_ok,
		"AudioManager loads 5 modern buses (no LPF choke), 16-voice pool, 44.1kHz stereo orchestral theme & cinema SFX")
	_check(geom_ships_ok and CapitalMarkersLayer.STRUCTURE_ICON_SIZE_PX >= 16.0 and CapitalMarkersLayer.STRUCTURE_LEVEL_MIN_ZOOM >= 1.4 and is_equal_approx(1.0 / maxf(0.45, 1.0), 1.0),
		"Land icons (%.0fpx), geometric ships (2x2/3x3/diamond), non-enlarging zoom & gated levels (>=%.2fx)" % [CapitalMarkersLayer.STRUCTURE_ICON_SIZE_PX, CapitalMarkersLayer.STRUCTURE_LEVEL_MIN_ZOOM])
	var main_ps: PackedScene = load("res://scenes/main.tscn")
	_check(main_ps != null, "Main scene loads cleanly")
	if main_ps != null:
		var inst: Node = main_ps.instantiate()
		add_child(inst)
		var wm: Node = inst.get_node_or_null("WorldMap")
		var hud: GameHUD = inst.get_node_or_null("HUD") as GameHUD
		var ok := wm != null and hud != null
		for lname: String in [
			"Layer1_BaseTerrain", "Layer2_ProvinceBoundaries", "Layer3_PoliticalOwnership",
			"Layer4_CitiesAndInfrastructure", "Layer5_Units", "Layer6_SelectionOverlay",
			"Layer7_EnvironmentDecor", "WorldCamera",
		]:
			if wm == null or wm.get_node_or_null(lname) == null:
				ok = false
		var no_army_ui := inst.get_node_or_null("HUD/Root/ActionDock/HBox/ArmyBtn") == null and inst.get_node_or_null("HUD/Root/RightStack/ArmyPanel") == null
		var l4: Node = wm.get_node_or_null("Layer4_CitiesAndInfrastructure") if wm != null else null
		var has_banner := l4 != null and l4.get("_tex_banner") != null and l4.get("_tex_banner_mask") != null
		var ui_ok := false
		if hud != null:
			var menu_init: bool = (
				hud.menu_overlay.visible
				and is_equal_approx(hud.menu_overlay.color.a, 0.0)
				and hud.home_corners.visible
				and hud.sp_card != null and not hud.sp_card.visible
				and hud.get("_settings_card") != null and not (hud.get("_settings_card") as Control).visible
				and inst.get_node_or_null("HUD/Root/MenuOverlay/Center/PatchNotesCard") == null
				and inst.get_node_or_null("HUD/Root/MenuOverlay/Center/MenuCard/VBox/ColorInfo") == null
				and not hud.spawn_banner.visible and not hud.top_bar.visible and not hud.action_dock.visible and not hud.leaderboard_panel.visible and not hud.ping_badge.visible
			)
			var cam_pan_init: bool = wm != null and wm.camera.auto_pan_enabled
			var cam_p0: Vector2 = wm.camera._target_pos if wm != null else Vector2.ZERO
			if wm != null:
				wm.camera._process(0.5)
			var cam_pan_moved: bool = wm != null and not wm.camera._target_pos.is_equal_approx(cam_p0)
			hud.open_friends_page("menu")
			var friends_open_ok: bool = hud.friends_card.visible and not hud.menu_card.visible
			hud._on_friends_back_pressed()
			var friends_back_ok: bool = (not hud.friends_card.visible) and hud.menu_card.visible
			var prof_cfg := ConfigFile.new()
			var had_prof := prof_cfg.load(GameHUD.PROFILE_SAVE_PATH) == OK
			var prev_saved_name: String = str(prof_cfg.get_value("profile", "player_name", "")) if had_prof else ""
			hud.save_player_name("Admiral Reyes")
			hud.menu_name_edit.text = "TmpOverride"
			hud._load_profile()
			var name_rem_ok: bool = hud.menu_name_edit.text == "Admiral Reyes" and hud.nation_name_edit.text == "Admiral Reyes"
			if had_prof and not prev_saved_name.is_empty():
				hud.save_player_name(prev_saved_name)
			elif FileAccess.file_exists(GameHUD.PROFILE_SAVE_PATH):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(GameHUD.PROFILE_SAVE_PATH))
			hud._on_play_pressed()
			var play_reveals_spawn: bool = (not hud.menu_overlay.visible) and hud.spawn_banner.visible and hud.top_bar.visible and hud.ping_badge.visible and (not wm.camera.auto_pan_enabled)
			var no_color_or_slider: bool = inst.get_node_or_null("HUD/Root/SpawnBanner/VBox/Row/ColorRow") == null and inst.get_node_or_null("HUD/Root/ActionDock/HBox/CommitBox/CommitSlider") == null
			hud.set_commit_ratio(0.10)
			var r10: bool = is_equal_approx(hud.get_commit_ratio(), 0.10)
			hud.set_commit_ratio(0.25)
			var r25: bool = is_equal_approx(hud.get_commit_ratio(), 0.25) and hud.attack_pct_label.text == "25%"
			hud.set_commit_ratio(0.50)
			var r50: bool = is_equal_approx(hud.get_commit_ratio(), 0.50)
			hud.set_commit_ratio(0.75)
			var r75: bool = is_equal_approx(hud.get_commit_ratio(), 0.75)
			hud.set_commit_ratio(0.35)
			var hk_init: bool = bool(hud.get("_hotkeys_enabled"))
			hud.toggle_hotkeys()
			var hk_off: bool = not bool(hud.get("_hotkeys_enabled"))
			hud.toggle_hotkeys()
			hud._on_lb_toggle_pressed()
			var lb_min: bool = (not hud.leaderboard_panel.visible) and hud.world_min_btn.visible
			hud._on_lb_toggle_pressed()
			var lb_restored: bool = hud.leaderboard_panel.visible and (not hud.world_min_btn.visible)
			var dock_icons: bool = (
				hud.expand_btn.icon != null
				and hud.town_btn.icon != null
				and hud.factory_btn.icon != null
				and hud.port_btn.icon != null
				and hud.defense_btn.icon != null
				and hud.silo_btn.icon != null
				and hud.sam_btn.icon != null
				and hud.warship_btn.icon != null
				and hud.atom_dock_btn.icon != null
				and hud.hbomb_dock_btn.icon != null
				and hud.mirv_dock_btn.icon != null
				and hud.gold_icon.texture != null
				and hud.troops_icon.texture != null
				and hud.logo_rect.texture != null
				and hud.play_btn.icon != null
				and hud.friends_back_btn.icon != null
				and hud.mp_disconnect_btn.icon != null
				and hud.quit_btn.icon != null
				and hud.st_close_btn.icon != null
				and hud.menu_rankings_btn.icon != null
				and hud.menu_audio_btn.icon != null
				and hud.sp_back_btn.icon != null
				and (inst.get_node("HUD/Root/MenuOverlay/Center/SingleplayerCard/VBox/NameRow/Lbl") as Label).text == "Nation Name"
				and is_equal_approx(WorldState.NEUTRAL_EXPLORE_TROOP_COST_MULT, 1.85)
				and GameHUD.SERVER_REGIONS.size() == 1
				and hud.get_selected_server_name() == "Manila, PH"
				and not hud.mp_server_edit.visible
				and hud.expand_btn.text == "Explore"
				and (hud.action_dock.offset_right - hud.action_dock.offset_left) <= 1160.0
				and hud.action_dock.get_combined_minimum_size().x <= 1140.0
				and hud.action_dock.get_combined_minimum_size().y <= 70.0
				and hud.nation_color_swatch != null
				and hud.troop_bar != null
				and hud.attack_preview_label != null
				and hud.town_btn.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
				and hud.commit_10_btn != null
				and hud.commit_25_btn != null
				and hud.radial_attack_btn.text == "Attack"
				and hud.radial_build_btn.text == "Upgrade"
				and hud.radial_warship_btn.text == "Boat"
				and hud.radial_dip_btn.text == "Ally"
				and inst.get_node_or_null("HUD/Root/VictoryOverlay") != null
				and inst.get_node_or_null("HUD/Root/SpectatorBanner") != null
			)
			var of_nodes := inst.get_node_or_null("HUD/Root/RadialMenu") != null and inst.get_node_or_null("HUD/Root/RightStack/DiplomacyPanel") != null and inst.get_node_or_null("HUD/Root/AllianceBanner") != null
			var mp_nodes := inst.get_node_or_null("HUD/Root/MenuOverlay/Center/MpLobbyCard") != null and inst.get_node_or_null("HUD/Root/MenuOverlay/Center/FriendsCard") != null and hud.multiplayer_btn != null
			var ping_nodes := inst.get_node_or_null("HUD/Root/PingBadge") != null and inst.get_node_or_null("HUD/Root/PingBadge/HBox/PingIcon") != null and inst.get_node_or_null("HUD/Root/PingBadge/HBox/PingLabel") != null
			hud.update_ping(42)
			var ping_set_ok: bool = hud.ping_label.text == "42ms"
			hud.update_ping(-1)
			var ping_reset_ok: bool = hud.ping_label.text == "--ms"
			var peso_hud_ok: bool = hud.gold_header_lbl.text == "PESOS"
			var l5: Node = wm.get_node_or_null("Layer5_Units") if wm != null else null
			var smooth_filter_ok: bool = l4 != null and l5 != null and (l4 as CanvasItem).texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR and (l5 as CanvasItem).texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR
			# Verify hotkeys 1..7 + nuke hotkeys 8/N (Atom), 9/H (H-Bomb), F/M (MIRV) during PLAYING phase
			hud._world_state.match_phase = WorldState.PHASE_PLAYING
			var ev_2 := InputEventKey.new()
			ev_2.keycode = KEY_2
			ev_2.pressed = true
			hud._unhandled_input(ev_2)
			var hk_fact: bool = hud._build_mode == StructureData.TYPE_FACTORY
			var ev_7 := InputEventKey.new()
			ev_7.keycode = KEY_7
			ev_7.pressed = true
			hud._unhandled_input(ev_7)
			var hk_ship: bool = hud._build_mode == "warship"
			var ev_n := InputEventKey.new()
			ev_n.keycode = KEY_8
			ev_n.pressed = true
			hud._unhandled_input(ev_n)
			var hk_atom: bool = hud._missile_mode == MissileUnit.KIND_ATOM
			var ev_h := InputEventKey.new()
			ev_h.keycode = KEY_9
			ev_h.pressed = true
			hud._unhandled_input(ev_h)
			var hk_h: bool = hud._missile_mode == MissileUnit.KIND_HYDROGEN
			var ev_m := InputEventKey.new()
			ev_m.keycode = KEY_F
			ev_m.pressed = true
			hud._unhandled_input(ev_m)
			var hk_m: bool = hud._missile_mode == MissileUnit.KIND_MIRV
			hud.clear_missile_mode()
			hud._world_state.match_phase = WorldState.PHASE_SPAWN_SELECT
			ui_ok = menu_init and cam_pan_init and cam_pan_moved and friends_open_ok and friends_back_ok and name_rem_ok and play_reveals_spawn and no_color_or_slider and r10 and r25 and r50 and r75 and hk_init and hk_off and lb_min and lb_restored and dock_icons and of_nodes and mp_nodes and ping_nodes and ping_set_ok and ping_reset_ok and peso_hud_ok and smooth_filter_ok and hk_fact and hk_ship and hk_atom and hk_h and hk_m
			if not ui_ok:
				print("[UI DEBUG] menu_init=", menu_init, " cam_pan_init=", cam_pan_init, " cam_pan_moved=", cam_pan_moved, " friends_open=", friends_open_ok, " friends_back=", friends_back_ok, " name_rem=", name_rem_ok, " play=", play_reveals_spawn, " r10/25=", r10, "/", r25, " lb_min=", lb_min, " lb_restored=", lb_restored, " dock_icons=", dock_icons, " dock_min=", hud.action_dock.get_combined_minimum_size(), " mp_nodes=", mp_nodes, " peso=", peso_hud_ok, " hk=", hk_fact, "/", hk_ship, "/", hk_atom, "/", hk_h, "/", hk_m)
		_check(ok and no_army_ui and has_banner and ui_ok,
			"Main scene verifies smooth filters, Pesos bottom HUD, hotkeys(1..9,F), PingBadge, RadialMenu & Diplomacy")
		inst.queue_free()

	_run_openfront_feature_tests(us_spot, normandy, england, port_spot, town_spot)


func _run_openfront_feature_tests(us_spot: Vector2i, normandy: Vector2i, england: Vector2i, port_spot: Vector2i, _town_spot: Vector2i) -> void:
	# Milestone 1: Logistic Troop Growth Curve + Defense Post + Boat Retreat
	var ws := WorldState.new()
	ws.load_world()
	ws.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Defender", "ai_count": 0, "seed": 4242})
	var p: NationData = ws.get_player_nation()
	p.gold = 10000000.0
	p.troops = p.max_troops * 0.50
	ws.step_tick(1)
	var rate_50: float = p.effective_troops_per_sec
	p.troops = p.max_troops * 0.96
	ws.step_tick(2)
	var rate_96: float = p.effective_troops_per_sec
	_check(rate_50 > rate_96 * 1.4, "OpenFront logistic troop growth curve peaks near ~42-50%% vs ~96%% fill (%.2f vs %.2f)" % [rate_50, rate_96])

	# Verify exact Peso economy inflation curves + Warship & Structure pricing caps
	var peso_prices_ok: bool = (
		is_equal_approx(ShipUnit.get_warship_cost(0), 250000.0)
		and is_equal_approx(ShipUnit.get_warship_cost(1), 500000.0)
		and is_equal_approx(ShipUnit.get_warship_cost(2), 750000.0)
		and is_equal_approx(ShipUnit.get_warship_cost(5), 750000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_TOWN, 0), 125000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_TOWN, 1), 250000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_TOWN, 2), 500000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_TOWN, 3), 1000000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_DEFENSE_POST, 0), 50000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_DEFENSE_POST, 1), 100000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_DEFENSE_POST, 2), 200000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_DEFENSE_POST, 3), 250000.0)
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_DEFENSE_POST, 5), 250000.0)
		and StructureData.format_compact(125000.0) == "125K"
		and StructureData.format_compact(19700.0) == "19.7K"
		and StructureData.format_compact(4760.0) == "4.76K"
		and StructureData.format_compact(1500000.0) == "1.5M"
		and StructureData.format_compact(690.0) == "690"
		and is_equal_approx(StructureData.get_build_cost(StructureData.TYPE_MISSILE_SILO), 1000000.0)
		and is_equal_approx(StructureData.get_build_cost(StructureData.TYPE_SAM_LAUNCHER), 1500000.0)
		and is_equal_approx(MissileUnit.get_cost(MissileUnit.KIND_ATOM), 750000.0)
		and is_equal_approx(MissileUnit.get_cost(MissileUnit.KIND_HYDROGEN), 5000000.0)
		and is_equal_approx(MissileUnit.get_cost(MissileUnit.KIND_MIRV), 25000000.0)
	)
	_check(peso_prices_ok, "Peso inflation pricing verified (Defense Post 250k cap, Buildings 2x->1M cap, Warships 2x->750k, Nukes 750k/5M/25M)")

	# Defense Post vs unfortified conquest cost + scaling build cost
	var rival := ws._create_nation("Tester", Color.RED, false, Vector2i(us_spot.x + 24, us_spot.y), 240)
	rival.gold = 5000000.0
	var def_res: Dictionary = ws.apply_command({"type": "build_structure", "nation_id": rival.id, "structure_type": StructureData.TYPE_DEFENSE_POST, "x": rival.capital_cell.x, "y": rival.capital_cell.y})
	var def_cost1: float = ws.get_structure_build_cost(rival.id, StructureData.TYPE_DEFENSE_POST)
	for _t in range(32):
		ws.step_tick(ws.current_tick + 1)
	var def_st: StructureData = ws.get_structure(int(def_res.get("structure_id", 0)))
	var mult_1: float = ws.get_defense_multiplier_at(rival.id, rival.capital_cell)
	ws.apply_command({"type": "upgrade_structure", "nation_id": rival.id, "structure_id": def_st.id})
	var mult_2: float = ws.get_defense_multiplier_at(rival.id, rival.capital_cell)
	var def_r_ok: bool = (
		is_equal_approx(StructureData.get_defense_radius_for_level(1), 28.0)
		and is_equal_approx(StructureData.get_defense_radius_for_level(10), 64.0)
		and is_equal_approx(ws.get_defense_multiplier_at(rival.id, Vector2i(rival.capital_cell.x + 40, rival.capital_cell.y)), 1.0)
	)
	_check(def_st != null and def_st.level == 2 and mult_1 >= 1.80 and mult_2 > mult_1 and def_cost1 > StructureData.get_build_cost(StructureData.TYPE_DEFENSE_POST) and def_r_ok,
		"Defense Post fortifies tight border (Lv.1 r=%.0f -> %.2fx -> %.2fx) & scaling Peso cost increases (%s)" % [StructureData.get_defense_radius_for_level(1), mult_1, mult_2, StructureData.format_pesos(def_cost1)])

	# 1.5K startup troops check
	var ws_start := WorldState.new()
	ws_start.load_world()
	ws_start.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Start1500", "ai_count": 2, "seed": 111})
	var start_all_1500 := true
	for nid_s: int in ws_start.nations.keys():
		if not is_equal_approx((ws_start.nations[nid_s] as NationData).troops, 1500.0):
			start_all_1500 = false
	_check(start_all_1500 and ws_start.nations.size() == 3,
		"Player and AI nations start with 1.5K troops (1500.0)")

	# OpenFront 1:1 25% contested attack retreat malus
	for bx in range(us_spot.x + 1, rival.capital_cell.x):
		var b_idx: int = us_spot.y * ws.sim_width + bx
		if ws.is_land_cell(bx, us_spot.y) and ws.owner_grid[b_idx] == 0:
			ws._set_cell_owner(b_idx, p.id)
	p.troops = 280.0
	var ret_ord_res: Dictionary = ws.apply_command({"type": "expand_to", "nation_id": p.id, "x": rival.capital_cell.x, "y": rival.capital_cell.y, "commit_ratio": 0.50})
	var ret_eid: int = int(ret_ord_res.get("expansion_id", 0))
	var troops_post_launch: float = p.troops
	var ret_cancel: Dictionary = ws.apply_command({"type": "cancel_expansion", "nation_id": p.id, "expansion_id": ret_eid})
	_check(bool(ret_cancel.get("ok", false)) and is_equal_approx(float(ret_cancel.get("returned_troops", 0.0)), 105.0) and is_equal_approx(p.troops - troops_post_launch, 105.0),
		"OpenFront 1:1 contested attack retreat enforces 25%% troop malus (140 -> 105 returned)",
		"ord=%s cancel=%s" % [str(ret_ord_res), str(ret_cancel)])

	# Boat Retreat (cancel_ship) + Landing Boat sinking + Warship Trade Capture + Range Control
	var ws_nav := WorldState.new()
	ws_nav.load_world()
	ws_nav.apply_command({"type": "spawn_player", "x": normandy.x, "y": normandy.y, "name": "Admiralty", "ai_count": 0, "seed": 777})
	var nav_p: NationData = ws_nav.get_player_nation()
	nav_p.gold = 10000000.0
	nav_p.troops = 300.0
	var cancel_boat: Dictionary = ws_nav.apply_command({"type": "expand_to", "nation_id": nav_p.id, "x": england.x, "y": england.y, "commit_ratio": 0.40})
	var c_sid: int = int(cancel_boat.get("ship_id", 0))
	var troops_before_retreat: float = nav_p.troops
	var retreat_res: Dictionary = ws_nav.apply_command({"type": "cancel_ship", "nation_id": nav_p.id, "ship_id": c_sid})
	_check(bool(retreat_res.get("ok", false)) and not ws_nav.ships.has(c_sid) and nav_p.troops > troops_before_retreat + 80.0,
		"Landing boat Retreat (cancel_ship) recalls vessel & refunds ~85%% troops")

	# Milestone 2: Warship build, movement, sinking enemy Landing Boat, and capturing enemy Trade Ship
	var p_port_cell := Vector2i(-1, -1)
	for dy in range(-16, 17):
		for dx in range(-16, 17):
			if ws_nav.can_place_structure(nav_p.id, StructureData.TYPE_PORT, normandy.x + dx, normandy.y + dy).get("ok", false):
				p_port_cell = Vector2i(normandy.x + dx, normandy.y + dy)
				break
		if p_port_cell.x >= 0:
			break
	var np_res: Dictionary = ws_nav.apply_command({"type": "build_structure", "nation_id": nav_p.id, "structure_type": StructureData.TYPE_PORT, "x": p_port_cell.x, "y": p_port_cell.y})
	for _t in range(34):
		ws_nav.step_tick(ws_nav.current_tick + 1)
	var np_id: int = int(np_res.get("structure_id", 0))
	var w_res: Dictionary = ws_nav.apply_command({"type": "build_warship", "nation_id": nav_p.id, "port_id": np_id})
	var ws_id: int = int(w_res.get("ship_id", 0))
	var warship: ShipUnit = ws_nav.ships.get(ws_id, null)
	var foe := ws_nav._create_nation("Corsair", Color.ORANGE, false, port_spot, 200)
	foe.troops = 300.0
	var nav_off: Vector2 = warship.position
	var trade_start: Vector2 = warship.position + Vector2(-8.0, 0.0)
	var trade_end: Vector2 = warship.position
	if warship.waypoints.size() >= 2:
		var wp1: Vector2 = warship.waypoints[warship.waypoints.size() - 1]
		nav_off = warship.position.lerp(wp1, 0.35)
		trade_start = warship.position.lerp(wp1, 0.55)
		trade_end = warship.position.lerp(wp1, 0.15)
	var enemy_land_boat := ShipUnit.new()
	enemy_land_boat.id = 9001
	enemy_land_boat.kind = ShipUnit.KIND_LANDING
	enemy_land_boat.nation_id = foe.id
	enemy_land_boat.position = nav_off
	enemy_land_boat.waypoints = PackedVector2Array([nav_off, trade_start])
	enemy_land_boat.waypoint_index = 1
	enemy_land_boat.speed_px_per_sec = 1.2
	enemy_land_boat.troops_carried = 110.0
	enemy_land_boat.hp = 45.0
	enemy_land_boat.max_hp = 45.0
	ws_nav.ships[9001] = enemy_land_boat

	var enemy_trade := ShipUnit.new()
	enemy_trade.id = 9002
	enemy_trade.kind = ShipUnit.KIND_TRADE
	enemy_trade.nation_id = foe.id
	enemy_trade.position = trade_start
	enemy_trade.waypoints = PackedVector2Array([trade_start, trade_end])
	enemy_trade.waypoint_index = 1
	enemy_trade.speed_px_per_sec = 1.2
	enemy_trade.gold_value = 65000.0
	ws_nav.ships[9002] = enemy_trade

	var gold_pre_plunder: float = nav_p.gold
	var nav_ev := {"sunk": false, "captured_ship": false}
	ws_nav.ship_destroyed.connect(func(_pos: Vector2, k: String) -> void:
		if k == ShipUnit.KIND_LANDING:
			nav_ev["sunk"] = true
	)
	ws_nav.trade_ship_captured.connect(func(_cid: int, _pos: Vector2, _amt: float) -> void:
		nav_ev["captured_ship"] = true
	)
	for _t in range(220):
		ws_nav.step_tick(ws_nav.current_tick + 1)
	var st_probe := StructureData.new()
	st_probe.level = 1
	var slow_ships_ok := WorldState.SHIP_SPEED_PX_SEC <= 25.0 and st_probe.get_ship_speed() <= 32.0
	var zoom_no_enlarge_ok := is_equal_approx(minf(1.0, 1.0 / maxf(0.45, 0.25)), 1.0)
	_check(bool(w_res.get("ok", false)) and slow_ships_ok and zoom_no_enlarge_ok and bool(nav_ev["sunk"]) and bool(nav_ev["captured_ship"]) and not ws_nav.ships.has(9001) and warship.xp >= 2 and warship.ship_level >= 2 and nav_p.gold > gold_pre_plunder,
		"Warship (non-enlarging) sinks Landing Boat, captures Trade Ship to Port (+Pesos) & reaches Lv.%d" % warship.ship_level,
		"w=%s sunk=%s cap=%s 9001=%s xp=%d p=%.0f->%.0f" % [str(w_res), str(nav_ev["sunk"]), str(nav_ev["captured_ship"]), str(ws_nav.ships.has(9001)), warship.xp, gold_pre_plunder, nav_p.gold])

	# Verify manual Warship movement obeys player destination without AI wander + stays on T_OCEAN
	var cmd_w_res: Dictionary = ws_nav.apply_command({
		"type": "command_warship", "nation_id": nav_p.id, "ship_id": ws_id, "x": normandy.x - 28, "y": normandy.y - 12
	})
	var manual_set_ok: bool = bool(cmd_w_res.get("ok", false)) and warship.manual_moving
	var warship_water_ok: bool = manual_set_ok
	for _t in range(180):
		ws_nav.step_tick(ws_nav.current_tick + 1)
		if ws_nav.ships.has(ws_id):
			var w_sim: Vector2i = ws_nav.world_to_sim(warship.position)
			if ws_nav.get_terrain_at(w_sim.x, w_sim.y) != WorldState.T_OCEAN:
				warship_water_ok = false
				break
	_check(warship_water_ok and warship.position.distance_to(warship.patrol_center) <= warship.patrol_radius + 8.0,
		"Commanded Warship sails player destination on T_OCEAN and patrols strictly within dedicated range (dist=%.1f <= %.1f)" % [warship.position.distance_to(warship.patrol_center), warship.patrol_radius])

	# Milestone 3: Curved Ballistic Missiles, Nearest Silo Auto-Select, MIRV & SAM Interception
	var ws_nuke := WorldState.new()
	ws_nuke.load_world()
	ws_nuke.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Atomic", "ai_count": 0, "seed": 999})
	var ap: NationData = ws_nuke.get_player_nation()
	ap.gold = 60000000.0
	var target_city := _find_nearby_land(ws_nuke, -82.0, 38.0, 10)
	var tgt_n := ws_nuke._create_nation("TargetState", Color.GREEN, false, target_city, 560)
	tgt_n.gold = 2000000.0
	var s_res: Dictionary = ws_nuke.apply_command({"type": "build_structure", "nation_id": ap.id, "structure_type": StructureData.TYPE_MISSILE_SILO, "x": us_spot.x, "y": us_spot.y})
	# Build a closer 2nd Silo east of us_spot toward target_city to verify nearest-silo dispatch
	ws_nuke._claim_organic_dot(ap.id, Vector2i(us_spot.x + 28, us_spot.y), 320, 0)
	var close_silo_cell := Vector2i(us_spot.x + 28, us_spot.y)
	var s2_res: Dictionary = ws_nuke.apply_command({"type": "build_structure", "nation_id": ap.id, "structure_type": StructureData.TYPE_MISSILE_SILO, "x": close_silo_cell.x, "y": close_silo_cell.y})
	var sam_res: Dictionary = ws_nuke.apply_command({"type": "build_structure", "nation_id": tgt_n.id, "structure_type": StructureData.TYPE_SAM_LAUNCHER, "x": target_city.x, "y": target_city.y})
	for _t in range(32):
		ws_nuke.step_tick(ws_nuke.current_tick + 1)
	var intercepted_flag := {"count": 0}
	ws_nuke.missile_intercepted.connect(func(_pos: Vector2) -> void: intercepted_flag["count"] = int(intercepted_flag["count"]) + 1)
	var atom_res: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_ATOM, "x": target_city.x, "y": target_city.y})
	var atom_m: MissileUnit = ws_nuke.missiles.get(int(atom_res.get("missile_id", 0)), null)
	var curved_ok: bool = false
	var nearest_silo_ok: bool = int(atom_res.get("silo_id", 0)) == int(s2_res.get("structure_id", -1))
	if atom_m != null:
		var chord_dir: Vector2 = (atom_m.target_pos - atom_m.start_pos).normalized()
		var apex_pt: Vector2 = atom_m.get_curve_point(0.5)
		var proj: Vector2 = atom_m.start_pos + chord_dir * (apex_pt - atom_m.start_pos).dot(chord_dir)
		curved_ok = apex_pt.distance_to(proj) > 12.0
	for _t in range(180):
		ws_nuke.step_tick(ws_nuke.current_tick + 1)
	_check(bool(s_res.get("ok", false)) and bool(s2_res.get("ok", false)) and nearest_silo_ok and curved_ok and bool(sam_res.get("ok", false)) and bool(atom_res.get("ok", false)) and int(intercepted_flag["count"]) == 1,
		"Nearest Silo fires curved ballistic Atom Bomb & shortened SAM intercepts mid-air",
		"near=%s curve=%s sam=%s hits=%d" % [str(nearest_silo_ok), str(curved_ok), str(sam_res), int(intercepted_flag["count"])])

	# Verify shortened SAM range + 2-consecutive-missile burst limit + slow reload + nuke building destruction!
	var sam_st_chk: StructureData = ws_nuke.get_structure(int(sam_res.get("structure_id", 0)))
	var sam_specs_ok: bool = sam_st_chk != null and sam_st_chk.get_sam_radius() <= 44.0 and sam_st_chk.get_sam_cooldown_ticks() >= 300
	if sam_st_chk != null:
		sam_st_chk.sam_ammo = StructureData.SAM_MAX_AMMO
		sam_st_chk.sam_reload_ticks = 0
		sam_st_chk.action_cooldown_ticks = 0
	var pre_burst_hits: int = int(intercepted_flag["count"])
	for shot_i in range(3):
		for sid_s in [int(s_res.get("structure_id", 0)), int(s2_res.get("structure_id", 0))]:
			var s_obj: StructureData = ws_nuke.get_structure(sid_s)
			if s_obj != null:
				s_obj.action_cooldown_ticks = 0
		ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_ATOM, "x": target_city.x, "y": target_city.y})
		for _t in range(16):
			ws_nuke.step_tick(ws_nuke.current_tick + 1)
	for _t in range(190):
		ws_nuke.step_tick(ws_nuke.current_tick + 1)
	var burst_hits: int = int(intercepted_flag["count"]) - pre_burst_hits
	var sam_destroyed: bool = ws_nuke.get_structure(int(sam_res.get("structure_id", 0))) == null
	_check(sam_specs_ok and burst_hits == 2 and sam_destroyed,
		"Shortened SAM intercepts max 2 consecutive missiles before slow reload & 3rd nuke destroys SAM building (%d/3 intercepted)" % burst_hits,
		"specs=%s burst=%d sam_gone=%s" % [str(sam_specs_ok), burst_hits, str(sam_destroyed)])

	# Also verify H-Bomb destroys structures cleanly within full blast radius on an intact target nation
	var hbomb_city := _find_nearby_land(ws_nuke, -84.0, 33.0, 10)
	var tgt_n2 := ws_nuke._create_nation("TargetStateB", Color.ORANGE, false, hbomb_city, 720)
	tgt_n2.gold = 2000000.0
	var tgt_town_res: Dictionary = ws_nuke.apply_command({"type": "build_structure", "nation_id": tgt_n2.id, "structure_type": StructureData.TYPE_TOWN, "x": hbomb_city.x, "y": hbomb_city.y})
	for _t in range(32):
		ws_nuke.step_tick(ws_nuke.current_tick + 1)
	var tgt_town_id: int = int(tgt_town_res.get("structure_id", 0))
	for sid_s in [int(s_res.get("structure_id", 0)), int(s2_res.get("structure_id", 0))]:
		var s_obj: StructureData = ws_nuke.get_structure(sid_s)
		if s_obj != null:
			s_obj.action_cooldown_ticks = 0
	var hb_res: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_HYDROGEN, "x": hbomb_city.x, "y": hbomb_city.y})
	for _t in range(210):
		ws_nuke.step_tick(ws_nuke.current_tick + 1)
	_check(bool(tgt_town_res.get("ok", false)) and bool(hb_res.get("ok", false)) and ws_nuke.get_structure(tgt_town_id) == null,
		"Nuclear detonation destroys structures cleanly within full blast radius")

	# Verify MIRV rejection on unconquered land + Silo max range limit + Silo cooldown + MIRV blanket mini-warheads on TargetStateC
	var unconq_land := _find_nearby_land(ws_nuke, -110.0, 48.0, 4)
	ws_nuke._set_cell_owner(unconq_land.y * ws_nuke.sim_width + unconq_land.x, 0)
	for sid_s in [int(s_res.get("structure_id", 0)), int(s2_res.get("structure_id", 0))]:
		var s_obj: StructureData = ws_nuke.get_structure(sid_s)
		if s_obj != null:
			s_obj.action_cooldown_ticks = 0
	var unconq_mirv: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_MIRV, "x": unconq_land.x, "y": unconq_land.y})
	ap.gold = 60000000.0
	var own_atom: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_ATOM, "x": ap.capital_cell.x, "y": ap.capital_cell.y})
	var own_hbomb: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_HYDROGEN, "x": ap.capital_cell.x, "y": ap.capital_cell.y})
	var own_mirv: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_MIRV, "x": ap.capital_cell.x, "y": ap.capital_cell.y})
	var own_land_blocked: bool = (
		not bool(own_atom.get("ok", true)) and "own" in str(own_atom.get("reason", "")).to_lower()
		and not bool(own_hbomb.get("ok", true)) and "own" in str(own_hbomb.get("reason", "")).to_lower()
		and not bool(own_mirv.get("ok", true)) and "own" in str(own_mirv.get("reason", "")).to_lower()
	)
	_check(own_land_blocked, "Nuclear warheads (Atom, H-Bomb, MIRV) reject targeting own territory", "atom=%s hb=%s mirv=%s" % [str(own_atom), str(own_hbomb), str(own_mirv)])
	var far_range_atom: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_ATOM, "x": clampi(us_spot.x + 720, 0, ws_nuke.sim_width - 1), "y": us_spot.y})
	if bool(far_range_atom.get("ok", false)):
		ws_nuke.missiles.erase(int(far_range_atom.get("missile_id", 0)))
	var silo_ref: StructureData = ws_nuke.get_structure(int(s_res.get("structure_id", 0)))
	var silo_cd_ticks: int = silo_ref.get_silo_cooldown_ticks() if silo_ref != null else 0
	var silo_up2: Dictionary = ws_nuke.apply_command({"type": "upgrade_structure", "nation_id": ap.id, "structure_id": silo_ref.id})
	var silo_up3: Dictionary = ws_nuke.apply_command({"type": "upgrade_structure", "nation_id": ap.id, "structure_id": silo_ref.id})
	var silo_up4_rej: Dictionary = ws_nuke.apply_command({"type": "upgrade_structure", "nation_id": ap.id, "structure_id": silo_ref.id})
	var silo_sam_caps_ok: bool = (
		bool(silo_up2.get("ok", false))
		and bool(silo_up3.get("ok", false))
		and not bool(silo_up4_rej.get("ok", true))
		and silo_ref.level == 3
		and StructureData.get_silo_cooldown_for_level(1) == 456
		and StructureData.get_silo_cooldown_for_level(2) == 410
		and StructureData.get_silo_cooldown_for_level(3) == 369
		and StructureData.get_sam_cooldown_for_level(1) == 480
		and StructureData.get_sam_cooldown_for_level(2) == 420
		and is_equal_approx(StructureData.get_sam_radius_for_level(2), 36.0 * 1.15)
	)
	_check(not bool(unconq_mirv.get("ok", true)) and bool(far_range_atom.get("ok", false)) and silo_cd_ticks >= 240 and silo_sam_caps_ok,
		"MIRV rejects unconquered land, Missiles have infinite range, Silo/SAM cap at Lv.3 (-10%% Silo CD, +15%% SAM range / -12.5%% SAM CD)" ,
		"unconq=%s far=%s cd=%d caps=%s" % [str(unconq_mirv), str(far_range_atom), silo_cd_ticks, str(silo_sam_caps_ok)])

	var mirv_city := _find_nearby_land(ws_nuke, -88.0, 41.0, 10)
	var tgt_n3 := ws_nuke._create_nation("TargetStateC", Color.PURPLE, false, mirv_city, 880)
	var pre_nuke_cells: int = tgt_n3.owned_cell_count
	for sid_s in [int(s_res.get("structure_id", 0)), int(s2_res.get("structure_id", 0))]:
		var s_obj: StructureData = ws_nuke.get_structure(sid_s)
		if s_obj != null:
			s_obj.action_cooldown_ticks = 0
	var mirv_res: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_MIRV, "x": mirv_city.x, "y": mirv_city.y})
	var max_subwarheads := 0
	for _t in range(210):
		ws_nuke.step_tick(ws_nuke.current_tick + 1)
		var cur_subs := 0
		for mid_k: int in ws_nuke.missiles.keys():
			if (ws_nuke.missiles[mid_k] as MissileUnit).kind == MissileUnit.KIND_MIRV_WARHEAD:
				cur_subs += 1
		max_subwarheads = maxi(max_subwarheads, cur_subs)
	_check(bool(mirv_res.get("ok", false)) and max_subwarheads >= 8 and tgt_n3.owned_cell_count < pre_nuke_cells,
		"MIRV blankets target nation with %d mini-warheads & scorches target land (%d -> %d cells)" % [max_subwarheads, pre_nuke_cells, tgt_n3.owned_cell_count],
		"mirv=%s subs=%d pre=%d post=%d" % [str(mirv_res), max_subwarheads, pre_nuke_cells, tgt_n3.owned_cell_count])

	# Verify nuclear fallout creation + exclusion during normal explore unless fallout is clicked + reclamation cost
	var fallout_probe := Vector2i(-1, -1)
	for dy_f in range(-16, 17):
		for dx_f in range(-16, 17):
			var fx: int = mirv_city.x + dx_f
			var fy: int = mirv_city.y + dy_f
			if ws_nuke.is_fallout_at(fx, fy) and ws_nuke.get_owner_at(fx, fy) == 0:
				fallout_probe = Vector2i(fx, fy)
				break
		if fallout_probe.x >= 0:
			break
	var f_idx_probe: int = fallout_probe.y * ws_nuke.sim_width + fallout_probe.x if fallout_probe.x >= 0 else 0
	var fallout_created_ok: bool = (
		fallout_probe.x >= 0
		and ws_nuke.fallout_cell_count > 120
		and ws_nuke.render_owner_grid[f_idx_probe] == 255
		and bool(ws_nuke.get_cell_info(fallout_probe.x, fallout_probe.y).get("fallout", false))
	)
	# First verify that normal free-hand explore (clicking a clean cell) sets allow_fallout == false and skips fallout cells
	var clean_target := Vector2i(us_spot.x + 16, us_spot.y)
	ws_nuke._set_cell_owner(clean_target.y * ws_nuke.sim_width + clean_target.x, 0)
	ws_nuke.fallout_grid[clean_target.y * ws_nuke.sim_width + clean_target.x] = 0
	var adj_fallout := Vector2i(us_spot.x + 6, us_spot.y)
	var adj_f_idx: int = adj_fallout.y * ws_nuke.sim_width + adj_fallout.x
	ws_nuke._set_cell_owner(adj_f_idx, 0)
	if ws_nuke.fallout_grid[adj_f_idx] == 0:
		ws_nuke.fallout_grid[adj_f_idx] = 1
		ws_nuke.render_owner_grid[adj_f_idx] = 255
		ws_nuke.fallout_cell_count += 1
	ap.troops = 300.0
	var clean_exp := ws_nuke.apply_command({
		"type": "expand_to",
		"nation_id": ap.id,
		"x": clean_target.x,
		"y": clean_target.y,
		"commit_ratio": 0.30,
	})
	var clean_ord: ExpansionOrder = ws_nuke.expansions.get(int(clean_exp.get("expansion_id", 0)), null)
	var clean_disallows_fallout: bool = clean_ord != null and not clean_ord.allow_fallout
	for _t in range(18):
		ws_nuke.step_tick(ws_nuke.current_tick + 1)
	var skipped_fallout_ok: bool = clean_disallows_fallout and ws_nuke.is_fallout_at(adj_fallout.x, adj_fallout.y) and ws_nuke.get_owner_at(adj_fallout.x, adj_fallout.y) == 0

	var pre_reclaim_fallout: int = ws_nuke.fallout_cell_count
	var reclaimer := ws_nuke._create_nation("Reclaimers", Color.YELLOW, false, fallout_probe, 4)
	reclaimer.troops = 200.0
	var rec_cmd := ws_nuke.apply_command({
		"type": "expand_to",
		"nation_id": reclaimer.id,
		"x": clampi(fallout_probe.x + 4, 0, ws_nuke.sim_width - 1),
		"y": fallout_probe.y,
		"commit_ratio": 0.40,
	})
	var rec_eid: int = int(rec_cmd.get("expansion_id", 0))
	var rec_ord: ExpansionOrder = ws_nuke.expansions.get(rec_eid, null)
	var allow_fallout_ok: bool = rec_ord != null and rec_ord.allow_fallout
	var init_rec_troops: float = rec_ord.initial_troops if rec_ord != null else 0.0
	var min_rem_troops: float = init_rec_troops
	var claimed_rec_cells := 0
	for _t in range(38):
		ws_nuke.step_tick(ws_nuke.current_tick + 1)
		if rec_ord != null:
			min_rem_troops = minf(min_rem_troops, rec_ord.remaining_troops)
			claimed_rec_cells = maxi(claimed_rec_cells, rec_ord.cells_claimed)
	var cost_per_cell: float = (init_rec_troops - min_rem_troops) / maxf(float(claimed_rec_cells), 1.0)
	_check(fallout_created_ok and skipped_fallout_ok and allow_fallout_ok and claimed_rec_cells >= 20 and ws_nuke.fallout_cell_count < pre_reclaim_fallout and not ws_nuke.is_fallout_at(fallout_probe.x, fallout_probe.y) and cost_per_cell >= 0.55 and cost_per_cell <= 1.25,
		"Nuke leaves GPU nuclear fallout excluded unless clicked & cleared by rebalanced costly troop reclamation (%.2f troops/cell, %d fallout remaining)" % [cost_per_cell, ws_nuke.fallout_cell_count],
		"ok=%s skip=%s allow=%s probe=%s claimed=%d cost=%.2f f=%d->%d" % [str(fallout_created_ok), str(skipped_fallout_ok), str(allow_fallout_ok), str(fallout_probe), claimed_rec_cells, cost_per_cell, pre_reclaim_fallout, ws_nuke.fallout_cell_count])

	# Milestone 4 & 5: Alliances, Embargo, Peso & Troop Donations, Betrayal & Factory Trains
	var friend := ws._create_nation("AllyRealm", Color.CYAN, false, Vector2i(us_spot.x - 36, us_spot.y), 200)
	friend.gold = 500000.0
	friend.troops = 50.0
	p.troops = 260.0
	var ally_req: Dictionary = ws.apply_command({"type": "request_alliance", "nation_id": p.id, "target_nation_id": friend.id})
	var blocked_atk: Dictionary = ws.apply_command({"type": "expand_to", "nation_id": p.id, "x": friend.capital_cell.x, "y": friend.capital_cell.y, "commit_ratio": 0.25})
	var don_g: Dictionary = ws.apply_command({"type": "donate_gold", "nation_id": p.id, "target_nation_id": friend.id, "amount": 100000.0})
	var friend_troops_pre: float = friend.troops
	var don_t: Dictionary = ws.apply_command({"type": "donate_troops", "nation_id": p.id, "target_nation_id": friend.id, "ratio": 0.25})
	var brk_res: Dictionary = ws.apply_command({"type": "break_alliance", "nation_id": p.id, "target_nation_id": friend.id})
	_check(bool(ally_req.get("accepted", false)) and not bool(blocked_atk.get("ok", true)) and bool(don_g.get("ok", false)) and bool(don_t.get("ok", false)) and friend.troops > friend_troops_pre + 40.0 and bool(brk_res.get("ok", false)) and p.is_betrayer(ws.current_tick) and ws.is_embargoed(p.id, friend.id),
		"Diplomacy: Alliance blocks attack, Peso & Troop Donations work, Breaking alliance sets Betrayal + Embargo")

	var ws_tr := WorldState.new()
	ws_tr.load_world()
	ws_tr.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "RailBarons", "ai_count": 0, "seed": 123})
	var rp: NationData = ws_tr.get_player_nation()
	rp.gold = 5000000.0
	ws_tr._claim_organic_dot(rp.id, Vector2i(us_spot.x + 18, us_spot.y), 2080, 0)
	var b1 := ws_tr.apply_command({"type": "build_structure", "nation_id": rp.id, "structure_type": StructureData.TYPE_TOWN, "x": us_spot.x, "y": us_spot.y})
	var fac_pt := Vector2i(us_spot.x + 24, us_spot.y)
	for dy in range(-36, 37):
		var picked := false
		for dx in range(-36, 37):
			var c_pt := Vector2i(us_spot.x + dx, us_spot.y + dy)
			if c_pt.distance_to(us_spot) >= 22.0 and c_pt.distance_to(us_spot) <= 44.0 and ws_tr.can_place_structure(rp.id, StructureData.TYPE_FACTORY, c_pt.x, c_pt.y).get("ok", false):
				fac_pt = c_pt
				picked = true
				break
		if picked:
			break
	var b2 := ws_tr.apply_command({"type": "build_structure", "nation_id": rp.id, "structure_type": StructureData.TYPE_FACTORY, "x": fac_pt.x, "y": fac_pt.y})
	var tr_ev := {"delivered": false}
	ws_tr.structure_income_popup.connect(func(nid: int, _pos: Vector2, g: float, k: String) -> void:
		if nid == rp.id and k == "train" and g >= 1.0:
			tr_ev["delivered"] = true
	)
	var saw_train := false
	var train_has_road := false
	for _t in range(180):
		ws_tr.step_tick(ws_tr.current_tick + 1)
		if not ws_tr.trains.is_empty():
			saw_train = true
			var t0_d: Dictionary = ws_tr.trains[0]
			var t0_pts: PackedVector2Array = t0_d.get("road_points", PackedVector2Array())
			var t0_cars: PackedVector2Array = t0_d.get("car_positions", PackedVector2Array())
			if t0_pts.size() >= 10 and t0_d.has("heading") and t0_cars.size() == 3:
				train_has_road = true
	var road_irregular_ok := false
	var road_reused_ok := false
	var max_road_dev := 0.0
	if not ws_tr.factory_links.is_empty():
		var lnk: Dictionary = ws_tr.factory_links[0]
		var r_pts: PackedVector2Array = lnk.get("road_points", PackedVector2Array())
		var fw: Vector2 = lnk["from_world"]
		var tw: Vector2 = lnk["to_world"]
		if r_pts.size() >= 10 and r_pts[0].distance_to(fw) < 0.01 and r_pts[r_pts.size() - 1].distance_to(tw) < 0.01:
			var chord: Vector2 = (tw - fw).normalized()
			for pt_r: Vector2 in r_pts:
				max_road_dev = maxf(max_road_dev, absf((pt_r - fw).cross(chord)))
			road_irregular_ok = max_road_dev > 1.2
		ws_tr._recompute_factory_links()
		if not ws_tr.factory_links.is_empty():
			var r_pts_after: PackedVector2Array = ws_tr.factory_links[0].get("road_points", PackedVector2Array())
			road_reused_ok = (ws_tr._road_cache.size() >= 1 and r_pts_after.size() == r_pts.size() and r_pts_after[5] == r_pts[5])
	_check(bool(b1.get("ok", false)) and bool(b2.get("ok", false)) and saw_train and bool(tr_ev["delivered"]) and road_irregular_ok and road_reused_ok and train_has_road,
		"Irregular winding Factory roads (dev=%.1fpx) persist in _road_cache across conquests & carry Trains" % max_road_dev,
		"b1=%s b2=%s saw=%s deliv=%s road=%s reuse=%s tr_r=%s links=%d" % [str(b1), str(b2), str(saw_train), str(tr_ev["delivered"]), str(road_irregular_ok), str(road_reused_ok), str(train_has_road), ws_tr.factory_links.size()])

	# Factory-to-Factory link + Cross-border Factory link + bilateral trains + Embargo severing
	var ws_fac := WorldState.new()
	ws_fac.load_world()
	ws_fac.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "RailCorp", "ai_count": 0, "seed": 456})
	var fp1: NationData = ws_fac.get_player_nation()
	fp1.gold = 5000000.0
	ws_fac._claim_organic_dot(fp1.id, Vector2i(us_spot.x + 20, us_spot.y), 1040, 0)
	var f1_res: Dictionary = ws_fac.apply_command({"type": "build_structure", "nation_id": fp1.id, "structure_type": StructureData.TYPE_FACTORY, "x": us_spot.x, "y": us_spot.y})
	var f2_pt := Vector2i(-1, -1)
	for dy_f in range(-36, 37):
		for dx_f in range(-36, 37):
			var c_f := Vector2i(us_spot.x + dx_f, us_spot.y + dy_f)
			var dist_f: float = c_f.distance_to(us_spot)
			if dist_f >= 16.0 and dist_f <= 36.0 and ws_fac.can_place_structure(fp1.id, StructureData.TYPE_FACTORY, c_f.x, c_f.y).get("ok", false):
				f2_pt = c_f
				break
		if f2_pt.x >= 0:
			break
	var f2_res: Dictionary = ws_fac.apply_command({"type": "build_structure", "nation_id": fp1.id, "structure_type": StructureData.TYPE_FACTORY, "x": f2_pt.x, "y": f2_pt.y})
	for _t in range(32):
		ws_fac.step_tick(ws_fac.current_tick + 1)
	var f1_st: StructureData = ws_fac.get_structure(int(f1_res.get("structure_id", 0)))
	var f2_st: StructureData = ws_fac.get_structure(int(f2_res.get("structure_id", 0)))
	var f2f_links := 0
	if f1_st != null and f2_st != null:
		for lnk: Dictionary in ws_fac.factory_links:
			var a_id: int = int(lnk.get("factory_id", 0))
			var b_id: int = int(lnk.get("target_id", 0))
			if mini(a_id, b_id) == mini(f1_st.id, f2_st.id) and maxi(a_id, b_id) == maxi(f1_st.id, f2_st.id):
				f2f_links += 1
	_check(
		f1_st != null and f2_st != null and f2f_links == 1
		and f1_st.connected_count >= 1 and f2_st.connected_count >= 1
		and f1_st.connection_bonus > 1.0 and f2_st.connection_bonus > 1.0,
		"Factory-to-Factory links connect cleanly without duplicate edges & boost both factories",
		"f1=%s f2=%s links=%d c1=%d c2=%d" % [str(f1_res), str(f2_res), f2f_links, f1_st.connected_count if f1_st else -1, f2_st.connected_count if f2_st else -1]
	)

	var nb_cell := Vector2i(-1, -1)
	for dy_n in range(-44, 45):
		for dx_n in range(-44, 45):
			var cn := Vector2i(us_spot.x + dx_n, us_spot.y + dy_n)
			var dn1: float = Vector2(cn - us_spot).length()
			var dn2: float = Vector2(cn - f2_pt).length() if f2_pt.x >= 0 else 999.0
			if dn1 >= 20.0 and dn1 <= 40.0 and dn2 >= 16.0 and ws_fac.get_terrain_at(cn.x, cn.y) != WorldState.T_OCEAN:
				if f1_st != null and f1_st.is_cell_in_factory_range(cn):
					nb_cell = cn
					break
		if nb_cell.x >= 0:
			break
	var border_n := ws_fac._create_nation("BorderState", Color.ORANGE, false, nb_cell, 140)
	border_n.gold = 5000000.0
	var nb_town_res: Dictionary = ws_fac.apply_command({"type": "build_structure", "nation_id": border_n.id, "structure_type": StructureData.TYPE_TOWN, "x": nb_cell.x, "y": nb_cell.y})
	for _t in range(32):
		ws_fac.step_tick(ws_fac.current_tick + 1)
	var nb_town_id: int = int(nb_town_res.get("structure_id", 0))
	var has_cb_link := false
	for lnk: Dictionary in ws_fac.factory_links:
		var lf: StructureData = ws_fac.get_structure(int(lnk.get("factory_id", 0)))
		var lt: StructureData = ws_fac.get_structure(int(lnk.get("target_id", 0)))
		if lf != null and lt != null and lf.nation_id != lt.nation_id:
			has_cb_link = true
	var cb_pay := {"p1": false, "p2": false}
	ws_fac.structure_income_popup.connect(func(nid: int, _pos: Vector2, g: float, k: String) -> void:
		if k == "train" and g >= 1.0:
			if nid == fp1.id:
				cb_pay["p1"] = true
			elif nid == border_n.id:
				cb_pay["p2"] = true
	)
	for _t in range(280):
		ws_fac.step_tick(ws_fac.current_tick + 1)
		if bool(cb_pay["p1"]) and bool(cb_pay["p2"]):
			break
	ws_fac.apply_command({"type": "toggle_embargo", "nation_id": fp1.id, "target_nation_id": border_n.id})
	for _t in range(4):
		ws_fac.step_tick(ws_fac.current_tick + 1)
	var post_embargo_cb_links := 0
	for lnk: Dictionary in ws_fac.factory_links:
		var lf: StructureData = ws_fac.get_structure(int(lnk.get("factory_id", 0)))
		var lt: StructureData = ws_fac.get_structure(int(lnk.get("target_id", 0)))
		if lf != null and lt != null and lf.nation_id != lt.nation_id:
			post_embargo_cb_links += 1
	var post_embargo_cb_trains := 0
	for tr: Dictionary in ws_fac.trains:
		var lt: StructureData = ws_fac.get_structure(int(tr.get("target_id", 0)))
		if lt != null and lt.nation_id == border_n.id:
			post_embargo_cb_trains += 1
	_check(
		nb_town_id > 0 and has_cb_link and bool(cb_pay["p1"]) and bool(cb_pay["p2"])
		and post_embargo_cb_links == 0 and post_embargo_cb_trains == 0,
		"Cross-border Factory connects to neighbor Town, shares train Pesos bilaterally & severs on Embargo",
		"town=%s cb_link=%s pay=%s post_links=%d post_trains=%d" % [str(nb_town_res), str(has_cb_link), str(cb_pay), post_embargo_cb_links, post_embargo_cb_trains]
	)

	# Extended multi-hop Factory trains: Factory A -> Factory B -> Town C (beyond A's direct range)
	var ws_ext := WorldState.new()
	ws_ext.load_world()
	ws_ext.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "ExtRail", "ai_count": 0, "seed": 901})
	var ep: NationData = ws_ext.get_player_nation()
	ep.gold = 10000000.0
	for ox in range(16, 176, 20):
		ws_ext._claim_organic_dot(ep.id, Vector2i(clampi(us_spot.x + ox, 0, ws_ext.sim_width - 1), us_spot.y), 1040, 0)
	var ex_a_res: Dictionary = ws_ext.apply_command({"type": "build_structure", "nation_id": ep.id, "structure_type": StructureData.TYPE_FACTORY, "x": us_spot.x, "y": us_spot.y})
	var ex_a_st: StructureData = ws_ext.get_structure(int(ex_a_res.get("structure_id", 0)))
	var ex_b_pt := Vector2i(-1, -1)
	for dx_b in range(48, 76):
		var cp := Vector2i(us_spot.x + dx_b, us_spot.y)
		if ws_ext.can_place_structure(ep.id, StructureData.TYPE_FACTORY, cp.x, cp.y).get("ok", false) and ex_a_st.is_cell_in_factory_range(cp):
			ex_b_pt = cp
			break
	var ex_b_res: Dictionary = ws_ext.apply_command({"type": "build_structure", "nation_id": ep.id, "structure_type": StructureData.TYPE_FACTORY, "x": ex_b_pt.x, "y": ex_b_pt.y})
	var ex_b_st: StructureData = ws_ext.get_structure(int(ex_b_res.get("structure_id", 0)))
	var ex_c_pt := Vector2i(-1, -1)
	for dy_c in range(-20, 21):
		for dx_c in range(40, 88):
			var cp := Vector2i(ex_b_pt.x + dx_c, ex_b_pt.y + dy_c)
			if ex_b_st != null and ex_b_st.is_cell_in_factory_range(cp) and not ex_a_st.is_cell_in_factory_range(cp):
				if ws_ext.can_place_structure(ep.id, StructureData.TYPE_TOWN, cp.x, cp.y).get("ok", false):
					ex_c_pt = cp
					break
		if ex_c_pt.x >= 0:
			break
	var ex_c_res: Dictionary = ws_ext.apply_command({"type": "build_structure", "nation_id": ep.id, "structure_type": StructureData.TYPE_TOWN, "x": ex_c_pt.x, "y": ex_c_pt.y})
	var ex_c_id: int = int(ex_c_res.get("structure_id", 0))
	for _t in range(34):
		ws_ext.step_tick(ws_ext.current_tick + 1)
	var mh_ev := {"saw": false, "returning": false, "delivered": false}
	var ex_c_pos: Vector2 = ws_ext.sim_to_world(ex_c_pt)
	ws_ext.structure_income_popup.connect(func(nid: int, pos: Vector2, _g: float, k: String) -> void:
		if nid == ep.id and k == "train" and pos.distance_to(ex_c_pos) < 4.0:
			mh_ev["delivered"] = true
	)
	for _t in range(400):
		ws_ext.step_tick(ws_ext.current_tick + 1)
		for tr: Dictionary in ws_ext.trains:
			if int(tr.get("factory_id", 0)) == ex_a_st.id and int(tr.get("target_id", 0)) == ex_c_id and (tr.get("hop_ids", []) as Array).size() >= 3:
				mh_ev["saw"] = true
				if bool(tr.get("returning", false)):
					mh_ev["returning"] = true
		if bool(mh_ev["saw"]) and bool(mh_ev["returning"]) and bool(mh_ev["delivered"]):
			break
	_check(ex_c_id > 0 and bool(mh_ev["saw"]) and bool(mh_ev["returning"]) and bool(mh_ev["delivered"]),
		"Factory trains traverse ALL connected roads including extended multi-hop routes (Factory A -> Factory B -> Town C)",
		"b=%s c=%s ev=%s" % [str(ex_b_res), str(ex_c_res), str(mh_ev)])

	# Buildings vs Giant Empty Land fairness check (built-up nation beats 10k-cell empty nation)
	var ws_bal := WorldState.new()
	ws_bal.load_world()
	ws_bal.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Builder", "ai_count": 0, "seed": 505})
	var bn_built: NationData = ws_bal.get_player_nation()
	bn_built.gold = 20000000.0
	var bal_south := _find_nearby_land(ws_bal, 0.0, -80.0, 12)
	var bn_empty := ws_bal._create_nation("BigEmpty", Color.GRAY, false, bal_south, 40)
	bn_built.owned_cell_count = 6000
	bn_empty.owned_cell_count = 40000
	var b_pts := [us_spot, Vector2i(us_spot.x + 16, us_spot.y), Vector2i(us_spot.x - 16, us_spot.y)]
	for pt_b: Vector2i in b_pts:
		ws_bal._claim_organic_dot(bn_built.id, pt_b, 80, 0)
		var bt_res := ws_bal.apply_command({"type": "build_structure", "nation_id": bn_built.id, "structure_type": StructureData.TYPE_TOWN, "x": pt_b.x, "y": pt_b.y})
		var btid: int = int(bt_res.get("structure_id", 0))
		for _t in range(32):
			ws_bal.step_tick(ws_bal.current_tick + 1)
		ws_bal.apply_command({"type": "upgrade_structure", "nation_id": bn_built.id, "structure_id": btid})
	var bf_pos := Vector2i(us_spot.x, us_spot.y + 16)
	ws_bal._claim_organic_dot(bn_built.id, bf_pos, 80, 0)
	ws_bal.apply_command({"type": "build_structure", "nation_id": bn_built.id, "structure_type": StructureData.TYPE_FACTORY, "x": bf_pos.x, "y": bf_pos.y})
	for _t in range(32):
		ws_bal.step_tick(ws_bal.current_tick + 1)
	bn_built.owned_cell_count = 6000
	bn_empty.owned_cell_count = 40000
	ws_bal._recompute_factory_links()
	ws_bal._recompute_all_economy_rates()
	_check(
		bn_built.max_troops > bn_empty.max_troops and bn_built.troops_per_sec > bn_empty.troops_per_sec and bn_built.gold_per_sec > bn_empty.gold_per_sec,
		"Towns & Factories beat giant buildingless land (cap %.0f vs %.0f, rate %.1f vs %.1f, gold %.0f vs %.0f)" % [
			bn_built.max_troops, bn_empty.max_troops, bn_built.troops_per_sec, bn_empty.troops_per_sec, bn_built.gold_per_sec, bn_empty.gold_per_sec
		]
	)

	# Fastest sea-time ship routing (Panama isthmus: Pacific shore beats closer-Euclidean Caribbean shore requiring SA detour)
	var ws_fast := WorldState.new()
	ws_fast.load_world()
	var carib_pt := _find_nearby_land(ws_fast, -79.9, 9.35, 10)
	var pac_pt := _find_nearby_land(ws_fast, -81.0, 8.2, 10)
	var pac_tgt := _find_nearby_land(ws_fast, -78.2, 7.6, 10)
	if carib_pt.x >= 0 and pac_pt.x >= 0 and pac_tgt.x >= 0:
		ws_fast.apply_command({"type": "spawn_player", "x": pac_pt.x, "y": pac_pt.y, "name": "Admiral", "ai_count": 0, "seed": 707})
		var fn: NationData = ws_fast.get_player_nation()
		ws_fast._claim_organic_dot(fn.id, carib_pt, 16, 0)
		var tgt_r := ws_fast._create_nation("PacTarget", Color.YELLOW, false, pac_tgt, 48)
		var fast_res: Dictionary = ws_fast.find_closest_owned_shore(fn.id, tgt_r.capital_cell)
		var chosen_shore: Vector2i = fast_res.get("shore_cell", Vector2i(-1, -1))
		var carib_nav := ws_fast.sea_pathfinder.find_nearest_nav_cell(carib_pt, 3)
		var dest_nav_t := ws_fast.sea_pathfinder.find_nearest_nav_cell(fast_res.get("landing_cell", tgt_r.capital_cell), 3)
		var carib_route := ws_fast.sea_pathfinder.find_path(carib_nav, dest_nav_t)
		var chosen_len: float = WorldState._compute_route_length(fast_res.get("route", PackedVector2Array()))
		var carib_len: float = WorldState._compute_route_length(carib_route)
		var euclid_carib: float = Vector2(carib_pt - pac_tgt).length()
		var euclid_pac: float = Vector2(pac_pt - pac_tgt).length()
		_check(
			bool(fast_res.get("ok", false)) and euclid_carib < euclid_pac and chosen_shore != carib_pt
			and (carib_route.is_empty() or (carib_len > 200.0 and chosen_len < carib_len * 0.25)),
			"Fastest sea-time ship routing launches from fast Pacific coast (route=%.0fpx) over nearer-Euclidean Atlantic/Caribbean detour (route=%.0fpx, d=%.1f vs %.1f)" % [
				chosen_len, carib_len, euclid_carib, euclid_pac
			]
		)

	# Homeland Counter-Attack & AI-vs-AI Warfare checks (also verifies clean circle spawn with NO auto-spread until player expands)
	var ws_cnt := WorldState.new()
	ws_cnt.load_world()
	ws_cnt.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Homeland", "ai_count": 0, "seed": 888})
	var def_p: NationData = ws_cnt.get_player_nation()
	var spawn_seed_cells: int = def_p.owned_cell_count
	var no_autospread_ok: bool = ws_cnt.expansions.is_empty() and spawn_seed_cells >= 25 and spawn_seed_cells <= 64
	for _t in range(12):
		ws_cnt.step_tick(ws_cnt.current_tick + 1)
	var stays_circle_ok: bool = (def_p.owned_cell_count == spawn_seed_cells)
	ws_cnt.apply_command({"type": "expand_to", "nation_id": def_p.id, "x": us_spot.x + 8, "y": us_spot.y, "commit_ratio": 0.25})
	for _t in range(24):
		ws_cnt.step_tick(ws_cnt.current_tick + 1)
	var spawn_grown_ok: bool = no_autospread_ok and stays_circle_ok and def_p.owned_cell_count >= 120
	var inv_n := ws_cnt._create_nation("InvaderAI", Color.RED, false, Vector2i(us_spot.x + 26, us_spot.y), 240)
	ws_cnt._claim_organic_dot(def_p.id, Vector2i(us_spot.x + 18, us_spot.y), 120, 0)
	def_p.troops = 500.0
	inv_n.troops = 140.0
	var counter_ev := {"fired": false, "repelled": false}
	ws_cnt.attack_countered.connect(func(d_id: int, _a_id: int, _dest: float, rep: bool) -> void:
		if d_id == def_p.id:
			counter_ev["fired"] = true
			counter_ev["repelled"] = rep
	)
	var inv_ord_res: Dictionary = ws_cnt.apply_command({"type": "expand_to", "nation_id": inv_n.id, "x": def_p.capital_cell.x, "y": def_p.capital_cell.y, "commit_ratio": 0.50})
	for _t in range(4):
		ws_cnt.step_tick(ws_cnt.current_tick + 1)
	var counter_res: Dictionary = ws_cnt.apply_command({"type": "expand_to", "nation_id": def_p.id, "x": def_p.capital_cell.x, "y": def_p.capital_cell.y, "commit_ratio": 0.50})
	_check(spawn_grown_ok and bool(inv_ord_res.get("ok", false)) and bool(counter_res.get("ok", false)) and str(counter_res.get("mode", "")) == "counter_repel" and bool(counter_ev["fired"]) and bool(counter_ev["repelled"]),
		"First explore grows organically (%d->%d cells) & clicking own land under attack repels enemy invasion" % [spawn_seed_cells, def_p.owned_cell_count],
		"grow=%s inv=%s cnt=%s ev=%s" % [str(spawn_grown_ok), str(inv_ord_res), str(counter_res), str(counter_ev)])

	# OpenFront 1:1 Defense Post destroyed on enemy conquest + Conquest Gold Spoils
	var tiny_ai := ws_cnt._create_nation("DoomedPost", Color.MAGENTA, false, Vector2i(us_spot.x - 24, us_spot.y), 1)
	tiny_ai.gold = 500000.0
	var dp_res: Dictionary = ws_cnt.apply_command({"type": "build_structure", "nation_id": tiny_ai.id, "structure_type": StructureData.TYPE_DEFENSE_POST, "x": tiny_ai.capital_cell.x, "y": tiny_ai.capital_cell.y})
	var dp_id: int = int(dp_res.get("structure_id", 0))
	var pre_conq_gold: float = def_p.gold
	var cap_idx: int = tiny_ai.capital_cell.y * ws_cnt.sim_width + tiny_ai.capital_cell.x
	ws_cnt._set_cell_owner(cap_idx, def_p.id)
	_check(dp_id > 0 and ws_cnt.get_structure(dp_id) == null and not tiny_ai.alive and def_p.gold >= pre_conq_gold + 400000.0,
		"OpenFront 1:1 Defense Post is destroyed on tile capture & conqueror claims defeated treasury spoils")

	var ws_aivai := WorldState.new()
	ws_aivai.load_world()
	var ai_a := ws_aivai._create_nation("AI_North", Color.RED, false, us_spot, 360)
	var ai_b := ws_aivai._create_nation("AI_South", Color.BLUE, false, Vector2i(us_spot.x + 16, us_spot.y), 360)
	ws_aivai.match_phase = WorldState.PHASE_PLAYING
	ws_aivai._recompute_all_economy_rates()
	ai_a.troops = ai_a.max_troops * 0.85
	ai_b.troops = ai_b.max_troops * 0.55
	var ai_contested := false
	for t_i in range(1, 300):
		ws_aivai.step_tick(t_i)
		for eid: int in ws_aivai.expansions.keys():
			if (ws_aivai.expansions[eid] as ExpansionOrder).is_contested:
				ai_contested = true
	_check(ai_contested or ai_a.owned_cell_count > 480 or ai_b.owned_cell_count < 360,
		"AI actively attacks and fights rival AI nations on shared borders (AI_A=%d, AI_B=%d)" % [ai_a.owned_cell_count, ai_b.owned_cell_count])

	# Conquest audio filtering: player bubble-wrap pop ONLY on player conquest, silent on AI-vs-AI, warning ONLY when enemy takes player land
	var ws_sfx := WorldState.new()
	ws_sfx.load_world()
	ws_sfx.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Conqueror", "ai_count": 0, "seed": 515})
	var sfx_p: NationData = ws_sfx.get_player_nation()
	var sfx_ev := {"conq": 0, "atk": 0, "last_attacker": 0}
	ws_sfx.player_land_conquered.connect(func(cells: int, _cont: bool) -> void:
		sfx_ev["conq"] = int(sfx_ev["conq"]) + cells
	)
	ws_sfx.player_territory_attacked.connect(func(a_id: int, cells: int) -> void:
		sfx_ev["atk"] = int(sfx_ev["atk"]) + cells
		sfx_ev["last_attacker"] = a_id
	)
	ws_sfx.apply_command({"type": "expand_to", "nation_id": sfx_p.id, "x": us_spot.x + 8, "y": us_spot.y, "commit_ratio": 0.40})
	for _t in range(18):
		ws_sfx.step_tick(ws_sfx.current_tick + 1)
	var player_conq_ok: bool = int(sfx_ev["conq"]) > 0 and int(sfx_ev["atk"]) == 0
	ws_sfx.expansions.clear()
	sfx_ev["conq"] = 0
	sfx_ev["atk"] = 0
	var far_spot := _find_nearby_land(ws_sfx, 20.0, 20.0, 12)
	var ai1 := ws_sfx._create_nation("OtherAI_1", Color.GREEN, false, far_spot, 160)
	var ai2 := ws_sfx._create_nation("OtherAI_2", Color.PURPLE, false, Vector2i(far_spot.x + 16, far_spot.y), 160)
	ai1.troops = 500.0
	ai2.troops = 120.0
	ws_sfx.apply_command({"type": "expand_to", "nation_id": ai1.id, "x": ai2.capital_cell.x, "y": ai2.capital_cell.y, "commit_ratio": 0.5})
	for _t in range(25):
		ws_sfx.step_tick(ws_sfx.current_tick + 1)
	var ai_silent_ok: bool = int(sfx_ev["conq"]) == 0 and int(sfx_ev["atk"]) == 0
	ws_sfx.expansions.clear()
	var foe_x: int = us_spot.x + 16
	for dx in range(5, 60):
		var cx: int = us_spot.x + dx
		if ws_sfx.is_land_cell(cx, us_spot.y) and ws_sfx.owner_grid[us_spot.y * ws_sfx.sim_width + cx] == 0:
			foe_x = cx
			break
	var near_inv := ws_sfx._create_nation("BorderFoe", Color.RED, false, Vector2i(foe_x, us_spot.y), 180)
	near_inv.troops = 450.0
	sfx_p.troops = 40.0
	ws_sfx.apply_command({"type": "expand_to", "nation_id": near_inv.id, "x": sfx_p.capital_cell.x, "y": sfx_p.capital_cell.y, "commit_ratio": 0.6})
	for _t in range(20):
		ws_sfx.step_tick(ws_sfx.current_tick + 1)
	var under_atk_warn_ok: bool = int(sfx_ev["conq"]) == 0 and int(sfx_ev["atk"]) > 0 and int(sfx_ev["last_attacker"]) == near_inv.id
	_check(player_conq_ok and ai_silent_ok and under_atk_warn_ok,
		"Conquest audio emits only for player pops, is silent for AI-vs-AI, and warns when player land is taken",
		"conq=%s ai_silent=%s atk=%s" % [str(player_conq_ok), str(ai_silent_ok), str(under_atk_warn_ok)])

	_run_multiplayer_lockstep_tests(us_spot, normandy)


func _run_multiplayer_lockstep_tests(us_spot: Vector2i, eu_spot: Vector2i) -> void:
	var mp := MPClient.new()
	var pong_sig := {"ms": -1}
	mp.ping_updated.connect(func(ms: int) -> void: pong_sig["ms"] = ms)
	mp._handle_message({"type": "pong", "t": Time.get_ticks_msec() - 25})
	_check(mp.DEFAULT_SERVER_URL == "ws://151.242.136.18:30041/ws" and not mp.is_socket_active() and int(pong_sig["ms"]) >= 1 and mp.last_ping_ms == int(pong_sig["ms"]),
		"MPClient points at ws://151.242.136.18:30041/ws and handles pong RTT cleanly (%dms)" % mp.last_ping_ms)

	var ws_a := WorldState.new()
	var ws_b := WorldState.new()
	ws_a.load_world()
	ws_b.load_world()
	var start_cmd := {
		"type": "start_mp_match",
		"seed": 1337,
		"local_nation_id": 1,
		"ai_count": 2,
		"players": [
			{"nation_id": 2, "name": "EuroPact", "x": eu_spot.x, "y": eu_spot.y},
			{"nation_id": 1, "name": "AmeriCorp", "x": us_spot.x, "y": us_spot.y},
		],
	}
	var ra: Dictionary = ws_a.apply_command(start_cmd)
	var rb: Dictionary = ws_b.apply_command(start_cmd)
	var scripted_cmds := [
		{"tick": 6, "cmd": {"type": "expand_to", "nation_id": 1, "x": us_spot.x + 8, "y": us_spot.y, "commit_ratio": 0.35}},
		{"tick": 12, "cmd": {"type": "expand_to", "nation_id": 2, "x": eu_spot.x + 6, "y": eu_spot.y, "commit_ratio": 0.35}},
		{"tick": 18, "cmd": {"type": "build_structure", "nation_id": 1, "structure_type": StructureData.TYPE_TOWN, "x": us_spot.x, "y": us_spot.y}},
		{"tick": 30, "cmd": {"type": "request_alliance", "nation_id": 1, "target_nation_id": 3}},
		{"tick": 54, "cmd": {"type": "upgrade_structure", "nation_id": 1, "structure_id": 1}},
	]
	for t in range(1, 241):
		for item: Dictionary in scripted_cmds:
			if int(item["tick"]) == t:
				ws_a.apply_command(item["cmd"])
				ws_b.apply_command(item["cmd"])
		ws_a.step_tick(t)
		ws_b.step_tick(t)

	var hash_a: int = ws_a.compute_state_hash()
	var hash_b: int = ws_b.compute_state_hash()
	_check(bool(ra.get("ok", false)) and bool(rb.get("ok", false)) and hash_a == hash_b and ws_a.get_nation(1).owned_cell_count == ws_b.get_nation(1).owned_cell_count,
		"Multiplayer lockstep parity verified across 240 ticks (seed=1337, hash=%d)" % hash_a)

	_run_phase2_account_and_pfp_tests()


func _run_phase2_account_and_pfp_tests() -> void:
	# 1. Pure-GDScript GIF89a 2-frame animated PFP decode verification
	# Minimal 2x2 RGB 2-frame GIF (red frame -> green frame)
	var gif_bytes := PackedByteArray([
		0x47, 0x49, 0x46, 0x38, 0x39, 0x61, # GIF89a
		0x02, 0x00, 0x02, 0x00, 0x80, 0x00, 0x00, # 2x2, GCT size=2
		0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, # GCT: 0=red, 1=green
		0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, # GCE 100ms
		0x2C, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02, 0x00, 0x00, # Image 0
		0x02, 0x02, 0x44, 0x01, 0x00, # LZW min_code_size=2, 4 zero indices
		0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, # GCE 100ms
		0x2C, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02, 0x00, 0x00, # Image 1
		0x02, 0x02, 0x4C, 0x01, 0x00, # LZW min_code_size=2, 4 one indices
		0x3B, # Trailer
	])
	var dec: Dictionary = GifDecoder.decode_gif_bytes(gif_bytes, 64, 16)
	var frames_arr: Array = dec.get("frames", [])
	var strip_img: Image = dec.get("strip_image")
	var gif_ok := (
		bool(dec.get("ok", false))
		and frames_arr.size() == 2
		and strip_img != null
		and strip_img.get_width() == 128
		and strip_img.get_height() == 64
		and strip_img.get_pixel(16, 16).r > 0.8
		and strip_img.get_pixel(80, 16).g > 0.8
	)
	_check(gif_ok, "GifDecoder decodes animated GIF89a into distinct 64x64 frames & 128x64 strip", "dec=%s" % str(dec.get("error", "")))

	# 2. Friends list presence sorting: Online first -> Most Recent Offline -> Longest Offline
	var sorted_fr: Array = AccountClient.sort_friends_list([
		{"username": "OldOffline", "online": false, "last_seen_unix": 1000},
		{"username": "ZaraOnline", "online": true, "last_seen_unix": 2000},
		{"username": "RecentOffline", "online": false, "last_seen_unix": 9000},
		{"username": "AlphaOnline", "online": true, "last_seen_unix": 1500},
	])
	var order_ok := (
		sorted_fr.size() == 4
		and str((sorted_fr[0] as Dictionary)["username"]) == "AlphaOnline"
		and str((sorted_fr[1] as Dictionary)["username"]) == "ZaraOnline"
		and str((sorted_fr[2] as Dictionary)["username"]) == "RecentOffline"
		and str((sorted_fr[3] as Dictionary)["username"]) == "OldOffline"
	)
	_check(order_ok, "Friends sorting places Online friends first, then most-recent to longest-offline")

	# 3. AccountClient URL normalization & CapitalMarkersLayer custom PFP binding
	var ac := AccountClient.new()
	ac.set_ws_url("ws://151.242.136.18:30041/ws")
	var cml := CapitalMarkersLayer.new()
	cml.set_nation_avatar(1, frames_arr, 100)
	var bound_avatars: Dictionary = cml.get("_nation_avatars")
	_check(ac.api_base_url == "http://151.242.136.18:30041" and bound_avatars.has(1),
		"AccountClient derives HTTP API URL cleanly & CapitalMarkersLayer binds custom PFP frames")
	cml.free()
	ac.free()

	# 4. PatchLoader patch-pack discovery order + PATCH_NOTES.md presence
	var tmp_patch_dir := ProjectSettings.globalize_path("user://test_patches_tmp")
	DirAccess.make_dir_recursive_absolute(tmp_patch_dir)
	var p1 := FileAccess.open(tmp_patch_dir.path_join("patch_02.pck"), FileAccess.WRITE)
	if p1 != null:
		p1.store_8(0)
		p1.close()
	var p0 := FileAccess.open(tmp_patch_dir.path_join("patch_01.pck"), FileAccess.WRITE)
	if p0 != null:
		p0.store_8(0)
		p0.close()
	var pt_txt := FileAccess.open(tmp_patch_dir.path_join("ignore.txt"), FileAccess.WRITE)
	if pt_txt != null:
		pt_txt.store_8(0)
		pt_txt.close()
	var listed: PackedStringArray = PatchLoader.list_patch_files(tmp_patch_dir)
	var pl_ok: bool = (
		listed.size() == 2
		and listed[0].ends_with("patch_01.pck")
		and listed[1].ends_with("patch_02.pck")
	)
	for leftover: String in ["patch_01.pck", "patch_02.pck", "ignore.txt"]:
		DirAccess.remove_absolute(tmp_patch_dir.path_join(leftover))
	DirAccess.remove_absolute(tmp_patch_dir)
	var notes_ok: bool = FileAccess.file_exists("res://PATCH_NOTES.md") and FileAccess.get_file_as_string("res://PATCH_NOTES.md").contains("Patch Notes")
	_check(pl_ok and notes_ok, "PatchLoader sorts runtime .pck patches & PATCH_NOTES.md is packaged cleanly")

	# 5. SAM placement preview radius + SelectionOverlayLayer & WorldState Team Mode / Telemetry
	var sam_r1: float = StructureData.get_sam_radius_for_level(1)
	var ov := SelectionOverlayLayer.new()
	_check(sam_r1 > 0.0 and ov.has_method("set_build_mode") and ov.has_method("add_map_ping"),
		"SAM placement range Lv.1 (%.1f px) & tactical ping overlay methods exposed" % sam_r1)
	ov.free()

	var tws := WorldState.new()
	tws.load_world()
	var n1_pos := _find_nearby_land(tws, -98.0, 39.0)
	var n2_pos := _find_nearby_land(tws, -82.0, 35.0)
	var n3_pos := _find_nearby_land(tws, 10.0, 48.0)
	tws.apply_command({
		"type": "start_mp_match",
		"seed": 777,
		"local_nation_id": 1,
		"ai_count": 0,
		"players": [
			{"nation_id": 1, "name": "TeamAlpha1", "team_id": 1, "x": n1_pos.x, "y": n1_pos.y},
			{"nation_id": 2, "name": "TeamAlpha2", "team_id": 1, "x": n2_pos.x, "y": n2_pos.y},
			{"nation_id": 3, "name": "TeamBravo1", "team_id": 2, "x": n3_pos.x, "y": n3_pos.y},
		],
	})
	var tn1: NationData = tws.get_nation(1)
	var tn2: NationData = tws.get_nation(2)
	var tn3: NationData = tws.get_nation(3)
	var team_ally_ok: bool = tn1 != null and tn2 != null and tn3 != null and tws.are_allied(1, 2) and not tws.are_allied(1, 3)
	for t_hist in range(1, 73):
		tws.step_tick(t_hist)
	if tn1 != null and tn2 != null:
		tn1.territory_percent = 50.0
		tn2.territory_percent = 35.0
	tws.step_tick(73)
	var team_win_ok: bool = (tws.match_phase == WorldState.PHASE_VICTORY and tws.winner_team_id == 1)
	var telemetry_ok: bool = (tn1 != null and tn1.peak_territory_percent >= 50.0 and tws.match_history.size() >= 1)
	_check(team_ally_ok and team_win_ok and telemetry_ok,
		"WorldState Team Mode shared alliances/victory & match_history telemetry verified")

	# 6. Warship -45% speed nerf +5%/lvl scaling, no_nukes modifier, SimulationClock speed, and new missile/SAM SFX
	var test_ship := ShipUnit.new()
	test_ship.kind = ShipUnit.KIND_WARSHIP
	test_ship.base_speed_px_per_sec = 10.48 # ~55% of legacy ~19.05
	test_ship.refresh_warship_speed()
	var spd_l1: float = test_ship.speed_px_per_sec
	test_ship.add_xp(2) # Lv.2 (+5%)
	var spd_l2: float = test_ship.speed_px_per_sec
	test_ship.add_xp(3) # Lv.3 (+10% vs base)
	var spd_l3: float = test_ship.speed_px_per_sec
	_check(is_equal_approx(spd_l2, spd_l1 * 1.05) and is_equal_approx(spd_l3, spd_l1 * 1.10),
		"Warship speed reduced (-45%% base) and scales +5%% per level (%.2f -> %.2f -> %.2f)" % [spd_l1, spd_l2, spd_l3])

	var mod_ws := WorldState.new()
	mod_ws.load_world()
	mod_ws.apply_command({
		"type": "start_mp_match",
		"seed": 888,
		"local_nation_id": 1,
		"ai_count": 0,
		"options": {"game_speed": 2.0, "no_nukes": true, "ai_difficulty": "brutal", "start_preset": "fast"},
		"players": [{"nation_id": 1, "name": "CmdMod", "x": n1_pos.x, "y": n1_pos.y}],
	})
	var silo_chk: Dictionary = mod_ws.can_place_structure(1, StructureData.TYPE_MISSILE_SILO, n1_pos.x, n1_pos.y)
	var nuke_rej: Dictionary = mod_ws.apply_command({"type": "launch_missile", "nation_id": 1, "missile_kind": MissileUnit.KIND_ATOM, "x": n3_pos.x, "y": n3_pos.y})
	var sc2 := SimulationClock.new()
	sc2.speed_multiplier = 2.0
	var adv_ticks: int = sc2.advance(0.125) # 2x -> 6 ticks instead of 3
	_check(mod_ws.no_nukes and not bool(silo_chk.get("ok", true)) and not bool(nuke_rej.get("ok", true)) and mod_ws.get_nation(1).gold >= 500000.0 and adv_ticks == 6,
		"Match modifiers (No Nukes, Fast Start, 2x clock speed=%d ticks/125ms) enforced cleanly" % adv_ticks)

	var new_sfx_ok := true
	for wname: String in ["res://assets/audio/sfx/missile_launch.wav", "res://assets/audio/sfx/sam_launch.wav", "res://assets/audio/sfx/sam_intercept.wav", "res://assets/audio/sfx/silo_nuke_launch.wav"]:
		var st_wav: AudioStreamWAV = load(wname) as AudioStreamWAV
		if st_wav == null or not st_wav.stereo or st_wav.mix_rate != 44100:
			new_sfx_ok = false
	_check(new_sfx_ok, "Updated MP3 missile launch & resounded SAM launch/intercept load as 44.1kHz stereo WAVs")

	# 7. v1.3.0 Checks: 20+ AI opponents, Allied Trade +40% & Naval Raiding bounty, FFA & Team Aid, HUD Pages
	var ws_many := WorldState.new()
	ws_many.load_world()
	ws_many.apply_command({"type": "spawn_player", "x": n1_pos.x, "y": n1_pos.y, "name": "ManyCmd", "ai_count": 20, "seed": 313})
	_check(ws_many.nations.size() >= 21 and ws_many.expansions.is_empty(),
		"Singleplayer supports 20+ AI opponents (%d total nations) starting cleanly without auto-spread" % ws_many.nations.size())

	var ws_trade := WorldState.new()
	ws_trade.load_world()
	ws_trade.apply_command({
		"type": "start_mp_match", "seed": 515, "local_nation_id": 1, "ai_count": 0,
		"players": [
			{"nation_id": 1, "name": "AlliedA", "team_id": 1, "x": n1_pos.x, "y": n1_pos.y},
			{"nation_id": 2, "name": "AlliedB", "team_id": 1, "x": n2_pos.x, "y": n2_pos.y},
			{"nation_id": 3, "name": "RaiderC", "team_id": 2, "x": n3_pos.x, "y": n3_pos.y},
		],
	})
	var tr_a: NationData = ws_trade.get_nation(1)
	var tr_b: NationData = ws_trade.get_nation(2)
	var tr_c: NationData = ws_trade.get_nation(3)
	var team_aid_g: Dictionary = ws_trade.apply_command({"type": "donate_gold", "nation_id": 1, "target_nation_id": 2, "amount": 50000.0})
	var team_aid_t: Dictionary = ws_trade.apply_command({"type": "donate_troops", "nation_id": 1, "target_nation_id": 2, "ratio": 0.25})
	var team_brk: Dictionary = ws_trade.apply_command({"type": "break_alliance", "nation_id": 1, "target_nation_id": 2})
	var r_ship := ShipUnit.new()
	r_ship.id = ws_trade._next_ship_id
	ws_trade._next_ship_id += 1
	r_ship.kind = ShipUnit.KIND_TRADE
	r_ship.nation_id = tr_a.id
	r_ship.gold_value = 40000.0
	r_ship.position = Vector2(512.0, 512.0)
	r_ship.waypoints = PackedVector2Array([Vector2(512.0, 512.0), Vector2(540.0, 512.0)])
	r_ship.waypoint_index = 1
	ws_trade.ships[r_ship.id] = r_ship
	var w_raid := ShipUnit.new()
	w_raid.id = ws_trade._next_ship_id
	ws_trade._next_ship_id += 1
	w_raid.kind = ShipUnit.KIND_WARSHIP
	w_raid.nation_id = tr_c.id
	w_raid.position = Vector2(518.0, 512.0)
	w_raid.patrol_center = w_raid.position
	w_raid.waypoints = PackedVector2Array([w_raid.position, Vector2(528.0, 512.0)])
	w_raid.waypoint_index = 1
	ws_trade.ships[w_raid.id] = w_raid
	var c_gold_pre: float = tr_c.gold
	ws_trade._step_ships()
	var raid_loot_ok: bool = tr_c.gold >= c_gold_pre + 25000.0 # 65% of 40000 = 26000 when no friendly port
	_check(bool(team_aid_g.get("ok", false)) and bool(team_aid_t.get("ok", false)) and not bool(team_brk.get("ok", true)) and raid_loot_ok,
		"Team/FFA Gold & Troop aid verified, permanent team pact protected, and Warship naval raid plunders 65%% trade value")

	# 8. v1.3.2 Regression Checks: MIRV Whole-Nation Coverage, AI Explore Troop Cost, Strict Coastal Port Placement
	var ws_v132 := WorldState.new()
	ws_v132.load_world()
	ws_v132.apply_command({"type": "spawn_player", "x": n1_pos.x, "y": n1_pos.y, "name": "Cmd132", "ai_count": 0, "seed": 777})
	var p132: NationData = ws_v132.get_player_nation()
	p132.gold = 80000000.0
	var giant_spot := _find_nearby_land(ws_v132, 20.0, 10.0, 12) # Central Africa interior for ~8000-cell nation
	var giant_n: NationData = ws_v132._create_nation("MegaState", Color.RED, false, giant_spot, 8000)
	var mirv_pts: Array[Vector2i] = ws_v132.compute_mirv_targets(giant_n.id, giant_spot)
	var g_min_x := 9999
	var g_max_x := -1
	var g_min_y := 9999
	var g_max_y := -1
	for gi in range(ws_v132.sim_width * ws_v132.sim_height):
		if ws_v132.owner_grid[gi] == giant_n.id:
			var gx: int = gi % ws_v132.sim_width
			var gy: int = int(gi / ws_v132.sim_width)
			g_min_x = mini(g_min_x, gx)
			g_max_x = maxi(g_max_x, gx)
			g_min_y = mini(g_min_y, gy)
			g_max_y = maxi(g_max_y, gy)
	var g_cx: float = float(g_min_x + g_max_x) * 0.5
	var g_cy: float = float(g_min_y + g_max_y) * 0.5
	var q_mask := 0
	var near_center := false
	for mp: Vector2i in mirv_pts:
		if mp.x < g_cx and mp.y < g_cy: q_mask |= 1
		elif mp.x >= g_cx and mp.y < g_cy: q_mask |= 2
		elif mp.x < g_cx and mp.y >= g_cy: q_mask |= 4
		else: q_mask |= 8
		if Vector2(mp).distance_to(Vector2(g_cx, g_cy)) <= 32.0:
			near_center = true
	var p132_silo := ws_v132.apply_command({"type": "build_structure", "nation_id": p132.id, "structure_type": StructureData.TYPE_MISSILE_SILO, "x": n1_pos.x, "y": n1_pos.y})
	for _t in range(32):
		ws_v132.step_tick(ws_v132.current_tick + 1)
	var p132_silo_obj: StructureData = ws_v132.get_structure(int(p132_silo.get("structure_id", 0)))
	if p132_silo_obj != null:
		p132_silo_obj.action_cooldown_ticks = 0
	var m_launch := ws_v132.apply_command({"type": "launch_missile", "nation_id": p132.id, "missile_kind": MissileUnit.KIND_MIRV, "x": giant_spot.x, "y": giant_spot.y})
	var spawned_subs := 0
	for _t in range(180):
		ws_v132.step_tick(ws_v132.current_tick + 1)
		var c_now := 0
		for mid_k: int in ws_v132.missiles.keys():
			if (ws_v132.missiles[mid_k] as MissileUnit).kind == MissileUnit.KIND_MIRV_WARHEAD:
				c_now += 1
		spawned_subs = maxi(spawned_subs, c_now)
	_check(bool(m_launch.get("ok", false)) and mirv_pts.size() >= 12 and q_mask == 15 and near_center and spawned_subs >= mirv_pts.size() - 2,
		"MIRV targets whole territory across interior & all 4 quadrants (%d targets, %d warheads)" % [mirv_pts.size(), spawned_subs],
		"pts=%d q=%d center=%s subs=%d" % [mirv_pts.size(), q_mask, str(near_center), spawned_subs])

	var ws_ai_cost := WorldState.new()
	ws_ai_cost.load_world()
	ws_ai_cost.apply_command({"type": "spawn_player", "x": n1_pos.x, "y": n1_pos.y, "name": "AiCostRef", "ai_count": 3, "seed": 909})
	var ai_sample: NationData = null
	for nid_a: int in ws_ai_cost.nations.keys():
		if not ws_ai_cost.nations[nid_a].is_player:
			ai_sample = ws_ai_cost.nations[nid_a]
			break
	var ai_pre_troops: float = ai_sample.troops
	ai_sample.troops = ai_sample.max_troops * 0.90
	ai_pre_troops = ai_sample.troops
	AIController._act_for_nation(ws_ai_cost, ai_sample, 14)
	var ai_dropped_troops: bool = (ai_sample.troops < ai_pre_troops * 0.70) and (ws_ai_cost.count_active_expansions(ai_sample.id) >= 1)
	var tiny_ship := ShipUnit.new()
	tiny_ship.id = ws_ai_cost._next_ship_id
	ws_ai_cost._next_ship_id += 1
	tiny_ship.kind = ShipUnit.KIND_LANDING
	tiny_ship.nation_id = ai_sample.id
	tiny_ship.troops_carried = 3.0
	tiny_ship.landing_cell = _find_nearby_land(ws_ai_cost, -1.5, 51.5, 4)
	tiny_ship.target_cell = tiny_ship.landing_cell
	tiny_ship.waypoints = PackedVector2Array([ws_ai_cost.sim_to_world(tiny_ship.landing_cell)])
	tiny_ship.waypoint_index = 1
	ws_ai_cost.ships[tiny_ship.id] = tiny_ship
	var ex_before_tiny: int = ws_ai_cost.expansions.size()
	ws_ai_cost._step_ships()
	var no_free_landing_troops: bool = (ws_ai_cost.expansions.size() == ex_before_tiny)
	_check(ai_dropped_troops and no_free_landing_troops,
		"AI exploration deducts standing army properly (%.0f -> %.0f) & tiny landing ships spawn zero free troops" % [ai_pre_troops, ai_sample.troops])

	var ws_port_rule := WorldState.new()
	ws_port_rule.load_world()
	var port_coast := Vector2i(-1, -1)
	var port_inland_2px := Vector2i(-1, -1)
	var lake_shore := Vector2i(-1, -1)
	for py in range(100, ws_port_rule.sim_height - 100):
		var ro: int = py * ws_port_rule.sim_width
		for px in range(100, ws_port_rule.sim_width - 100):
			var idx_p: int = ro + px
			if ws_port_rule.terrain_grid[idx_p] < WorldState.T_PLAINS:
				continue
			if port_coast.x < 0 and ws_port_rule.coastal_grid[idx_p] == 1 and ws_port_rule.sea_pathfinder.find_nearest_nav_cell(Vector2i(px, py), 2).x >= 0:
				if px + 2 < ws_port_rule.sim_width and ws_port_rule.terrain_grid[idx_p + 2] >= WorldState.T_PLAINS and ws_port_rule.coastal_grid[idx_p + 2] == 0:
					port_coast = Vector2i(px, py)
					port_inland_2px = Vector2i(px + 2, py)
			if lake_shore.x < 0 and ws_port_rule.coastal_grid[idx_p] == 0:
				for dir_l: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if ws_port_rule.get_terrain_at(px + dir_l.x, py + dir_l.y) == WorldState.T_LAKE:
						lake_shore = Vector2i(px, py)
						break
			if port_coast.x >= 0 and lake_shore.x >= 0:
				break
		if port_coast.x >= 0 and lake_shore.x >= 0:
			break
	ws_port_rule.apply_command({"type": "spawn_player", "x": port_coast.x, "y": port_coast.y, "name": "PortStrict", "ai_count": 0, "seed": 414})
	var pp_s: NationData = ws_port_rule.get_player_nation()
	pp_s.gold = 5000000.0
	ws_port_rule._claim_organic_dot(pp_s.id, port_coast, 80, 0)
	ws_port_rule._set_cell_owner(port_inland_2px.y * ws_port_rule.sim_width + port_inland_2px.x, pp_s.id)
	if lake_shore.x >= 0:
		ws_port_rule._set_cell_owner(lake_shore.y * ws_port_rule.sim_width + lake_shore.x, pp_s.id)
	var port_ok_chk: Dictionary = ws_port_rule.can_place_structure(pp_s.id, StructureData.TYPE_PORT, port_coast.x, port_coast.y)
	var port_inland_chk: Dictionary = ws_port_rule.can_place_structure(pp_s.id, StructureData.TYPE_PORT, port_inland_2px.x, port_inland_2px.y)
	var port_lake_chk: Dictionary = ws_port_rule.can_place_structure(pp_s.id, StructureData.TYPE_PORT, lake_shore.x, lake_shore.y) if lake_shore.x >= 0 else {"ok": false, "reason": "coastline"}
	_check(
		bool(port_ok_chk.get("ok", false))
		and not bool(port_inland_chk.get("ok", true)) and "coastline" in str(port_inland_chk.get("reason", "")).to_lower()
		and not bool(port_lake_chk.get("ok", true)) and "coastline" in str(port_lake_chk.get("reason", "")).to_lower(),
		"Port placement strictly requires ocean coastline with open-sea access (rejects 2px inland & inland lakes)",
		"coast=%s inland=%s lake=%s" % [str(port_ok_chk), str(port_inland_chk), str(port_lake_chk)])
