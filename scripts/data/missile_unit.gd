class_name MissileUnit
extends RefCounted
## Strategic ballistic missiles (Atom, H-Bomb, MIRV, split sub-warheads) and SAM interceptors.

const KIND_ATOM := "atom"
const KIND_HYDROGEN := "hydrogen"
const KIND_MIRV := "mirv"
const KIND_MIRV_WARHEAD := "mirv_warhead"
const KIND_SAM := "sam"

var id: int = 0
var kind: String = KIND_ATOM
var nation_id: int = 0
var source_structure_id: int = 0
var start_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var ctrl_pos: Vector2 = Vector2.ZERO
var ground_pos: Vector2 = Vector2.ZERO
var target_cell: Vector2i = Vector2i(-1, -1)
var pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var start_altitude: float = 0.0
var altitude: float = 0.0
var progress: float = 0.0
var speed_px_sec: float = 155.0
var blast_radius_sim: int = 20
var target_missile_id: int = 0
var target_nation_id: int = 0
var has_split: bool = false
var active: bool = true


func compute_ballistic_curve(is_sub_warhead: bool = false) -> void:
	var delta: Vector2 = target_pos - start_pos
	var dist: float = maxf(delta.length(), 16.0)
	var mid: Vector2 = (start_pos + target_pos) * 0.5
	var arch_h: float = clampf(dist * (0.28 if is_sub_warhead else 0.36), 18.0 if is_sub_warhead else 32.0, 75.0 if is_sub_warhead else 185.0)
	var lat_dir: float = 1.0 if (int(id) % 2 == 0) else -1.0
	var lat_off: float = lat_dir * clampf(dist * 0.14, 12.0, 40.0) if absf(delta.x) < absf(delta.y) * 0.85 else 0.0
	ctrl_pos = mid + Vector2(lat_off, -arch_h)
	heading = get_curve_heading(0.0)


func get_curve_point(t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * start_pos + 2.0 * u * t * ctrl_pos + t * t * target_pos


func get_curve_heading(t: float) -> float:
	var deriv: Vector2 = 2.0 * (1.0 - t) * (ctrl_pos - start_pos) + 2.0 * t * (target_pos - ctrl_pos)
	if deriv.length_squared() < 0.0001:
		return (target_pos - start_pos).angle()
	return deriv.angle()


static func get_cost(missile_kind: String) -> float:
	match missile_kind:
		KIND_ATOM:
			return 750000.0
		KIND_HYDROGEN:
			return 5000000.0
		KIND_MIRV:
			return 25000000.0
	return 750000.0


static func get_blast_radius(missile_kind: String) -> int:
	match missile_kind:
		KIND_ATOM:
			return 40
		KIND_HYDROGEN:
			return 72
		KIND_MIRV:
			return 36
		KIND_MIRV_WARHEAD:
			return 18
		KIND_SAM:
			return 0
	return 40


static func get_speed(missile_kind: String) -> float:
	match missile_kind:
		KIND_ATOM:
			return 96.0
		KIND_HYDROGEN:
			return 78.0
		KIND_MIRV:
			return 86.0
		KIND_MIRV_WARHEAD:
			return 112.0
		KIND_SAM:
			return 235.0
	return 96.0
