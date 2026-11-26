class_name SeaPathfinder
extends RefCounted
## 8-directional A* pathfinder on strict 1024x512 water-only navigable ocean grid with corner-cut guards and route cache.

const DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]
const DIR_COSTS := [1.0, 1.0, 1.0, 1.0, 1.41421356, 1.41421356, 1.41421356, 1.41421356]

var nav_width: int = 1024
var nav_height: int = 512
var _coarse_w: int = 256
var _coarse_h: int = 128
var _world_scale: float = 2.0
var _sim_shift: int = 0
var nav_grid: PackedByteArray = PackedByteArray()
var _coarse_astar: AStarGrid2D = null
var _fine_astar: AStarGrid2D = null
var _coarse_rep_x: PackedInt32Array = PackedInt32Array()
var _coarse_rep_y: PackedInt32Array = PackedInt32Array()
var _route_cache: Dictionary = {}
var _trade_route_cache: Dictionary = {}
var _g_cost: PackedFloat32Array = PackedFloat32Array()
var _parent: PackedInt32Array = PackedInt32Array()
var _seen_stamp: PackedInt32Array = PackedInt32Array()
var _closed_stamp: PackedInt32Array = PackedInt32Array()
var _heap_f: PackedFloat32Array = PackedFloat32Array()
var _heap_idx: PackedInt32Array = PackedInt32Array()
var _stamp_id: int = 0


func load_nav_grid(path: String, w: int = 1024, h: int = 512, sim_w: int = 2048) -> bool:
	nav_width = w
	nav_height = h
	_coarse_w = maxi(1, w >> 2)
	_coarse_h = maxi(1, h >> 2)
	_world_scale = 2048.0 / float(maxi(w, 1))
	_sim_shift = 1 if sim_w >= w * 2 else 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open ocean nav grid: %s" % path)
		return false
	nav_grid = f.get_buffer(w * h)
	f.close()
	_route_cache.clear()
	_trade_route_cache.clear()
	_ensure_scratch_buffers(w * h)
	if nav_grid.size() != w * h:
		return false
	_build_astar_grids()
	return true


func _build_astar_grids() -> void:
	_coarse_astar = AStarGrid2D.new()
	_coarse_astar.region = Rect2i(0, 0, _coarse_w, _coarse_h)
	_coarse_astar.cell_size = Vector2(_world_scale * 4.0, _world_scale * 4.0)
	_coarse_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_coarse_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_coarse_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_coarse_astar.jumping_enabled = false
	_coarse_astar.update()
	_coarse_rep_x.resize(_coarse_w * _coarse_h)
	_coarse_rep_x.fill(-1)
	_coarse_rep_y.resize(_coarse_w * _coarse_h)
	_coarse_rep_y.fill(-1)
	for cy in range(_coarse_h):
		var y_base: int = cy * 4
		var c_row: int = cy * _coarse_w
		for cx in range(_coarse_w):
			var x_base: int = cx * 4
			var has_water := false
			var has_coastal := false
			var bx := -1
			var by := -1
			var best_s := -999
			for dy in range(4):
				var py: int = y_base + dy
				if py >= nav_height:
					continue
				var row_off: int = py * nav_width + x_base
				for dx in range(4):
					var px: int = x_base + dx
					if px >= nav_width:
						continue
					var v: int = nav_grid[row_off + dx]
					if v > 0:
						has_water = true
						var sc: int = v * 10 - absi(dx - 1) - absi(dy - 1)
						if sc > best_s:
							best_s = sc
							bx = px
							by = py
					if v < 2:
						has_coastal = true
			if not has_water:
				_coarse_astar.set_point_solid(Vector2i(cx, cy), true)
			else:
				_coarse_rep_x[c_row + cx] = bx
				_coarse_rep_y[c_row + cx] = by
				if has_coastal:
					_coarse_astar.set_point_weight_scale(Vector2i(cx, cy), 1.85)

	_fine_astar = null
	_ensure_fine_astar()


