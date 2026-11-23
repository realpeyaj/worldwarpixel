class_name AIController
extends RefCounted
## Scheduled 24 Hz AI controller with front reinforcement, synergy-aware structure
## placement, opportunistic conquest, and overseas island hopping.

const AI_STEP_INTERVAL := 14

const AI_NAMES := [
	"Aurelian Pact",
	"Boreal Union",
	"Solis Dominion",
	"Verdant League",
	"Iron Armada",
	"Pacific Compact",
	"Vanguard Republic",
	"Meridian Crown",
	"Polaris Realm",
	"Saffron Syndicate",
]

const AI_COLORS := [
	"#ef4444",
	"#22c55e",
	"#eab308",
	"#a855f7",
	"#06b6d4",
	"#f97316",
	"#ec4899",
	"#84cc16",
	"#14b8a6",
	"#f43f5e",
]


static func step_scheduled(ws: WorldState, tick: int) -> void:
	if ws.match_phase != WorldState.PHASE_PLAYING:
		return
	var ai_ids: Array[int] = []
	for nid: int in ws.nations.keys():
		var n: NationData = ws.nations[nid]
		if not n.is_player and n.alive:
			ai_ids.append(nid)
	if ai_ids.is_empty():
		return

	if tick % AI_STEP_INTERVAL != 0:
		return
	var chosen_idx: int = int(tick / AI_STEP_INTERVAL) % ai_ids.size()
	var nid: int = ai_ids[chosen_idx]
	_act_for_nation(ws, ws.nations[nid], tick)


