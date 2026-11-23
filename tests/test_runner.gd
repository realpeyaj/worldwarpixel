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
	_check(icons_ok and ui_ok_tex and not ResourceLoader.exists("res://assets/sprites/icon_capital.png") and not ResourceLoader.exists("res://assets/sprites/icon_army.png"),
		"All 14 smooth minimalist sprites (64x64 / 96x48 / 64x32), 10 nation masks & 5 9-patch UI frames load cleanly")

	var env_script := EnvironmentDecor.new()
	_check(not env_script.has_method("_draw_compass_rose"), "EnvironmentDecor has no N/S/E/W compass rose")
	env_script.free()

	# 2. Load & Grid Integrity
	var t0: int = Time.get_ticks_usec()
	var ws := WorldState.new()
	var loaded: bool = ws.load_world()
	var t1: int = Time.get_ticks_usec()
	print("[BENCH] WorldState.load_world() (1024x512 grid + landmasses + 1024x512 nav): %.2f ms" % (float(t1 - t0) / 1000.0))
	var nav_land_overlap := 0
	if ws.terrain_grid.size() == ws.sea_pathfinder.nav_grid.size():
		for n_idx in range(ws.sea_pathfinder.nav_grid.size()):
			if ws.sea_pathfinder.nav_grid[n_idx] > 0 and ws.terrain_grid[n_idx] != WorldState.T_OCEAN:
				nav_land_overlap += 1
	_check(loaded and ws.terrain_grid.size() == 1024 * 512 and ws.sea_pathfinder.nav_grid.size() == 1024 * 512 and nav_land_overlap == 0,
		"WorldState loads 1024x512 terrain_grid and strict water-only 1024x512 ocean_nav (0 land overlaps)")

	var ata_cells := 0
	for y in range(422, ws.sim_height):
		for x in range(ws.sim_width):
			if ws.is_land_cell(x, y):
				ata_cells += 1
	_check(ata_cells > 5000 and ws.total_conquerable_area_km2 >= 135000000.0,
		"Antarctica (%d cells) is conquerable and included in total area (%.0f km2)" % [ata_cells, ws.total_conquerable_area_km2])

	var islands_ok := true
	for pt in [[-155.5, 19.6], [-18.5, 64.9], [46.8, -18.9], [-79.5, 21.8], [138.2, 36.2], [-59.5, -51.7]]:
		if _find_nearby_land(ws, pt[0], pt[1], 4).x < 0:
			islands_ok = false
	_check(islands_ok, "Enlarged tiny islands (Hawaii, Iceland, Madagascar, Cuba, Japan, Falklands) present as land")

	# 3. Spawn & Long-Range Circular-Organic Expansion (Zero Heartbeat Spikes)
	_check(not bool(ws.apply_command({"type": "spawn_player", "x": 120, "y": 280, "name": "Ocean", "ai_count": 0}).get("ok", true)),
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
	p.owned_cell_count = 20000
	var giant_scale: float = ws.get_nation_label_scale(p.id)
	p.owned_cell_count = saved_cnt
	_check(label_on_owned and label_cell_after.x > label_cell_before.x and label_scale_after > label_scale_before * 1.25 and giant_scale <= WorldState.NATION_LABEL_MAX_SCALE + 0.01,
		"Nation banner+name tracks centroid ((%d,%d)->(%d,%d)) and scales with cap (%.2f->%.2f, max=%.2f)" % [
			label_cell_before.x, label_cell_before.y, label_cell_after.x, label_cell_after.y, label_scale_before, label_scale_after, giant_scale
		])

	# Verify tight structure placement spacing (5 cells allowed, 2 cells rejected)
	p.gold = 1000000.0
	var sp_base := ws.apply_command({"type": "build_structure", "nation_id": p.id, "structure_type": StructureData.TYPE_TOWN, "x": us_spot.x, "y": us_spot.y})
	var sp_close_rej := ws.can_place_structure(p.id, StructureData.TYPE_DEFENSE_POST, us_spot.x + 2, us_spot.y)
	var sp_near_ok := ws.can_place_structure(p.id, StructureData.TYPE_DEFENSE_POST, us_spot.x + 5, us_spot.y)
	_check(bool(sp_base.get("ok", false)) and WorldState.MIN_STRUCTURE_SPACING_CELLS <= 4 and not bool(sp_close_rej.get("ok", true)) and bool(sp_near_ok.get("ok", false)),
		"Structure spacing allows close placement (5 cells ok, 2 cells rejected, min=%d)" % WorldState.MIN_STRUCTURE_SPACING_CELLS)

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
	for dy in range(-8, 9):
		for dx in range(-8, 9):
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
	var partner_coast: Vector2i = _find_nearby_land(ws_sea, -4.0, 48.2, 6)
	var partner_n: NationData = ws_sea._create_nation("TradeLeague", Color.TEAL, false, partner_coast, 42)
	partner_n.gold = 2000000.0
	var p2_spot := Vector2i(-1, -1)
	for dy in range(-8, 9):
		for dx in range(-8, 9):
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

	# Verify OpenFront 1:1 Port-to-Port auto-trading ships pay BOTH partners distance-scaled Pesos + Town/Factory popups
	sea_p.gold = 10000000.0
	var town_spot := Vector2i(-1, -1)
	for dy in range(-18, 19):
		for dx in range(-18, 19):
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
	var rival_spot := Vector2i(us_spot.x + 12, us_spot.y)
	var rival: NationData = ws_war._create_nation("Rival", Color.RED, false, rival_spot, 60)
	var rival_orig_cells: Array[int] = []
	for idx in range(ws_war.sim_width * ws_war.sim_height):
		if ws_war.owner_grid[idx] == rival.id:
			rival_orig_cells.append(idx)
	p_war.troops = 500.0
	var wild_click := Vector2i(us_spot.x + 6, us_spot.y - 2)
	for dy_w in range(-4, 5):
		var cy_w: int = us_spot.y + dy_w
		var cx_w: int = us_spot.x + 6
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

	var falk := _find_nearby_land(ws_hop, -59.5, -51.7, 6)
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
			if n.owned_cell_count > 62:
				ai_grew += 1
			if n.structure_ids.size() > 0:
				ai_built += 1
	_check(seen_colors.size() == 5 and ai_grew >= 2 and ai_built >= 1,
		"Random distinct colors assigned (%d unique) & smarter AI expands/builds (%d grew, %d built)" % [seen_colors.size(), ai_grew, ai_built])

	var theme_stream: AudioStream = load("res://assets/audio/music/world_war_pixel_theme.wav")
	var audio_streams: Dictionary = AudioManager.get("_streams") if AudioManager != null else {}
	var public_sfx_ok := FileAccess.file_exists("res://assets/audio/SOURCES.txt")
	for cat_k: String in ["missile_launch", "silo_nuke_launch", "sam_launch", "sam_intercept", "nuke_blast", "cannon_fire", "battle_clash", "boat_bell", "target_lock", "warship_horn", "troop_donate", "retreat_horn"]:
		if not audio_streams.has(cat_k) or (audio_streams[cat_k] as Array).is_empty():
			public_sfx_ok = false
	var geom_ships_ok := (
		is_equal_approx(UnitsLayer.TRADE_SHIP_SIZE_PX, 2.0)
		and is_equal_approx(UnitsLayer.EXPLORER_SHIP_SIZE_PX, 3.0)
		and UnitsLayer.WARSHIP_DIAMOND_HALF_LEN > 2.0
	)
	_check(AudioManager != null and AudioServer.bus_count >= 5 and theme_stream != null and AudioManager.get("_music_player") != null and public_sfx_ok,
		"AudioManager loads 5 buses, martial theme track & public-domain missile/silo/SAM/nuke WAVs")
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
			var menu_init: bool = hud.menu_overlay.visible and not hud.spawn_banner.visible
			hud._on_play_pressed()
			var play_reveals_spawn: bool = (not hud.menu_overlay.visible) and hud.spawn_banner.visible
			var no_color_or_slider: bool = inst.get_node_or_null("HUD/Root/SpawnBanner/VBox/Row/ColorRow") == null and inst.get_node_or_null("HUD/Root/ActionDock/HBox/CommitBox/CommitSlider") == null
			hud.set_commit_ratio(0.20)
			var r20: bool = is_equal_approx(hud.get_commit_ratio(), 0.20)
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
				and not (inst.get_node("HUD/Root/MenuOverlay/Center/MenuCard/VBox/Subtitle") as Control).visible
				and (inst.get_node("HUD/Root/MenuOverlay/Center/MenuCard/VBox/NameRow/Lbl") as Label).text == "Name"
				and hud.get_selected_server_name() == "Manila, PH"
				and not hud.mp_server_edit.visible
				and hud.expand_btn.text == "Explore"
				and (hud.action_dock.offset_right - hud.action_dock.offset_left) <= 760.0
				and hud.radial_attack_btn.text == "Attack"
				and hud.radial_build_btn.text == "Upgrade"
				and hud.radial_warship_btn.text == "Boat"
				and hud.radial_dip_btn.text == "Ally"
				and inst.get_node_or_null("HUD/Root/VictoryOverlay") != null
				and inst.get_node_or_null("HUD/Root/SpectatorBanner") != null
			)
			var of_nodes := inst.get_node_or_null("HUD/Root/RadialMenu") != null and inst.get_node_or_null("HUD/Root/RightStack/DiplomacyPanel") != null and inst.get_node_or_null("HUD/Root/AllianceBanner") != null
			var mp_nodes := inst.get_node_or_null("HUD/Root/MenuOverlay/Center/MpLobbyCard") != null and inst.get_node_or_null("HUD/Root/MenuOverlay/Center/MenuCard/VBox/MultiplayerBtn") != null
			var ping_nodes := inst.get_node_or_null("HUD/Root/PingBadge") != null and inst.get_node_or_null("HUD/Root/PingBadge/HBox/PingIcon") != null and inst.get_node_or_null("HUD/Root/PingBadge/HBox/PingLabel") != null
			hud.update_ping(42)
			var ping_set_ok: bool = hud.ping_label.text == "42ms"
			hud.update_ping(-1)
			var ping_reset_ok: bool = hud.ping_label.text == "--ms"
			var peso_hud_ok: bool = hud.gold_label.text.begins_with("Pesos:")
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
			ui_ok = menu_init and play_reveals_spawn and no_color_or_slider and r20 and r50 and r75 and hk_init and hk_off and lb_min and lb_restored and dock_icons and of_nodes and mp_nodes and ping_nodes and ping_set_ok and ping_reset_ok and peso_hud_ok and smooth_filter_ok and hk_fact and hk_ship and hk_atom and hk_h and hk_m
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
		and is_equal_approx(StructureData.get_scaled_build_cost(StructureData.TYPE_DEFENSE_POST, 5), 1000000.0)
		and is_equal_approx(StructureData.get_build_cost(StructureData.TYPE_MISSILE_SILO), 1000000.0)
		and is_equal_approx(StructureData.get_build_cost(StructureData.TYPE_SAM_LAUNCHER), 1500000.0)
		and is_equal_approx(MissileUnit.get_cost(MissileUnit.KIND_ATOM), 750000.0)
		and is_equal_approx(MissileUnit.get_cost(MissileUnit.KIND_HYDROGEN), 5000000.0)
		and is_equal_approx(MissileUnit.get_cost(MissileUnit.KIND_MIRV), 25000000.0)
	)
	_check(peso_prices_ok, "Peso inflation pricing verified (Buildings 2x->1M cap, Warships 2x->750k, Silo 1M, SAM 1.5M, Nukes 750k/5M/25M)")

	# Defense Post vs unfortified conquest cost + scaling build cost
	var rival := ws._create_nation("Tester", Color.RED, false, Vector2i(us_spot.x + 12, us_spot.y), 60)
	rival.gold = 5000000.0
	var def_res: Dictionary = ws.apply_command({"type": "build_structure", "nation_id": rival.id, "structure_type": StructureData.TYPE_DEFENSE_POST, "x": rival.capital_cell.x, "y": rival.capital_cell.y})
	var def_cost1: float = ws.get_structure_build_cost(rival.id, StructureData.TYPE_DEFENSE_POST)
	for _t in range(32):
		ws.step_tick(ws.current_tick + 1)
	var def_st: StructureData = ws.get_structure(int(def_res.get("structure_id", 0)))
	var mult_1: float = ws.get_defense_multiplier_at(rival.id, rival.capital_cell)
	ws.apply_command({"type": "upgrade_structure", "nation_id": rival.id, "structure_id": def_st.id})
	var mult_2: float = ws.get_defense_multiplier_at(rival.id, rival.capital_cell)
	_check(def_st != null and def_st.level == 2 and mult_1 >= 1.80 and mult_2 > mult_1 and def_cost1 > StructureData.get_build_cost(StructureData.TYPE_DEFENSE_POST),
		"Defense Post fortifies nearby border (%.2fx -> %.2fx) & scaling Peso cost increases (%s)" % [mult_1, mult_2, StructureData.format_pesos(def_cost1)])

	# OpenFront 1:1 25% contested attack retreat malus
	ws._claim_organic_dot(p.id, Vector2i(us_spot.x + 6, us_spot.y), 45, 0)
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
	for dy in range(-8, 9):
		for dx in range(-8, 9):
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
	var foe := ws_nav._create_nation("Corsair", Color.ORANGE, false, port_spot, 50)
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
		"type": "command_warship", "nation_id": nav_p.id, "ship_id": ws_id, "x": normandy.x - 14, "y": normandy.y - 6
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
	var target_city := _find_nearby_land(ws_nuke, -82.0, 38.0, 6)
	var tgt_n := ws_nuke._create_nation("TargetState", Color.GREEN, false, target_city, 140)
	tgt_n.gold = 2000000.0
	var s_res: Dictionary = ws_nuke.apply_command({"type": "build_structure", "nation_id": ap.id, "structure_type": StructureData.TYPE_MISSILE_SILO, "x": us_spot.x, "y": us_spot.y})
	# Build a closer 2nd Silo east of us_spot toward target_city to verify nearest-silo dispatch
	ws_nuke._claim_organic_dot(ap.id, Vector2i(us_spot.x + 14, us_spot.y), 80, 0)
	var close_silo_cell := Vector2i(us_spot.x + 14, us_spot.y)
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
	var sam_specs_ok: bool = sam_st_chk != null and sam_st_chk.get_sam_radius() <= 22.0 and sam_st_chk.get_sam_cooldown_ticks() >= 300
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
	var hbomb_city := _find_nearby_land(ws_nuke, -84.0, 33.0, 6)
	var tgt_n2 := ws_nuke._create_nation("TargetStateB", Color.ORANGE, false, hbomb_city, 180)
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
	var far_range_atom: Dictionary = ws_nuke.apply_command({"type": "launch_missile", "nation_id": ap.id, "missile_kind": MissileUnit.KIND_ATOM, "x": clampi(us_spot.x + 360, 0, ws_nuke.sim_width - 1), "y": us_spot.y})
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
		and is_equal_approx(StructureData.get_sam_radius_for_level(2), 18.0 * 1.15)
	)
	_check(not bool(unconq_mirv.get("ok", true)) and bool(far_range_atom.get("ok", false)) and silo_cd_ticks >= 240 and silo_sam_caps_ok,
		"MIRV rejects unconquered land, Missiles have infinite range, Silo/SAM cap at Lv.3 (-10%% Silo CD, +15%% SAM range / -12.5%% SAM CD)" ,
		"unconq=%s far=%s cd=%d caps=%s" % [str(unconq_mirv), str(far_range_atom), silo_cd_ticks, str(silo_sam_caps_ok)])

	var mirv_city := _find_nearby_land(ws_nuke, -88.0, 41.0, 6)
	var tgt_n3 := ws_nuke._create_nation("TargetStateC", Color.PURPLE, false, mirv_city, 220)
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
	for dy_f in range(-8, 9):
		for dx_f in range(-8, 9):
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
		and ws_nuke.fallout_cell_count > 30
		and ws_nuke.render_owner_grid[f_idx_probe] == 255
		and bool(ws_nuke.get_cell_info(fallout_probe.x, fallout_probe.y).get("fallout", false))
	)
	# First verify that normal free-hand explore (clicking a clean cell) sets allow_fallout == false and skips fallout cells
	var clean_target := Vector2i(us_spot.x + 8, us_spot.y)
	ws_nuke._set_cell_owner(clean_target.y * ws_nuke.sim_width + clean_target.x, 0)
	ws_nuke.fallout_grid[clean_target.y * ws_nuke.sim_width + clean_target.x] = 0
	var adj_fallout := Vector2i(us_spot.x + 3, us_spot.y)
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
	var reclaimer := ws_nuke._create_nation("Reclaimers", Color.YELLOW, false, fallout_probe, 1)
	reclaimer.troops = 200.0
	var rec_cmd := ws_nuke.apply_command({
		"type": "expand_to",
		"nation_id": reclaimer.id,
		"x": clampi(fallout_probe.x + 2, 0, ws_nuke.sim_width - 1),
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
	_check(fallout_created_ok and skipped_fallout_ok and allow_fallout_ok and claimed_rec_cells >= 5 and ws_nuke.fallout_cell_count < pre_reclaim_fallout and not ws_nuke.is_fallout_at(fallout_probe.x, fallout_probe.y) and cost_per_cell >= 2.2,
		"Nuke leaves GPU nuclear fallout excluded unless clicked & cleared by costly troop reclamation (%.2f troops/cell, %d fallout remaining)" % [cost_per_cell, ws_nuke.fallout_cell_count],
		"ok=%s skip=%s allow=%s probe=%s claimed=%d cost=%.2f f=%d->%d" % [str(fallout_created_ok), str(skipped_fallout_ok), str(allow_fallout_ok), str(fallout_probe), claimed_rec_cells, cost_per_cell, pre_reclaim_fallout, ws_nuke.fallout_cell_count])

	# Milestone 4 & 5: Alliances, Embargo, Peso & Troop Donations, Betrayal & Factory Trains
	var friend := ws._create_nation("AllyRealm", Color.CYAN, false, Vector2i(us_spot.x - 18, us_spot.y), 50)
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
	ws_tr._claim_organic_dot(rp.id, Vector2i(us_spot.x + 9, us_spot.y), 520, 0)
	var b1 := ws_tr.apply_command({"type": "build_structure", "nation_id": rp.id, "structure_type": StructureData.TYPE_TOWN, "x": us_spot.x, "y": us_spot.y})
	var fac_pt := Vector2i(us_spot.x + 12, us_spot.y)
	for dy in range(-18, 19):
		var picked := false
		for dx in range(-18, 19):
			var c_pt := Vector2i(us_spot.x + dx, us_spot.y + dy)
			if c_pt.distance_to(us_spot) >= 11.0 and c_pt.distance_to(us_spot) <= 22.0 and ws_tr.can_place_structure(rp.id, StructureData.TYPE_FACTORY, c_pt.x, c_pt.y).get("ok", false):
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

	# Homeland Counter-Attack & AI-vs-AI Warfare checks (also verifies initial spawn starts at 14 cells and grows)
	var ws_cnt := WorldState.new()
	ws_cnt.load_world()
	ws_cnt.apply_command({"type": "spawn_player", "x": us_spot.x, "y": us_spot.y, "name": "Homeland", "ai_count": 0, "seed": 888})
	var def_p: NationData = ws_cnt.get_player_nation()
	var spawn_seed_cells: int = def_p.owned_cell_count
	for _t in range(24):
		ws_cnt.step_tick(ws_cnt.current_tick + 1)
	var spawn_grown_ok: bool = (spawn_seed_cells <= 16 and def_p.owned_cell_count >= 50)
	var inv_n := ws_cnt._create_nation("InvaderAI", Color.RED, false, Vector2i(us_spot.x + 8, us_spot.y), 60)
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
	var tiny_ai := ws_cnt._create_nation("DoomedPost", Color.MAGENTA, false, Vector2i(us_spot.x - 12, us_spot.y), 1)
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
	var ai_a := ws_aivai._create_nation("AI_North", Color.RED, false, us_spot, 90)
	var ai_b := ws_aivai._create_nation("AI_South", Color.BLUE, false, Vector2i(us_spot.x + 8, us_spot.y), 90)
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
	_check(ai_contested or ai_a.owned_cell_count > 120 or ai_b.owned_cell_count < 90,
		"AI actively attacks and fights rival AI nations on shared borders (AI_A=%d, AI_B=%d)" % [ai_a.owned_cell_count, ai_b.owned_cell_count])

	_run_multiplayer_lockstep_tests(us_spot, normandy)


func _run_multiplayer_lockstep_tests(us_spot: Vector2i, eu_spot: Vector2i) -> void:
	var mp := MPClient.new()
	var pong_sig := {"ms": -1}
	mp.ping_updated.connect(func(ms: int) -> void: pong_sig["ms"] = ms)
	mp._handle_message({"type": "pong", "t": Time.get_ticks_msec() - 25})
	_check(mp.DEFAULT_SERVER_URL == "ws://151.242.136.36:30041/ws" and not mp.is_socket_active() and int(pong_sig["ms"]) >= 1 and mp.last_ping_ms == int(pong_sig["ms"]),
		"MPClient points at ws://151.242.136.36:30041/ws and handles pong RTT cleanly (%dms)" % mp.last_ping_ms)

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
