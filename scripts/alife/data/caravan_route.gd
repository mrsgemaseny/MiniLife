class_name CaravanRoute
extends AlifeRecord

var route_id: String = ""
var from_id: String = ""
var to_id: String = ""
var cargo: Dictionary = {}
var base_success_chance: float = 0.8
var success_history: Array = []
var progress: float = 0.0
var active: bool = false
var next_departure_hour: float = 0.0
var investment: int = 1500
var successful_trips: int = 0
var guards: Array = []
var merchant_id: String = ""
var at_id: String = ""
var destination_id: String = ""
var paid_investment: bool = false
var invested_total: int = 0
var recovered_investment: int = 0
var cargo_cost: int = 0
var departure_hour: float = 0.0
var risk_checked: bool = false
var outbound_distance: float = 0.0
var attacked_by_player: bool = false
var pack_state: Dictionary = {}
var wrecks: Array = []
var ambushers: Array = []
var ambush_phase: String = "none"
var ambush_started_hour: float = 0.0
var ambush_origin: Vector2i = Vector2i.ZERO
var trip_id: int = 0

func _fields() -> Array[String]:
	return ["route_id", "from_id", "to_id", "cargo", "base_success_chance", "success_history", "progress", "active", "next_departure_hour", "investment", "successful_trips", "guards", "merchant_id", "at_id", "destination_id", "paid_investment", "invested_total", "recovered_investment", "cargo_cost", "departure_hour", "risk_checked", "outbound_distance", "attacked_by_player", "pack_state", "wrecks", "ambushers", "ambush_phase", "ambush_started_hour", "ambush_origin", "trip_id"]

static func from_dict(data: Dictionary) -> CaravanRoute:
	var result: CaravanRoute = CaravanRoute.new()
	result.restore(data)
	for item: String in result.cargo:
		result.cargo[item] = maxi(0, int(result.cargo[item]))
	return result