static func _act_for_nation(ws: WorldState, nation: NationData, tick: int) -> void:
	# 0. Accept pending alliance proposals only selectively (max 1 ally so AIs still fight each other)
	if not nation.incoming_alliances.is_empty() and not nation.is_betrayer(tick) and nation.alliances.size() < 1:
		var from_id: int = int(nation.incoming_alliances.keys()[0])
		ws.apply_command({"type": "respond_alliance", "nation_id": nation.id, "from_nation_id": from_id, "accept": true})
		return

	# 0b. Counter-attack incoming invasions on this nation's territory
	if nation.troops >= maxf(45.0, nation.max_troops * 0.22):
		for eid: int in ws.expansions.keys():
			var inc: ExpansionOrder = ws.expansions[eid]
			if inc.active and inc.enemy_nation_id == nation.id and inc.remaining_troops > 0.5:
				var c_cell: Vector2i = ws.world_to_sim(inc.front_world_pos) if inc.front_world_pos != Vector2.ZERO else inc.target_cell
				ws.apply_command({
					"type": "expand_to",
					"nation_id": nation.id,
					"x": c_cell.x,
					"y": c_cell.y,
					"commit_ratio": 0.35,
				})
				return

	# 1. Reinforce any active front running low on troops when reserve allows
	if nation.troops >= nation.max_troops * 0.55:
		for eid: int in ws.expansions.keys():
			var o: ExpansionOrder = ws.expansions[eid]
			if o.nation_id == nation.id and o.active and o.remaining_troops < 40.0:
				ws.apply_command({
					"type": "expand_to",
					"nation_id": nation.id,
					"x": o.target_cell.x,
					"y": o.target_cell.y,
					"commit_ratio": 0.35,
				})
				return

	# 2. Launch occasional Atom Bomb against a stronger non-allied rival using nearest ready Silo
	if nation.gold >= 950000.0:
		var nuke_tgt: Vector2i = _pick_missile_target(ws, nation)
		if nuke_tgt.x >= 0:
			var ready_silo: StructureData = ws.find_ready_silo(nation.id, nuke_tgt)
			if ready_silo != null and ready_silo.action_cooldown_ticks == 0:
				ws.apply_command({
					"type": "launch_missile",
					"nation_id": nation.id,
					"missile_kind": MissileUnit.KIND_ATOM,
					"x": nuke_tgt.x,
					"y": nuke_tgt.y,
				})
				return

	# 3. Commission a Warship only after basic economy (Port + Town/Factory) is established
	if nation.structure_ids.size() >= 2 and nation.gold >= 250000.0 and ws.count_warships(nation.id) < 2 and nation.gold >= ws.get_warship_build_cost(nation.id):
		for sid: int in nation.structure_ids:
			var p_st: StructureData = ws.structures.get(sid, null)
			if p_st != null and p_st.type == StructureData.TYPE_PORT and not p_st.is_constructing and p_st.level >= 1 and p_st.action_cooldown_ticks == 0:
				ws.apply_command({"type": "build_warship", "nation_id": nation.id, "port_id": p_st.id})
				return

	# 4. Smart Peso allocation: compare upgrading existing economy/defense vs placing new structures
	if nation.gold >= 50000.0 and nation.structure_ids.size() < 13:
		var has_port := false
		var town_count := 0
		var factory_count := 0
		var def_count := 0
		var sam_count := 0
		var silo_count := 0
		for sid: int in nation.structure_ids:
			var st: StructureData = ws.structures.get(sid, null)
			if st != null:
				match st.type:
					StructureData.TYPE_PORT:
						has_port = true
					StructureData.TYPE_TOWN:
						town_count += 1
					StructureData.TYPE_FACTORY:
						factory_count += 1
					StructureData.TYPE_DEFENSE_POST:
						def_count += 1
					StructureData.TYPE_SAM_LAUNCHER:
						sam_count += 1
					StructureData.TYPE_MISSILE_SILO:
						silo_count += 1

		var rival_has_silo := false
		for sid_all: int in ws.structures.keys():
			var st_all: StructureData = ws.structures[sid_all]
			if st_all.type == StructureData.TYPE_MISSILE_SILO and st_all.nation_id != nation.id and not ws.are_allied(nation.id, st_all.nation_id):
				rival_has_silo = true
				break

		# First secure core 1st Town, 1st Port (if coastal), and 1st Factory before expensive 2x/4x duplicates
		var want_type := ""
		if town_count == 0 and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_TOWN):
			want_type = StructureData.TYPE_TOWN
		elif not has_port and not ws._nation_coasts.get(nation.id, {}).is_empty() and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_PORT):
			want_type = StructureData.TYPE_PORT
		elif (town_count >= 1 or has_port) and factory_count == 0 and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_FACTORY):
			want_type = StructureData.TYPE_FACTORY
		elif def_count < 1 and nation.structure_ids.size() >= 1 and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_DEFENSE_POST):
			want_type = StructureData.TYPE_DEFENSE_POST

		if want_type != "":
			var build_cell: Vector2i = _pick_build_cell(ws, nation, want_type)
			if build_cell.x >= 0:
				ws.apply_command({
					"type": "build_structure",
					"nation_id": nation.id,
					"structure_type": want_type,
					"x": build_cell.x,
					"y": build_cell.y,
				})
				return

		# Upgrade existing high-ROI structures when cheaper than scaled new builds
		if not nation.structure_ids.is_empty():
			var best_sid := 0
			var best_score := -1e9
			for sid: int in nation.structure_ids:
				var st: StructureData = ws.structures.get(sid, null)
				if st != null and st.can_upgrade():
					var c: float = st.get_next_upgrade_cost()
					if c <= nation.gold:
						var prio: float = 2.4 if (st.type == StructureData.TYPE_FACTORY or st.type == StructureData.TYPE_PORT) else 1.8
						var sc: float = prio * 1000000.0 - c * 1.4
						if sc > best_score:
							best_score = sc
							best_sid = sid
			if best_sid > 0 and ws.get_structure(best_sid).get_next_upgrade_cost() <= 240000.0:
				ws.apply_command({"type": "upgrade_structure", "nation_id": nation.id, "structure_id": best_sid})
				return

		if sam_count < 1 and (rival_has_silo or nation.structure_ids.size() >= 4) and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_SAM_LAUNCHER):
			want_type = StructureData.TYPE_SAM_LAUNCHER
		elif silo_count < 1 and nation.structure_ids.size() >= 3 and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_MISSILE_SILO):
			want_type = StructureData.TYPE_MISSILE_SILO
		elif (town_count >= 1 or has_port) and factory_count < town_count + 1 and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_FACTORY):
			want_type = StructureData.TYPE_FACTORY
		elif town_count < 3 and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_TOWN):
			want_type = StructureData.TYPE_TOWN
		elif def_count < 2 and nation.structure_ids.size() >= 2 and nation.gold >= ws.get_structure_build_cost(nation.id, StructureData.TYPE_DEFENSE_POST):
			want_type = StructureData.TYPE_DEFENSE_POST

		if want_type != "":
			var build_cell2: Vector2i = _pick_build_cell(ws, nation, want_type)
			if build_cell2.x >= 0:
				ws.apply_command({
					"type": "build_structure",
					"nation_id": nation.id,
					"structure_type": want_type,
					"x": build_cell2.x,
					"y": build_cell2.y,
				})
				return

	# 6. Periodically propose an alliance to a non-bordering distant nation
	if tick % 1440 == 0 and nation.alliances.is_empty() and not nation.is_betrayer(tick):
		var ally_cand: int = _pick_peaceful_ally_candidate(ws, nation)
		if ally_cand > 0:
			ws.apply_command({"type": "request_alliance", "nation_id": nation.id, "target_nation_id": ally_cand})
			return

	# 7. Expand: smart unclaimed rush, opportunistic weaker non-allied rival attack, or overseas hop
	var owned_borders: Dictionary = ws.get_nation_borders(nation.id)
	if nation.troops >= nation.max_troops * 0.32 and ws.count_active_expansions(nation.id) < 2 and not owned_borders.is_empty():
		var land_target: Vector2i = _pick_smart_land_target(ws, nation, owned_borders, tick)
		if land_target.x >= 0:
			ws.apply_command({
				"type": "expand_to",
				"nation_id": nation.id,
				"x": land_target.x,
				"y": land_target.y,
				"commit_ratio": 0.35,
			})
			return

		if nation.troops >= nation.max_troops * 0.55 and not ws._nation_coasts.get(nation.id, {}).is_empty():
			var sea_target: Vector2i = _pick_overseas_target(ws, nation, tick)
			if sea_target.x >= 0:
				ws.apply_command({
					"type": "expand_to",
					"nation_id": nation.id,
					"x": sea_target.x,
					"y": sea_target.y,
					"commit_ratio": 0.35,
				})