func _ensure_fine_astar() -> AStarGrid2D:
	if _fine_astar != null:
		return _fine_astar
	_fine_astar = AStarGrid2D.new()
	_fine_astar.region = Rect2i(0, 0, nav_width, nav_height)
	_fine_astar.cell_size = Vector2(_world_scale, _world_scale)
	_fine_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_fine_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_fine_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_fine_astar.jumping_enabled = false
	_fine_astar.update()
	for y in range(nav_height):
		var row_off: int = y * nav_width
		var x := 0
		while x < nav_width:
			var v: int = nav_grid[row_off + x]
			if v == 0:
				var x0: int = x
				x += 1
				while x < nav_width and nav_grid[row_off + x] == 0:
					x += 1
				_fine_astar.fill_solid_region(Rect2i(x0, y, x - x0, 1), true)
			elif v == 1:
				var x0: int = x
				x += 1
				while x < nav_width and nav_grid[row_off + x] == 1:
					x += 1
				_fine_astar.fill_weight_scale_region(Rect2i(x0, y, x - x0, 1), 1.85)
			else:
				x += 1
	return _fine_astar


func _ensure_scratch_buffers(total_cells: int) -> void:
	if _seen_stamp.size() == total_cells:
		return
	_g_cost.resize(total_cells)
	_parent.resize(total_cells)
	_seen_stamp.resize(total_cells)
	_seen_stamp.fill(0)
	_closed_stamp.resize(total_cells)
	_closed_stamp.fill(0)
	_stamp_id = 0


func is_navigable(nx: int, ny: int) -> bool:
	if nx < 0 or ny < 0 or nx >= nav_width or ny >= nav_height:
		return false
	return nav_grid[ny * nav_width + nx] > 0


func is_world_pos_navigable(world_pos: Vector2) -> bool:
	var nx: int = int(floor(world_pos.x / _world_scale))
	var ny: int = int(floor(world_pos.y / _world_scale))
	return is_navigable(nx, ny)


func sim_to_nav(sim_cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(sim_cell.x >> _sim_shift, 0, nav_width - 1), clampi(sim_cell.y >> _sim_shift, 0, nav_height - 1))


func nav_to_world(nav_cell: Vector2i) -> Vector2:
	return Vector2((float(nav_cell.x) + 0.5) * _world_scale, (float(nav_cell.y) + 0.5) * _world_scale)


func find_nearest_nav_cell(sim_cell: Vector2i, max_radius: int = 14) -> Vector2i:
	var center: Vector2i = sim_to_nav(sim_cell)
	if is_navigable(center.x, center.y):
		return center
	var best := Vector2i(-1, -1)
	var best_d2: int = 999999
	for dy in range(-max_radius, max_radius + 1):
		for dx in range(-max_radius, max_radius + 1):
			var nx: int = center.x + dx
			var ny: int = center.y + dy
			if is_navigable(nx, ny):
				var d2: int = dx * dx + dy * dy
				if d2 < best_d2:
					best_d2 = d2
					best = Vector2i(nx, ny)
	return best


