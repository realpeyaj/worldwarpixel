class_name StructureData
extends RefCounted
## Economic, defensive, and strategic structures strictly capped at Level 10.
## Initial placement takes ~1.2s; all level upgrades (Lv.2..10) apply instantly.

const TYPE_TOWN := "town"
const TYPE_PORT := "port"
const TYPE_FACTORY := "factory"
const TYPE_DEFENSE_POST := "defense_post"
const TYPE_MISSILE_SILO := "missile_silo"
const TYPE_SAM_LAUNCHER := "sam_launcher"
const MAX_LEVEL := 10
const MAX_SILO_SAM_LEVEL := 3
const SAM_MAX_AMMO := 2

const BASE_BUILD_COST := {
	TYPE_TOWN: 125000.0,
	TYPE_PORT: 125000.0,
	TYPE_FACTORY: 125000.0,
	TYPE_DEFENSE_POST: 50000.0,
	TYPE_MISSILE_SILO: 1000000.0,
	TYPE_SAM_LAUNCHER: 1500000.0,
}
const MAX_BUILD_COST := {
	TYPE_TOWN: 1000000.0,
	TYPE_PORT: 1000000.0,
	TYPE_FACTORY: 1000000.0,
	TYPE_DEFENSE_POST: 1000000.0,
	TYPE_MISSILE_SILO: 1000000.0,
	TYPE_SAM_LAUNCHER: 1500000.0,
}


static func peso_symbol() -> String:
	if ThemeDB.fallback_font != null and ThemeDB.fallback_font.has_char(0x20B1):
		return "₱"
	return "P"


static func format_pesos(amount: float) -> String:
	var sym: String = peso_symbol()
	var a: float = maxf(0.0, amount)
	if a >= 1000000.0:
		var s := "%.1fM" % (a / 1000000.0)
		return sym + s.replace(".0M", "M")
	if a >= 1000.0:
		var s := "%.1fk" % (a / 1000.0)
		return sym + s.replace(".0k", "k")
	return sym + ("%d" % int(round(a)))

var id: int = 0
var nation_id: int = 0
var type: String = TYPE_TOWN
var cell: Vector2i = Vector2i.ZERO
var level: int = 0
var target_level: int = 1
var is_constructing: bool = true
var progress_ticks: int = 0
var total_build_ticks: int = 29

var terrain_bonus: float = 1.0
var connection_bonus: float = 1.0   # Factory multiplier from connected Towns & Ports
var factory_boost: float = 1.0      # Town/Port multiplier from linked Factories
var connected_count: int = 0
var bridge_count: int = 0

var trade_cooldown_ticks: int = 0
var action_cooldown_ticks: int = 0
var train_cooldown_ticks: int = 0
var sam_ammo: int = SAM_MAX_AMMO
var sam_reload_ticks: int = 0
var income_popup_accum: float = 0.0
var active_ship_ids: Array[int] = []
var water_cell: Vector2i = Vector2i(-1, -1)


func get_display_name() -> String:
	match type:
		TYPE_TOWN:
			return "Town"
		TYPE_PORT:
			return "Port"
		TYPE_FACTORY:
			return "Factory"
		TYPE_DEFENSE_POST:
			return "Defense Post"
		TYPE_MISSILE_SILO:
			return "Missile Silo"
		TYPE_SAM_LAUNCHER:
			return "SAM Launcher"
	return type.capitalize()


func get_world_pos() -> Vector2:
	return Vector2((float(cell.x) + 0.5) * 2.0, (float(cell.y) + 0.5) * 2.0)


func get_progress_ratio() -> float:
	if not is_constructing or total_build_ticks <= 0:
		return 1.0
	return clampf(float(progress_ticks) / float(total_build_ticks), 0.0, 1.0)


func get_gold_per_sec() -> float:
	if level <= 0:
		return 0.0
	match type:
		TYPE_TOWN:
			return (620.0 + float(level) * 520.0) * factory_boost
		TYPE_PORT:
			return (480.0 + float(level) * 400.0) * factory_boost
		TYPE_FACTORY:
			return (980.0 + float(level) * 900.0) * terrain_bonus * connection_bonus
	return 0.0


func get_max_troops_bonus() -> float:
	if type != TYPE_TOWN or level <= 0:
		return 0.0
	return 240.0 * float(level)


func get_troops_per_sec_bonus() -> float:
	if type != TYPE_TOWN or level <= 0:
		return 0.0
	return 2.4 * float(level)


func get_supply_radius() -> float:
	if type == TYPE_TOWN and level > 0:
		return 55.0 + float(level) * 8.0
	if type == TYPE_PORT and level > 0:
		return 50.0 + float(level) * 5.0
	return 0.0


func get_defense_radius() -> float:
	if type == TYPE_DEFENSE_POST and level > 0:
		return 24.0 + float(level) * 3.5
	return 0.0


func get_defense_multiplier() -> float:
	if type == TYPE_DEFENSE_POST and level > 0:
		return 1.85 + float(level - 1) * 0.22
	return 1.0


static func get_max_level_for_type(s_type: String) -> int:
	if s_type == TYPE_MISSILE_SILO or s_type == TYPE_SAM_LAUNCHER:
		return MAX_SILO_SAM_LEVEL
	return MAX_LEVEL


func get_max_level() -> int:
	return get_max_level_for_type(type)


static func get_sam_radius_for_level(lvl: int) -> float:
	if lvl <= 0:
		return 0.0
	return 18.0 * pow(1.15, float(clampi(lvl, 1, MAX_SILO_SAM_LEVEL) - 1))


func get_sam_radius() -> float:
	if type == TYPE_SAM_LAUNCHER and level > 0:
		return get_sam_radius_for_level(level)
	return 0.0


