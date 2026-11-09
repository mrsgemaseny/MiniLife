class_name AlifeSettlement
extends AlifeRecord

enum Status { NORMAL, RAZED, RUINS, UNGOVERNED }
var settlement_id: String = ""
var name: String = ""
var owner_faction: String = ""
var tile: Vector2i = Vector2i.ZERO
var prosperity: float = 50.0
var population: int = 0
var status: int = Status.NORMAL
var settlement_type: String = "village"
var economy_type: String = "agricultural"
var treasury: int = 0
var food: float = 100.0
var garrison: int = 0
var fort_level: int = 0
var connections: Array = []
var stockpile: Dictionary = {}
var demand: Dictionary = {}
var footprint: int = 8
var street_plan: int = 0
var biome: String = "plains"
var status_changed_hour: float = 0.0
var market_funds: int = 0
var stock_tier: int = 1
var caravan_successes: int = 0
var famine: bool = false

func _fields() -> Array[String]:
	return ["settlement_id", "name", "owner_faction", "tile", "prosperity", "population", "status", "settlement_type", "economy_type", "treasury", "food", "garrison", "fort_level", "connections", "stockpile", "demand", "footprint", "street_plan", "biome", "status_changed_hour", "market_funds", "stock_tier", "caravan_successes", "famine"]

static func from_dict(data: Dictionary) -> AlifeSettlement:
	var result: AlifeSettlement = AlifeSettlement.new()
	result.restore(data)
	return result