func find_path(start_nav: Vector2i, end_nav: Vector2i) -> PackedVector2Array:
	if not is_navigable(start_nav.x, start_nav.y) or not is_navigable(end_nav.x, end_nav.y):
		return PackedVector2Array()
	if start_nav == end_nav:
		return PackedVector2Array([nav_to_world(start_nav)])

	var start_idx: int = start_nav.y * nav_width + start_nav.x
	var end_idx: int = end_nav.y * nav_width + end_nav.x
	var cache_key: int = (start_idx << 20) | end_idx
	if _route_cache.has(cache_key):
		return _route_cache[cache_key]
	var rev_key: int = (end_idx << 20) | start_idx
	if _route_cache.has(rev_key):
		var rev_src: PackedVector2Array = _route_cache[rev_key]
		var rev_out := PackedVector2Array()
		rev_out.resize(rev_src.size())
		for i in range(rev_src.size()):
			rev_out[i] = rev_src[rev_src.size() - 1 - i]
		_cache_route(cache_key, rev_out)
		return rev_out

	if absi(start_nav.x - end_nav.x) <= 48 and absi(start_nav.y - end_nav.y) <= 48:
		if _nav_line_clear(start_nav, end_nav):
			var direct := PackedVector2Array([nav_to_world(start_nav), nav_to_world(end_nav)])
			_cache_route(cache_key, direct)
			return direct
		var near_cells: Array[Vector2i] = _run_local_fine_astar(start_nav, end_nav, 18)
		if not near_cells.is_empty():
			var near_out := _collapse_cells_to_world(near_cells)
			_cache_route(cache_key, near_out)
			return near_out

	var c_start := Vector2i(clampi(start_nav.x >> 2, 0, _coarse_w - 1), clampi(start_nav.y >> 2, 0, _coarse_h - 1))
	var c_end := Vector2i(clampi(end_nav.x >> 2, 0, _coarse_w - 1), clampi(end_nav.y >> 2, 0, _coarse_h - 1))
	var temp_blocked: Array[Vector2i] = []
	for _retry in range(2):
		var c_path: Array[Vector2i] = _coarse_astar.get_id_path(c_start, c_end)
		if c_path.is_empty():
			break

		var anchors: Array[Vector2i] = [start_nav]
		var anchor_coarse: Array[Vector2i] = [c_start]
		for i in range(1, c_path.size() - 1):
			var cp: Vector2i = c_path[i]
			var c_idx: int = cp.y * _coarse_w + cp.x
			var rx: int = _coarse_rep_x[c_idx]
			var ry: int = _coarse_rep_y[c_idx]
			if rx >= 0 and ry >= 0:
				var pt := Vector2i(rx, ry)
				if pt != anchors[anchors.size() - 1] and pt != end_nav:
					anchors.append(pt)
					anchor_coarse.append(cp)
		if end_nav != anchors[anchors.size() - 1]:
			anchors.append(end_nav)
			anchor_coarse.append(c_end)

		var out := PackedVector2Array([nav_to_world(anchors[0])])
		var stitch_ok := true
		var fail_a := Vector2i(-1, -1)
		var fail_b := Vector2i(-1, -1)
		for i in range(anchors.size() - 1):
			var a: Vector2i = anchors[i]
			var b: Vector2i = anchors[i + 1]
			if _nav_line_clear(a, b):
				out.append(nav_to_world(b))
			else:
				var seg_cells: Array[Vector2i] = _run_local_fine_astar(a, b, 14)
				if seg_cells.is_empty():
					stitch_ok = false
					fail_a = anchor_coarse[i]
					fail_b = anchor_coarse[i + 1]
					break
				var seg_w: PackedVector2Array = _collapse_cells_to_world(seg_cells)
				for si in range(1, seg_w.size()):
					out.append(seg_w[si])

		if stitch_ok and out.size() >= 2:
			for bc: Vector2i in temp_blocked:
				_coarse_astar.set_point_solid(bc, false)
			_cache_route(cache_key, out)
			return out

		var blocked_any := false
		for bc: Vector2i in [fail_a, fail_b]:
			if bc.x >= 0 and bc != c_start and bc != c_end and not _coarse_astar.is_point_solid(bc):
				_coarse_astar.set_point_solid(bc, true)
				temp_blocked.append(bc)
				blocked_any = true
		if not blocked_any:
			break

	for bc: Vector2i in temp_blocked:
		_coarse_astar.set_point_solid(bc, false)

	var fine_cells: Array[Vector2i] = _ensure_fine_astar().get_id_path(start_nav, end_nav)
	var fallback := _collapse_cells_to_world(fine_cells) if not fine_cells.is_empty() else PackedVector2Array()
	_cache_route(cache_key, fallback)
	return fallback


func _cache_route(key: int, route: PackedVector2Array) -> void:
	if _route_cache.size() > 4096:
		_route_cache.clear()
	_route_cache[key] = route


func _nav_line_clear(a: Vector2i, b: Vector2i) -> bool:
	var dx: int = b.x - a.x
	var dy: int = b.y - a.y
	var steps: int = maxi(absi(dx), absi(dy))
	if steps == 0:
		return is_navigable(a.x, a.y)
	var px: int = a.x
	var py: int = a.y
	for s in range(1, steps + 1):
		var nx: int = a.x + int(round(float(dx * s) / float(steps)))
		var ny: int = a.y + int(round(float(dy * s) / float(steps)))
		if not is_navigable(nx, ny):
			return false
		if nx != px and ny != py:
			if not is_navigable(px, ny) or not is_navigable(nx, py):
				return false
		px = nx
		py = ny

	var wa: Vector2 = nav_to_world(a)
	var wb: Vector2 = nav_to_world(b)
	var w_vec: Vector2 = wb - wa
	var w_dist: float = w_vec.length()
	if w_dist > 0.5:
		var perp := Vector2(-w_vec.y, w_vec.x) / w_dist * 0.5
		var w_steps: int = maxi(2, int(ceil(w_dist)))
		for s in range(1, w_steps):
			var pt: Vector2 = wa.lerp(wb, float(s) / float(w_steps))
			if not is_world_pos_navigable(pt):
				return false
			if not is_world_pos_navigable(pt + perp) or not is_world_pos_navigable(pt - perp):
				return false
	return true