static func get_sam_cooldown_for_level(lvl: int) -> int:
	# Level 1 SAM CD nerfed by +40% (342 -> 480 ticks = 20.0s), then -12.5% (10-15%) per upgrade up to Lv.3
	var c_lvl: int = clampi(maxi(1, lvl), 1, MAX_SILO_SAM_LEVEL)
	return maxi(240, int(round(480.0 * pow(0.875, float(c_lvl - 1)))))


func get_sam_cooldown_ticks() -> int:
	return get_sam_cooldown_for_level(level)


static func get_silo_cooldown_for_level(lvl: int) -> int:
	# Infinite range; each upgrade reduces cooldown by 10% up to Max Level 3
	var c_lvl: int = clampi(maxi(1, lvl), 1, MAX_SILO_SAM_LEVEL)
	return maxi(240, int(round(456.0 * pow(0.90, float(c_lvl - 1)))))


func get_silo_cooldown_ticks() -> int:
	return get_silo_cooldown_for_level(level)


func get_silo_max_range() -> float:
	return 999999.0


func get_ship_speed() -> float:
	return 18.0 + float(maxi(1, level)) * 1.2


func get_factory_base_radius(for_level: int = -1) -> float:
	var lvl: int = maxi(1, level) if for_level < 0 else maxi(1, for_level)
	return 38.0 + float(lvl) * 7.0


func get_factory_radius_at_angle(angle: float, for_level: int = -1) -> float:
	var base_r: float = get_factory_base_radius(for_level)
	var s1: float = float((id * 37) % 628) * 0.01
	var s2: float = float((id * 91 + 17) % 628) * 0.01
	var s3: float = float((id * 53 + 41) % 628) * 0.01
	var wobble: float = 1.0 + 0.14 * sin(3.0 * angle + s1) + 0.09 * cos(5.0 * angle + s2) + 0.05 * sin(7.0 * angle + s3)
	return base_r * wobble


func is_cell_in_factory_range(target_cell: Vector2i) -> bool:
	var delta := Vector2(target_cell - cell)
	var dist: float = delta.length()
	if dist <= 0.01:
		return true
	return dist <= get_factory_radius_at_angle(delta.angle())


func get_organic_range_polygon(sample_count: int = 56, for_level: int = -1) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sample_count)
	var origin: Vector2 = get_world_pos()
	for i in range(sample_count):
		var ang: float = (float(i) / float(sample_count)) * TAU
		var r_world: float = get_factory_radius_at_angle(ang, for_level) * 2.0
		pts[i] = origin + Vector2(cos(ang), sin(ang)) * r_world
	return pts


func can_upgrade() -> bool:
	return (not is_constructing) and level >= 1 and level < get_max_level()


func get_next_upgrade_cost() -> float:
	if level >= get_max_level():
		return 0.0
	return get_upgrade_cost(type, level + 1)


func get_next_level_summary() -> String:
	var max_l: int = get_max_level()
	if level >= max_l:
		return "Maximum Level %d reached." % max_l
	var nxt: int = level + 1
	match type:
		TYPE_TOWN:
			return "Lv.%d gains: +%s/s, +240 Pop Cap, +2.4/s Troops, +8 Supply" % [nxt, format_pesos(520.0)]
		TYPE_PORT:
			return "Lv.%d gains: %d Trade Ships, +%s/s, +1.2 Spd, +8%% Trade" % [nxt, get_max_trade_ships(nxt), format_pesos(400.0)]
		TYPE_FACTORY:
			return "Lv.%d gains: +%s/s base, +7 Organic Range, +Synergy" % [nxt, format_pesos(900.0)]
		TYPE_DEFENSE_POST:
			return "Lv.%d gains: %.2fx Defense, +3.5 Fortify Radius" % [nxt, 1.85 + float(nxt - 1) * 0.22]
		TYPE_MISSILE_SILO:
			return "Lv.%d/%d gains: -10%% Silo Reload Cooldown (%.1fs)" % [nxt, max_l, float(get_silo_cooldown_for_level(nxt)) / 24.0]
		TYPE_SAM_LAUNCHER:
			return "Lv.%d/%d gains: +15%% Radar Range (%.1f), -12.5%% Reload CD (%.1fs)" % [nxt, max_l, get_sam_radius_for_level(nxt), float(get_sam_cooldown_for_level(nxt)) / 24.0]
	return ""


static func get_build_cost(s_type: String) -> float:
	return float(BASE_BUILD_COST.get(s_type, 125000.0))


static func get_scaled_build_cost(s_type: String, owned_count: int) -> float:
	var base_c: float = get_build_cost(s_type)
	var cap_c: float = float(MAX_BUILD_COST.get(s_type, base_c))
	return minf(cap_c, round(base_c * pow(2.0, mini(owned_count, 6))))


static func get_upgrade_cost(s_type: String, next_level: int) -> float:
	var base: float = get_build_cost(s_type)
	return round(base * (0.40 + 0.30 * float(next_level)))


static func get_build_ticks(next_level: int) -> int:
	return 29 if next_level <= 1 else 0


static func get_max_trade_ships(lvl: int) -> int:
	if lvl <= 0:
		return 0
	return clampi(lvl, 1, MAX_LEVEL)


static func get_trade_payout(lvl: int, is_foreign: bool, boost: float = 1.0) -> float:
	var base := 3600.0 + float(lvl) * 1400.0
	return round(base * (1.45 if is_foreign else 1.0) * boost)


static func get_distance_trade_payout(route_dist_px: float, port_lvl: int = 1, boost: float = 1.0) -> float:
	var base_p: float = 2400.0 + pow(maxf(route_dist_px, 10.0), 1.12) * 5.2
	var lvl_mult: float = 1.0 + float(maxi(0, port_lvl - 1)) * 0.08
	return round(base_p * lvl_mult * boost)
