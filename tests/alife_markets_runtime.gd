extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func settlement() -> AlifeSettlement:
	var result: AlifeSettlement = AlifeSettlement.new()
	result.settlement_id = "market"
	result.population = 20
	result.food = 3.0
	result.market_funds = 10000
	return result

func _ready() -> void:
	var market: AlifeSettlement = settlement()
	var inv: InventoryComponent = InventoryComponent.new()
	inv.gold = 100
	inv.silver = 1000
	var money: int = CurrencyPolicy.total_value(inv)
	var funds: int = market.market_funds
	var quote: Dictionary = MarketPricing.quote("bread", {"items": MarketPricing.items(market), "population": market.population, "prosperity": market.prosperity}, true)
	var purchase: Dictionary = MarketTrade.execute(market, inv, "bread", 1, true)
	check(purchase.ok and purchase.amount == quote.price and purchase.currency == "silver", "Displayed quote equals charged price in silver")
	check(market.food == 2.0 and inv.count_of("bread") == 1, "Purchase transfers stock to player")
	check(CurrencyPolicy.total_value(inv) == money - int(purchase.silver_value) and market.market_funds == funds + int(purchase.silver_value), "Purchase transfers exact money to market")
	purchase = MarketTrade.execute(market, inv, "bread", 20, true)
	check(purchase.ok and purchase.count == 2 and market.food == 0.0, "Bulk purchase stops at actual remaining stock")
	var before: int = CurrencyPolicy.total_value(inv)
	check(not MarketTrade.execute(market, inv, "bread", 1, true).ok and CurrencyPolicy.total_value(inv) == before, "Empty shop cannot create items or debit money")
	var sale: Dictionary = MarketTrade.execute(market, inv, "bread", 1, false)
	check(sale.ok and market.food == 1.0 and inv.count_of("bread") == 2, "Sale returns goods to settlement stock")
	check(CurrencyPolicy.total_value(inv) == before + int(sale.silver_value), "Sale credits only actual payout")
	market.market_funds = 0
	check(not MarketTrade.execute(market, inv, "bread", 1, false).ok and inv.count_of("bread") == 2, "Insolvent market does not consume player's goods")
	market.market_funds = 10000
	var poor: InventoryComponent = InventoryComponent.new()
	check(not MarketTrade.execute(market, poor, "bread", 1, true).ok and market.food == 1.0, "Insufficient funds leave stock unchanged")
	var full: InventoryComponent = InventoryComponent.new()
	full.max_slots = 1
	full.slots = [{"item_id": "stone", "count": 64, "durability": -1}]
	full.gold = 10
	check(not MarketTrade.execute(market, full, "bread", 1, true).ok and full.gold == 10 and market.food == 1.0, "Full inventory leaves currency and market intact")
	check(not MarketTrade.execute(market, inv, "gold_coin", 1, true).ok, "Coins cannot be bought as underpriced commodities")
	check(MarketPricing.quote("steel_sword", {"items": {}, "prosperity": 50}, true).currency == "gold", "Expensive equipment is quoted in gold")
	var scarce: Dictionary = MarketPricing.quote("bread", {"items": {"bread": 1}, "population": 100, "prosperity": 30}, true)
	var supplied: Dictionary = MarketPricing.quote("bread", {"items": {"bread": 500}, "population": 100, "prosperity": 80}, true)
	check(int(scarce.price) > int(supplied.price), "Scarcity and hardship increase local price")
	var coins: InventoryComponent = InventoryComponent.new()
	coins.add_item("gold_coin", 2)
	check(CurrencyPolicy.spend_value(coins, 15), "Physical coins can pay for silver-denominated goods")
	check(CurrencyPolicy.total_value(coins) == 25 and coins.count_of("gold_coin") == 0, "Coin conversion neither duplicates funds nor loses change")
	var trader: InventoryComponent = InventoryComponent.new()
	trader.gold = 1000
	trader.max_weight = 10000.0
	trader.add_item("iron_ingot", 20)
	market = settlement()
	before = CurrencyPolicy.total_value(trader)
	sale = MarketTrade.execute(market, trader, "iron_ingot", 20, false, 0.3, 0.85)
	purchase = MarketTrade.execute(market, trader, "iron_ingot", 20, true, 0.3, 0.85)
	check(sale.count == 20 and purchase.count == 20, "Bulk sell and buyback transfer actual quantities")
	check(CurrencyPolicy.total_value(trader) <= before, "Marginal pricing prevents sell-then-buyback profit at maximum discount")
	var restored: AlifeSettlement = AlifeSettlement.from_dict(JSON.parse_string(JSON.stringify(market.to_dict())))
	check(restored.market_funds == market.market_funds and int(restored.stockpile.get("iron_ingot", 0)) == 0, "Market funds and depleted stock survive save")
	var memory: MemoryComponent = MemoryComponent.new()
	for transaction: int in range(4):
		memory.record_trade_silver(15, 1)
	check(memory.trade_volume_silver == 60 and memory.trade_volume_gold == 3, "Small silver trades accumulate without truncation loss")
	memory.record_trade_silver(1940, 1)
	memory.record_trade_silver(200, 1)
	check(memory.memories.size() == 1 and memory.personal_opinion_of_player == 2, "Frequent customer reward fires once at threshold")
	var legacy: MemoryComponent = MemoryComponent.new()
	legacy.from_dict({"trade_volume_gold": 5})
	check(legacy.trade_volume_silver == 100, "Legacy trading memory migrates to silver accounting")
	var workshop: AlifeSettlement = settlement()
	workshop.economy_type = "crafting"
	workshop.food = 100.0
	workshop.stockpile = {"iron_ore": 10.0, "wool": 10.0}
	workshop.stock_tier = 2
	SettlementEconomy.tick(workshop, 1.0)
	check(float(workshop.stockpile.get("iron_ingot", 0.0)) == 0.0 and float(workshop.stockpile["iron_ore"]) == 10.0, "Advanced production stays locked before trade investment pays off")
	workshop.stock_tier = 3
	SettlementEconomy.tick(workshop, 5.0)
	check(is_equal_approx(float(workshop.stockpile.get("iron_ingot", 0.0)), 2.0) and is_equal_approx(float(workshop.stockpile["iron_ore"]), 6.0), "Unlocked workshop consumes imported ore to produce ingots")
	var world: AlifeWorldContext = AlifeWorldContext.new()
	market = settlement()
	market.economy_type = "mining"
	market.food = 0.0
	world.settlements.register(market)
	EconomyTick.new().tick(world, 1.0)
	check(market.famine and str(world.events[0]["event_type"]) == "famine_started", "Actual shortage starts a public famine event")
	market.food = 100.0
	EconomyTick.new().tick(world, 1.0)
	check(not market.famine and str(world.events[-1]["event_type"]) == "famine_ended", "Resupply ends famine")
	var audit: ComprehensiveAudit = ComprehensiveAudit.new()
	add_child(audit)
	var report: Dictionary = {"errors": [], "checks_passed": 0}
	audit._audit_economy_and_currency(report)
	check((report["errors"] as Array).is_empty() and int(report["checks_passed"]) == 1, "Existing economy audit validates the new currency and finite market rules")
	audit.queue_free()
	print("ALIFE MARKET TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