func _run_local_fine_astar(a: Vector2i, b: Vector2i, pad: int) -> Array[Vector2i]:
	var x0: int = maxi(0, mini(a.x, b.x) - pad)
	var y0: int = maxi(0, mini(a.y, b.y) - pad)
	var x1: int = mini(nav_width - 1, maxi(a.x, b.x) + pad)
	var y1: int = mini(nav_height - 1, maxi(a.y, b.y) + pad)
	var start_idx: int = a.y * nav_width + a.x
	var end_idx: int = b.y * nav_width + b.x
	var total_cells: int = nav_width * nav_height
	_ensure_scratch_buffers(total_cells)
	_stamp_id += 1
	if _stamp_id >= 2000000000:
		_seen_stamp.fill(0)
		_closed_stamp.fill(0)
		_stamp_id = 1
	var sid: int = _stamp_id

	_heap_f.resize(0)
	_heap_idx.resize(0)
	_seen_stamp[start_idx] = sid
	_g_cost[start_idx] = 0.0
	_parent[start_idx] = -1
	_heap_f.append(_octile(a.x, a.y, b.x, b.y))
	_heap_idx.append(start_idx)

	var found := false
	while not _heap_idx.is_empty():
		var curr: int = _heap_idx[0]
		var last: int = _heap_idx.size() - 1
		if last > 0:
			_heap_idx[0] = _heap_idx[last]
			_heap_f[0] = _heap_f[last]
		_heap_idx.resize(last)
		_heap_f.resize(last)
		if last > 1:
			_sift_down(_heap_f, _heap_idx, 0)

		if _closed_stamp[curr] == sid:
			continue
		_closed_stamp[curr] = sid

		if curr == end_idx:
			found = true
			break

		var cx: int = curr % nav_width
		var cy: int = int(curr / nav_width)
		var curr_g: float = _g_cost[curr]

		for d_i in range(8):
			var d: Vector2i = DIRS[d_i]
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < x0 or nx > x1 or ny < y0 or ny > y1:
				continue
			if not is_navigable(nx, ny):
				continue
			if d.x != 0 and d.y != 0:
				if not is_navigable(cx + d.x, cy) or not is_navigable(cx, cy + d.y):
					continue
			var n_idx: int = ny * nav_width + nx
			if _closed_stamp[n_idx] == sid:
				continue
			var tier_cost: float = 1.0 if nav_grid[n_idx] >= 2 else 1.85
			var new_g: float = curr_g + float(DIR_COSTS[d_i]) * tier_cost
			if _seen_stamp[n_idx] != sid or new_g < _g_cost[n_idx]:
				_seen_stamp[n_idx] = sid
				_g_cost[n_idx] = new_g
				_parent[n_idx] = curr
				var f: float = new_g + _octile(nx, ny, b.x, b.y) * 1.16
				_heap_idx.append(n_idx)
				_heap_f.append(f)
				_sift_up(_heap_f, _heap_idx, _heap_idx.size() - 1)

	if not found:
		return []

	var raw_cells: Array[Vector2i] = []
	var trace: int = end_idx
	while trace != -1:
		raw_cells.append(Vector2i(trace % nav_width, int(trace / nav_width)))
		if trace == start_idx:
			break
		trace = _parent[trace]
	raw_cells.reverse()
	return raw_cells


