class_name ShipUnit
extends RefCounted
## Maritime vessel representing Port container trade ships, assault warships, and landing vessels.

const KIND_TRADE := "trade"
const KIND_LANDING := "landing"
const KIND_WARSHIP := "warship"
const WARSHIP_BASE_COST := 250000.0
const WARSHIP_MAX_COST := 750000.0

var id: int = 0
var kind: String = KIND_TRADE
var nation_id: int = 0
var source_port_id: int = 0
var dest_port_id: int = 0

var waypoints: PackedVector2Array = PackedVector2Array()
var waypoint_index: int = 0
var position: Vector2 = Vector2.ZERO
var heading: float = 0.0
var base_speed_px_per_sec: float = 10.5
var speed_px_per_sec: float = 10.5

var gold_value: float = 15000.0
var is_foreign_trade: bool = false
var is_allied_trade: bool = false
var returning: bool = false
var captured: bool = false

var troops_carried: float = 0.0
var landing_cell: Vector2i = Vector2i(-1, -1)
var target_cell: Vector2i = Vector2i(-1, -1)
var target_owner_id: int = 0

var hp: float = 100.0
var max_hp: float = 100.0
var ship_level: int = 1
var xp: int = 0
var fire_cooldown_ticks: int = 0
var patrol_center: Vector2 = Vector2.ZERO
var patrol_radius: float = 72.0
var manual_moving: bool = false
var target_ship_id: int = 0
var repair_retreating: bool = false
var docked_port_id: int = 0
var last_manual_order_tick: int = -100
var safe_from_pirates_ticks: int = 0

var active: bool = true


static func get_warship_cost(owned_warships: int) -> float:
	return minf(WARSHIP_MAX_COST, round(WARSHIP_BASE_COST * pow(2.0, mini(owned_warships, 4))))


func refresh_warship_speed() -> void:
	if kind != KIND_WARSHIP or base_speed_px_per_sec <= 0.0:
		return
	speed_px_per_sec = base_speed_px_per_sec * (1.0 + 0.05 * float(maxi(1, ship_level) - 1))


func add_xp(points: int) -> bool:
	xp += points
	var old_level: int = ship_level
	if xp >= 5:
		ship_level = 3
		max_hp = 190.0
	elif xp >= 2:
		ship_level = 2
		max_hp = 140.0
	if ship_level > old_level:
		hp = minf(max_hp, hp + 35.0)
		refresh_warship_speed()
		return true
	return false


func get_shell_damage() -> float:
	return 26.0 * (1.0 + 0.35 * float(ship_level - 1))
