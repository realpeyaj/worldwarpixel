class_name NationData
extends RefCounted
## Active nation identity, area-weighted territory stats, Gold treasury, and troop pool.

var id: int = 0
var name: String = ""
var color: Color = Color.WHITE
var is_player: bool = false
var alive: bool = true

var capital_cell: Vector2i = Vector2i(-1, -1)
var cell_sum_x: float = 0.0
var cell_sum_y: float = 0.0
var label_cell: Vector2i = Vector2i(-1, -1)
var label_dirty: bool = true
var label_recompute_tick: int = -100
var owned_cell_count: int = 0
var owned_area_km2: float = 0.0
var territory_percent: float = 0.0

var gold: float = 250.0
var gold_per_sec: float = 1.0
var troops: float = 160.0
var max_troops: float = 320.0
var troops_per_sec: float = 4.0
var effective_troops_per_sec: float = 4.0

var structure_ids: Array[int] = []

var alliances: Dictionary = {}           # other_nid: int -> expiry_tick: int
var incoming_alliances: Dictionary = {}  # from_nid: int -> expiry_tick: int
var embargoes: Dictionary = {}           # other_nid: int -> true
var betrayal_until_tick: int = 0


func is_betrayer(tick: int) -> bool:
	return tick < betrayal_until_tick