func _collapse_cells_to_world(raw_cells: Array[Vector2i]) -> PackedVector2Array:
	# Collapse strictly collinear steps so every segment stays strictly over navigable water
	var out := PackedVector2Array()
	if raw_cells.is_empty():
		return out
	out.append(nav_to_world(raw_cells[0]))
	for i in range(1, raw_cells.size() - 1):
		var d_prev: Vector2i = raw_cells[i] - raw_cells[i - 1]
		var d_next: Vector2i = raw_cells[i + 1] - raw_cells[i]
		if d_prev != d_next:
			out.append(nav_to_world(raw_cells[i]))
	if raw_cells.size() > 1:
		out.append(nav_to_world(raw_cells[raw_cells.size() - 1]))
	return out


func find_trade_path(start_nav: Vector2i, end_nav: Vector2i, lane_id: int = 0) -> PackedVector2Array:
	var lane: int = clampi(lane_id, 0, 4)
	if not is_navigable(start_nav.x, start_nav.y) or not is_navigable(end_nav.x, end_nav.y):
		return PackedVector2Array()
	if start_nav == end_nav:
		return PackedVector2Array([nav_to_world(start_nav)])

	var start_idx: int = start_nav.y * nav_width + start_nav.x
	var end_idx: int = end_nav.y * nav_width + end_nav.x
	var cache_key: int = (((start_idx << 20) | end_idx) << 3) | (lane + 1)
	if _trade_route_cache.has(cache_key):
		return _trade_route_cache[cache_key]

	var base_route: PackedVector2Array = find_path(start_nav, end_nav)
	if base_route.size() < 2:
		return base_route

	var direct_dist: float = Vector2(end_nav - start_nav).length()
	if direct_dist < 10.0:
		if _trade_route_cache.size() > 4096:
			_trade_route_cache.clear()
		_trade_route_cache[cache_key] = base_route
		return base_route

	# Single shared A* base route; lanes are derived by laterally displacing a densified copy (no extra searches)
	var dense := PackedVector2Array()
	dense.append(base_route[0])
	for i in range(1, base_route.size()):
		var a: Vector2 = base_route[i - 1]
		var b: Vector2 = base_route[i]
		var seg_len: float = a.distance_to(b)
		var pieces: int = maxi(1, int(ceil(seg_len / 20.0)))
		for p_i in range(1, pieces + 1):
			dense.append(a.lerp(b, float(p_i) / float(pieces)))

	var total_len: float = _route_length(dense)
	if total_len < 8.0:
		_trade_route_cache[cache_key] = base_route
		return base_route

	var lane_weights := [-0.55, -0.25, 0.0, 0.30, 0.65]
	var short_offsets := [-3.5, -1.8, 1.4, 2.4, 4.0]
	var mid_s: Dictionary = _sample_route_point_and_tangent(dense, 0.5)
	var mid_pos: Vector2 = mid_s["pos"]
	var mid_tan: Vector2 = mid_s["tangent"]
	var mid_perp := Vector2(-mid_tan.y, mid_tan.x)
	var mid_nav := Vector2(mid_pos.x / _world_scale, mid_pos.y / _world_scale)
	var plus_score := 0
	var minus_score := 0
	for probe_d: float in [6.0, 12.0, 20.0]:
		var p_plus := Vector2i(int(round(mid_nav.x + mid_perp.x * probe_d)), int(round(mid_nav.y + mid_perp.y * probe_d)))
		var p_minus := Vector2i(int(round(mid_nav.x - mid_perp.x * probe_d)), int(round(mid_nav.y - mid_perp.y * probe_d)))
		if is_navigable(p_plus.x, p_plus.y):
			plus_score += 3 if nav_grid[p_plus.y * nav_width + p_plus.x] >= 2 else 1
		if is_navigable(p_minus.x, p_minus.y):
			minus_score += 3 if nav_grid[p_minus.y * nav_width + p_minus.x] >= 2 else 1
	var sea_dir: float = 1.0 if plus_score >= minus_score else -1.0

	var total_off_nav: float = short_offsets[lane]
	if direct_dist >= 28.0:
		var open_push: float = sea_dir * clampf(direct_dist * 0.14, 5.0, 26.0)
		var lane_spread: float = lane_weights[lane] * clampf(direct_dist * 0.12, 4.0, 18.0)
		var wobble: float = 3.5 * float(((lane & 1) * 2) - 1)
		total_off_nav = open_push + lane_spread + wobble
	var total_off_w: float = total_off_nav * _world_scale

	var displaced := PackedVector2Array()
	displaced.resize(dense.size())
	displaced[0] = dense[0]
	var accum := 0.0
	for i in range(1, dense.size() - 1):
		accum += dense[i - 1].distance_to(dense[i])
		var t: float = accum / total_len
		var env: float = sin(PI * t)
		var tan_v: Vector2 = (dense[i + 1] - dense[i - 1]).normalized()
		var perp_v := Vector2(-tan_v.y, tan_v.x)
		var wave: float = 1.0 + 0.18 * sin(t * PI * 5.0 + float(lane) * 1.3)
		var chosen: Vector2 = dense[i]
		for shrink: float in [1.0, 0.75, 0.5, 0.3, 0.15, 0.0]:
			var cand: Vector2 = dense[i] + perp_v * (total_off_w * env * wave * shrink)
			if is_world_pos_navigable(cand):
				chosen = cand
				break
		displaced[i] = chosen
	displaced[dense.size() - 1] = dense[dense.size() - 1]

	var final_route: PackedVector2Array = displaced
	for i in range(displaced.size() - 1):
		if not _segment_navigable(displaced[i], displaced[i + 1]):
			final_route = base_route
			break

	if _trade_route_cache.size() > 4096:
		_trade_route_cache.clear()
	_trade_route_cache[cache_key] = final_route
	return final_route


