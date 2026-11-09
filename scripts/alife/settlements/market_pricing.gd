class_name MarketPricing
extends RefCounted

static func items(settlement: AlifeSettlement) -> Dictionary:
	var result: Dictionary = {}
	if settlement.food >= 1.0:
		result["bread"] = int(settlement.food)
	for item: String in settlement.stockpile:
		var count: int = int(settlement.stockpile[item])
		if count > 0 and DataRegistry.has_entry("items", item):
			result[item] = count
	return result

static func quote(item_id: String, market: Dictionary, is_buying: bool, skill_mod: float = 0.0, memory_mult: float = 1.0) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if definition.is_empty() or str(definition.get("type", "")) == "currency":
		return {}
	var base: float = maxf(1.0, float(definition.get("value", 5)))
	var stock: Dictionary = market.get("items", {})
	var available: int = int(stock.get(item_id, 0))
	var target: float = maxf(10.0, float(market.get("population", 100)) * 0.2)
	var scarcity: float = clampf(1.5 - float(available) / target * 0.25, 0.75, 1.5)
	var prosperity: float = clampf(1.2 - float(market.get("prosperity", 50.0)) * 0.004, 0.8, 1.2)
	var factor: float = (1.25 - clampf(skill_mod, 0.0, 0.3)) * maxf(0.85, memory_mult) if is_buying else (0.65 + clampf(skill_mod, 0.0, 0.3) * 0.5)
	var silver: float = base * scarcity * prosperity * factor
	var currency: String = "gold" if base >= 100.0 else "silver"
	var divisor: float = float(CurrencyPolicy.SILVER_PER_GOLD) if currency == "gold" else 1.0
	var price: int = maxi(1, int(ceil(silver / divisor)) if is_buying else int(floor(silver / divisor)))
	return {"price": price, "currency": currency, "silver_value": price * int(divisor), "available": available}
