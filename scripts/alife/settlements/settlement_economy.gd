class_name SettlementEconomy
extends RefCounted

const PRODUCTION: Dictionary = {
	"agricultural": {"food": 1.5, "wool": 0.1},
	"mining": {"iron_ore": 0.25, "stone": 0.5},
	"crafting": {"plank": 0.25},
	"trading": {"food": 0.5}
}
const BIOME_YIELD: Dictionary = {
	"food": {"plains": 1.0, "forest": 0.8, "mountains": 0.55, "desert": 0.35},
	"wool": {"plains": 1.0, "forest": 0.8, "mountains": 0.6, "desert": 0.45},
	"iron_ore": {"plains": 0.35, "forest": 0.55, "mountains": 1.4, "desert": 0.8},
	"stone": {"plains": 0.5, "forest": 0.7, "mountains": 1.5, "desert": 1.0},
	"plank": {"plains": 1.0, "forest": 1.25, "mountains": 0.75, "desert": 0.5}
}
const TYPE_OUTPUT: Dictionary = {"village": 1.0, "town": 1.05, "city": 1.1, "fortress": 0.95}
const TYPE_FOOD_USE: Dictionary = {"village": 1.0, "town": 1.05, "city": 1.1, "fortress": 1.15}
const PROCESSING: Array[Dictionary] = [
	{"input": "wool", "input_count": 2, "output": "cloth", "tier": 1},
	{"input": "iron_ore", "input_count": 2, "output": "iron_ingot", "tier": 3}
]

static func tick(settlement: AlifeSettlement, hours: float) -> void:
	if settlement.status == AlifeSettlement.Status.RAZED or settlement.status == AlifeSettlement.Status.RUINS:
		return
	var workers: float = float(settlement.population) * 0.4
	var output: Dictionary = PRODUCTION.get(settlement.economy_type, {})
	for item: String in output:
		var biome_yield: Dictionary = BIOME_YIELD.get(item, {})
		var produced: float = float(output[item]) * workers * hours \
			* float(biome_yield.get(settlement.biome, 1.0)) \
			* float(TYPE_OUTPUT.get(settlement.settlement_type, 1.0))
		if item == "food":
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
	settlement.food = clampf(settlement.food - float(settlement.population) * hours * 0.2 \
		* float(TYPE_FOOD_USE.get(settlement.settlement_type, 1.0)), 0.0, float(maxi(1, settlement.population)) * 30.0)
	var prosperity_delta: float = -2.0 if settlement.food <= 0.0 else 0.08
	settlement.prosperity = clampf(settlement.prosperity + prosperity_delta * hours, 0.0, 100.0)
	settlement.demand["food"] = maxf(0.0, float(settlement.population) * 6.0 - settlement.food)