func _segment_navigable(a: Vector2, b: Vector2) -> bool:
	var steps: int = maxi(2, int(ceil(a.distance_to(b))))
	for i in range(steps + 1):
		if not is_world_pos_navigable(a.lerp(b, float(i) / float(steps))):
			return false
	return true


static func _route_length(route: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(route.size() - 1):
		total += route[i].distance_to(route[i + 1])
	return total


static func _sample_route_point_and_tangent(route: PackedVector2Array, frac: float) -> Dictionary:
	if route.size() < 2:
		return {"pos": route[0] if route.size() == 1 else Vector2.ZERO, "tangent": Vector2.RIGHT}
	var total := 0.0
	for i in range(route.size() - 1):
		total += route[i].distance_to(route[i + 1])
	var target_d: float = clampf(frac, 0.0, 1.0) * total
	var accum := 0.0
	for i in range(route.size() - 1):
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		var d: float = a.distance_to(b)
		if accum + d >= target_d or i == route.size() - 2:
			var t: float = clampf((target_d - accum) / maxf(d, 0.001), 0.0, 1.0)
			var tang: Vector2 = (b - a).normalized() if d > 0.01 else Vector2.RIGHT
			return {"pos": a.lerp(b, t), "tangent": tang}
		accum += d
	return {"pos": route[route.size() - 1], "tangent": Vector2.RIGHT}


static func _octile(x0: int, y0: int, x1: int, y1: int) -> float:
	var dx: float = absf(float(x1 - x0))
	var dy: float = absf(float(y1 - y0))
	return maxf(dx, dy) + 0.41421356 * minf(dx, dy)


static func _sift_up(heap_f: PackedFloat32Array, heap_idx: PackedInt32Array, i: int) -> void:
	var idx: int = i
	while idx > 0:
		var p: int = (idx - 1) >> 1
		if heap_f[idx] < heap_f[p]:
			var tf: float = heap_f[idx]
			var ti: int = heap_idx[idx]
			heap_f[idx] = heap_f[p]
			heap_idx[idx] = heap_idx[p]
			heap_f[p] = tf
			heap_idx[p] = ti
			idx = p
		else:
			break


static func _sift_down(heap_f: PackedFloat32Array, heap_idx: PackedInt32Array, i: int) -> void:
	var n: int = heap_idx.size()
	var idx: int = i
	while true:
		var left: int = (idx << 1) + 1
		if left >= n:
			break
		var smallest: int = left
		var right: int = left + 1
		if right < n and heap_f[right] < heap_f[left]:
			smallest = right
		if heap_f[smallest] < heap_f[idx]:
			var tf: float = heap_f[idx]
			var ti: int = heap_idx[idx]
			heap_f[idx] = heap_f[smallest]
			heap_idx[idx] = heap_idx[smallest]
			heap_f[smallest] = tf
			heap_idx[smallest] = ti
			idx = smallest
		else:
			break
