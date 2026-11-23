class_name ExpansionOrder
extends RefCounted
## Active circular-organic territorial expansion advancing along a depth-bounded min-heap frontier.

var id: int = 0
var nation_id: int = 0
var target_cell: Vector2i = Vector2i.ZERO
var origin_dist_to_target: float = 0.0
var initial_troops: float = 0.0
var remaining_troops: float = 0.0
var cells_claimed: int = 0
var is_contested: bool = false
var enemy_nation_id: int = 0
var target_owner_id: int = 0
var supply_quality: String = "Normal"
var supply_factor: float = 1.0
var target_terrain: int = 2
var eta_seconds: float = 0.0
var front_world_pos: Vector2 = Vector2.ZERO
var last_troop_delta: float = 0.0
var troop_flash_timer: float = 0.0
var allow_fallout: bool = false
var active: bool = true

var _heap_scores: PackedFloat32Array = PackedFloat32Array()
var _heap_cells: PackedInt32Array = PackedInt32Array()
var _queued: Dictionary = {}
var _depths: Dictionary = {}


func push_frontier(cell_idx: int, score: float, depth: float = 0.0) -> void:
	if _queued.has(cell_idx):
		return
	_queued[cell_idx] = true
	_depths[cell_idx] = depth
	var idx: int = _heap_cells.size()
	_heap_cells.append(cell_idx)
	_heap_scores.append(score)
	_sift_up(idx)


func get_cell_depth(cell_idx: int) -> float:
	return float(_depths.get(cell_idx, 0.0))


func peek_best() -> int:
	return _heap_cells[0] if not _heap_cells.is_empty() else -1


func pop_best() -> int:
	var n: int = _heap_cells.size()
	if n == 0:
		return -1
	var best: int = _heap_cells[0]
	var last_idx: int = n - 1
	if last_idx > 0:
		_heap_cells[0] = _heap_cells[last_idx]
		_heap_scores[0] = _heap_scores[last_idx]
	_heap_cells.resize(last_idx)
	_heap_scores.resize(last_idx)
	if last_idx > 1:
		_sift_down(0)
	return best


func frontier_size() -> int:
	return _heap_cells.size()


func get_progress_percent() -> float:
	if initial_troops <= 0.01:
		return 100.0
	return clampf((1.0 - remaining_troops / initial_troops) * 100.0, 0.0, 100.0)


func _sift_up(i: int) -> void:
	var idx: int = i
	while idx > 0:
		var parent: int = (idx - 1) >> 1
		if _heap_scores[idx] < _heap_scores[parent]:
			var tc: int = _heap_cells[idx]
			var ts: float = _heap_scores[idx]
			_heap_cells[idx] = _heap_cells[parent]
			_heap_scores[idx] = _heap_scores[parent]
			_heap_cells[parent] = tc
			_heap_scores[parent] = ts
			idx = parent
		else:
			break


func _sift_down(i: int) -> void:
	var n: int = _heap_cells.size()
	var idx: int = i
	while true:
		var left: int = (idx << 1) + 1
		if left >= n:
			break
		var smallest: int = left
		var right: int = left + 1
		if right < n and _heap_scores[right] < _heap_scores[left]:
			smallest = right
		if _heap_scores[smallest] < _heap_scores[idx]:
			var tc: int = _heap_cells[idx]
			var ts: float = _heap_scores[idx]
			_heap_cells[idx] = _heap_cells[smallest]
			_heap_scores[idx] = _heap_scores[smallest]
			_heap_cells[smallest] = tc
			_heap_scores[smallest] = ts
			idx = smallest
		else:
			break
