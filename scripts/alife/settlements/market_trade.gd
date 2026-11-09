class_name MarketTrade
extends RefCounted

static func execute(settlement: AlifeSettlement, inventory: InventoryComponent, item_id: String, count: int, is_buying: bool, skill_mod: float = 0.0, memory_mult: float = 1.0) -> Dictionary:
	var result: Dictionary = {"handled": true, "ok": false, "count": 0, "amount": 0, "silver_value": 0, "currency": "silver"}
	if inventory == null or count <= 0 or count > 1000 or settlement.status != AlifeSettlement.Status.NORMAL:
		result["error"] = "This market is unavailable."
		return result
	for unit: int in range(count):
		var market: Dictionary = {"items": MarketPricing.items(settlement), "population": settlement.population, "prosperity": settlement.prosperity}
		var quote: Dictionary = MarketPricing.quote(item_id, market, is_buying, skill_mod, memory_mult)
		if quote.is_empty():
			result["error"] = "This item cannot be traded here."
			break
		var price: int = int(quote["price"])
		var value: int = int(quote["silver_value"])
		if is_buying:
			if int(quote["available"]) <= 0:
				result["error"] = "The trader has no stock left."
				break
			if CurrencyPolicy.total_value(inventory) < value:
				result["error"] = "Not enough currency."
				break
			if inventory.add_item(item_id, 1) != 1:
				result["error"] = "Inventory is full."
				break
			CurrencyPolicy.spend_value(inventory, value)
			settlement.market_funds += value
			_adjust_stock(settlement, item_id, -1)
		else:
			if inventory.count_of(item_id) <= 0 or settlement.market_funds < value:
				result["error"] = "The item or the trader's funds are unavailable."
				break
			if inventory.remove_item(item_id, 1) != 1:
				break
			if str(quote["currency"]) == "gold":
				inventory.add_gold(price)
			else:
				inventory.add_silver(price)
			settlement.market_funds -= value
			_adjust_stock(settlement, item_id, 1)
		result["count"] = int(result["count"]) + 1
		result["amount"] = int(result["amount"]) + price
		result["silver_value"] = int(result["silver_value"]) + value
		result["currency"] = str(quote["currency"])
	result["ok"] = int(result["count"]) > 0
	return result

static func _adjust_stock(settlement: AlifeSettlement, item: String, delta: int) -> void:
	if item == "bread":
		settlement.food = maxf(0.0, settlement.food + float(delta))
	else:
		settlement.stockpile[item] = maxf(0.0, float(settlement.stockpile.get(item, 0.0)) + float(delta))
