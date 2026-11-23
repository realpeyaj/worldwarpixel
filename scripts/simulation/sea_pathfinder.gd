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
var _world_scale: float = 2.0
var _sim_shift: int = 0
var nav_grid: PackedByteArray = PackedByteArray()
var _route_cache: Dictionary = {}
var _trade_route_cache: Dictionary = {}
var _g_cost: PackedFloat32Array = PackedFloat32Array()
var _parent: PackedInt32Array = PackedInt32Array()
var _seen_stamp: PackedInt32Array = PackedInt32Array()
var _closed_stamp: PackedInt32Array = PackedInt32Array()
var _heap_f: PackedFloat32Array = PackedFloat32Array()
var _heap_idx: PackedInt32Array = PackedInt32Array()
var _stamp_id: int = 0


func load_nav_grid(path: String, w: int = 1024, h: int = 512) -> bool:
	nav_width = w
	nav_height = h
	_world_scale = 2048.0 / float(maxi(w, 1))
	_sim_shift = 0 if w >= 1024 else 1
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open ocean nav grid: %s" % path)
		return false
	nav_grid = f.get_buffer(w * h)
	f.close()
	_route_cache.clear()
	_trade_route_cache.clear()
	_ensure_scratch_buffers(w * h)
	return nav_grid.size() == w * h


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
	_heap_f.append(_octile(start_nav.x, start_nav.y, end_nav.x, end_nav.y))
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
			if not is_navigable(nx, ny):
				continue
			# Strict corner-cut guard: never slice diagonally past any land cell corner
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
				var f: float = new_g + _octile(nx, ny, end_nav.x, end_nav.y) * 1.16
				_heap_idx.append(n_idx)
				_heap_f.append(f)
				_sift_up(_heap_f, _heap_idx, _heap_idx.size() - 1)

	if not found:
		return PackedVector2Array()

	var raw_cells: Array[Vector2i] = []
	var trace: int = end_idx
	while trace != -1:
		raw_cells.append(Vector2i(trace % nav_width, int(trace / nav_width)))
		if trace == start_idx:
			break
		trace = _parent[trace]
	raw_cells.reverse()

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

	if _route_cache.size() > 1024:
		_route_cache.clear()
	_route_cache[cache_key] = out
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
		if _trade_route_cache.size() > 1024:
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

	if _trade_route_cache.size() > 1024:
		_trade_route_cache.clear()
	_trade_route_cache[cache_key] = final_route
	return final_route


func _segment_navigable(a: Vector2, b: Vector2) -> bool:
	var steps: int = maxi(2, int(ceil(a.distance_to(b) / 0.5)))
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