static func _pick_missile_target(ws: WorldState, nation: NationData) -> Vector2i:
	var best_pt := Vector2i(-1, -1)
	var best_score := 0.0
	for nid: int in ws.nations.keys():
		if nid == nation.id or ws.are_allied(nation.id, nid):
			continue
		var en: NationData = ws.nations[nid]
		if not en.alive or en.owned_cell_count < 60:
			continue
		var score: float = float(en.owned_cell_count) + float(en.structure_ids.size()) * 40.0
		if score > best_score:
			best_score = score
			best_pt = en.capital_cell
			for sid: int in en.structure_ids:
				var st: StructureData = ws.structures.get(sid, null)
				if st != null:
					best_pt = st.cell
					break
	return best_pt


static func _pick_peaceful_ally_candidate(ws: WorldState, nation: NationData) -> int:
	for nid: int in ws.nations.keys():
		if nid == nation.id or ws.are_allied(nation.id, nid) or ws.is_embargoed(nation.id, nid):
			continue
		var other: NationData = ws.nations[nid]
		if other.alive and not other.is_betrayer(ws.current_tick) and not other.incoming_alliances.has(nation.id):
			if nation.owned_cell_count >= 90 and other.capital_cell.distance_to(nation.capital_cell) < 28.0:
				continue
			return nid
	return 0


static func _pick_build_cell(ws: WorldState, nation: NationData, s_type: String) -> Vector2i:
	var cap: Vector2i = nation.capital_cell
	if s_type == StructureData.TYPE_PORT:
		var coasts: Dictionary = ws._nation_coasts.get(nation.id, {})
		for idx_var in coasts.keys():
			var idx: int = int(idx_var)
			var cx: int = idx % ws.sim_width
			var cy: int = int(idx / ws.sim_width)
			if ws.can_place_structure(nation.id, s_type, cx, cy).get("ok", false):
				return Vector2i(cx, cy)
		return Vector2i(-1, -1)

	if s_type == StructureData.TYPE_FACTORY:
		# Prefer within organic range (12..34 sim cells) of an owned Town or Port for mutual synergy / Bridges
		for sid: int in nation.structure_ids:
			var anchor: StructureData = ws.structures.get(sid, null)
			if anchor == null or anchor.type == StructureData.TYPE_FACTORY:
				continue
			for r in [14, 22, 30]:
				for angle_i in range(8):
					var ang: float = float(angle_i) * (TAU / 8.0)
					var cx: int = clampi(anchor.cell.x + int(round(cos(ang) * r)), 0, ws.sim_width - 1)
					var cy: int = clampi(anchor.cell.y + int(round(sin(ang) * r)), 0, ws.sim_height - 1)
					if ws.can_place_structure(nation.id, s_type, cx, cy).get("ok", false):
						return Vector2i(cx, cy)

	for r in [0, 12, 22, 34]:
		for angle_i in range(8):
			var ang: float = float(angle_i) * (TAU / 8.0)
			var cx: int = clampi(cap.x + int(round(cos(ang) * r)), 0, ws.sim_width - 1)
			var cy: int = clampi(cap.y + int(round(sin(ang) * r)), 0, ws.sim_height - 1)
			if ws.can_place_structure(nation.id, s_type, cx, cy).get("ok", false):
				return Vector2i(cx, cy)
	return Vector2i(-1, -1)


