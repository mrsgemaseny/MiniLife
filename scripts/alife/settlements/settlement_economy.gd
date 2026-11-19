class_name SettlementEconomy
extends RefCounted

enum GrainRole { NONE, GROWER, CONSUMER }

const FOOD_PER_PERSON_HOUR: float = 0.2
const WHEAT_PER_PROVISION: float = 2.0
const PROVISION_RESERVE_HOURS: float = 6.0
const WHEAT_STORAGE_HOURS: float = 24.0
const WHEAT_PER_WORKER_HOUR: float = 1.5
const PRODUCTION: Dictionary = {
	"agricultural": {"food": 1.5, "wool": 0.1},
	"mining": {"iron_ore": 0.25, "stone": 0.5},
	"crafting": {"plank": 0.25},
	"trading": {"food": 0.5}
}
const PROCESSING: Array[Dictionary] = [
	{"input": "wool", "input_count": 2, "output": "cloth", "tier": 1},
	{"input": "iron_ore", "input_count": 2, "output": "iron_ingot", "tier": 3}
]

static func tick(settlement: AlifeSettlement, hours: float, grain_role: GrainRole = GrainRole.NONE) -> void:
	if settlement.status == AlifeSettlement.Status.RAZED or settlement.status == AlifeSettlement.Status.RUINS:
		return
	var workers: float = float(settlement.population) * 0.4
	var consumption: float = float(settlement.population) * FOOD_PER_PERSON_HOUR
	var output: Dictionary = PRODUCTION.get(settlement.economy_type, {})
	for item: String in output:
		var produced: float = float(output[item]) * workers * hours
		if item == "food":
			if grain_role == GrainRole.NONE:
				settlement.food += produced
		else:
			settlement.stockpile[item] = float(settlement.stockpile.get(item, 0.0)) + produced
	if settlement.economy_type == "crafting":
		for recipe: Dictionary in PROCESSING:
			if settlement.stock_tier < int(recipe["tier"]):
				continue
			var input: String = str(recipe["input"])
			var stock: float = float(settlement.stockpile.get(input, 0.0))
			var input_count: float = float(recipe["input_count"])
			var produced: float = minf(stock / input_count, workers * hours * 0.05)
			settlement.stockpile[input] = stock - produced * input_count
			var item: String = str(recipe["output"])
			settlement.stockpile[item] = float(settlement.stockpile.get(item, 0.0)) + produced
	if grain_role != GrainRole.NONE:
		_supply_grain(settlement, hours, consumption, workers if grain_role == GrainRole.GROWER else 0.0)
	settlement.food = clampf(settlement.food - consumption * hours, 0.0, float(maxi(1, settlement.population)) * 30.0)
	var prosperity_delta: float = -2.0 if settlement.food <= 0.0 else 0.08
	settlement.prosperity = clampf(settlement.prosperity + prosperity_delta * hours, 0.0, 100.0)
	settlement.demand["food"] = maxf(0.0, float(settlement.population) * 6.0 - settlement.food)

static func _supply_grain(settlement: AlifeSettlement, hours: float, consumption: float, growers: float) -> void:
	var wheat: float = float(settlement.stockpile.get("wheat", 0.0))
	var harvest_rate: float = growers * WHEAT_PER_WORKER_HOUR
	var storage_space: float = maxf(0.0, harvest_rate * WHEAT_STORAGE_HOURS - wheat)
	wheat += minf(storage_space, harvest_rate * hours)
	var missing_food: float = maxf(0.0, consumption * (PROVISION_RESERVE_HOURS + hours) - settlement.food)
	var milled: float = minf(wheat, missing_food * WHEAT_PER_PROVISION)
	settlement.food += milled / WHEAT_PER_PROVISION
	if wheat > 0.0:
		settlement.stockpile["wheat"] = wheat - milled