static func _pick_smart_land_target(ws: WorldState, nation: NationData, borders: Dictionary, tick: int) -> Vector2i:
	var keys: Array = borders.keys()
	var n_keys: int = keys.size()
	var sample_count: int = mini(n_keys, 16)
	var step: int = maxi(1, int(floor(float(n_keys) / float(sample_count))))
	var offset: int = (tick * 7 + nation.id * 13) % n_keys

	var best := Vector2i(-1, -1)
	var best_score := -1e9
	for i in range(sample_count):
		var b_idx: int = int(keys[(offset + i * step) % n_keys])
		var sx: int = b_idx % ws.sim_width
		var sy: int = int(b_idx / ws.sim_width)
		for dir: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(8, 0), Vector2i(-8, 0), Vector2i(0, 8), Vector2i(0, -8),
		]:
			var nx: int = sx + dir.x
			var ny: int = sy + dir.y
			if nx < 0 or ny < 0 or nx >= ws.sim_width or ny >= ws.sim_height:
				continue
			var n_idx: int = ny * ws.sim_width + nx
			var t: int = ws.terrain_grid[n_idx]
			if t < WorldState.T_PLAINS:
				continue
			var own: int = ws.owner_grid[n_idx]
			if own == nation.id:
				continue
			var score := 0.0
			if own == 0:
				score = 18.0 + (4.0 if ws.coastal_grid[n_idx] == 1 else 0.0) + (3.0 if t == WorldState.T_PLAINS else 0.0)
			else:
				if ws.are_allied(nation.id, own):
					continue
				# Attack any rival nation (AI or player) when equal or advantaged
				var enemy: NationData = ws.nations.get(own, null)
				var troop_fill: float = nation.troops / maxf(nation.max_troops, 1.0)
				var req_ratio: float = 0.72 if troop_fill >= 0.60 else 0.82
				if enemy == null or not enemy.alive or nation.troops < enemy.troops * req_ratio:
					continue
				var base_war: float = 22.0 if troop_fill >= 0.50 else 15.0
				score = base_war + clampf((1.0 - enemy.troops / maxf(nation.troops, 1.0)) * 12.0, -2.0, 12.0)
			score += Vector2(dir).length() * 0.25
			if score > best_score:
				best_score = score
				best = Vector2i(nx, ny)
	return best


static func _pick_overseas_target(ws: WorldState, nation: NationData, tick: int) -> Vector2i:
	var cands: Array[Vector2i] = ws.ai_spawn_candidates
	if cands.is_empty():
		return Vector2i(-1, -1)
	var cap_lm: int = ws.landmass_grid[nation.capital_cell.y * ws.sim_width + nation.capital_cell.x]
	var best := Vector2i(-1, -1)
	var best_d2 := 15625.0  # <= 125 sim cells
	var start: int = (tick + nation.id * 5) % cands.size()
	for i in range(mini(cands.size(), 10)):
		var pt: Vector2i = cands[(start + i) % cands.size()]
		var idx: int = pt.y * ws.sim_width + pt.x
		if not ws.is_land_cell(pt.x, pt.y) or ws.landmass_grid[idx] == cap_lm:
			continue
		var own: int = ws.owner_grid[idx]
		if own == nation.id:
			continue
		if own != 0:
			if ws.are_allied(nation.id, own):
				continue
			var en: NationData = ws.nations.get(own, null)
			if en == null or en.troops >= nation.troops * 0.95:
				continue
		var d2: float = float((pt.x - nation.capital_cell.x) * (pt.x - nation.capital_cell.x) + (pt.y - nation.capital_cell.y) * (pt.y - nation.capital_cell.y))
		if d2 < best_d2:
			best_d2 = d2
			best = pt
	if best.x < 0:
		for other_id: int in ws.nations.keys():
			if other_id == nation.id or ws.are_allied(nation.id, other_id):
				continue
			var other_n: NationData = ws.nations[other_id]
			if not other_n.alive or other_n.capital_cell.x < 0 or other_n.troops >= nation.troops * 0.95:
				continue
			var o_idx: int = other_n.capital_cell.y * ws.sim_width + other_n.capital_cell.x
			if ws.landmass_grid[o_idx] != cap_lm:
				var od2: float = Vector2(other_n.capital_cell - nation.capital_cell).length_squared()
				if od2 < best_d2:
					best_d2 = od2
					best = other_n.capital_cell
	return best
