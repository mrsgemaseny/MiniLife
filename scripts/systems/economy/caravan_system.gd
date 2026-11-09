class_name CaravanSystem
extends Node

# Caravan economy and two currencies with a uniform exchange rate.

const RATE_VILLAGE: int = CurrencyPolicy.SILVER_PER_GOLD
const RATE_CITY: int = CurrencyPolicy.SILVER_PER_GOLD
const ROI_TRIP_THRESHOLD: int = 5
const CARAVAN_INITIAL_INVESTMENT: int = 1500

class SettlementData extends RefCounted:
	var id: String = ""
	var name: String = ""
	var is_city: bool = false
	var treasury: int = 0
	var caravan_trips: int = 0
	var is_roi_achieved: bool = false
	var stock_tier: int = 1

var settlements: Dictionary = {}

func _ready() -> void:
	SignalBus.currency_exchange_requested.connect(_on_currency_exchange_requested)
	SignalBus.alife_market_snapshot.connect(_on_market_snapshot)

func _on_market_snapshot(markets: Dictionary) -> void:
	settlements.clear()
	for id: String in markets:
		settlements[id] = _from_market(markets[id])

func _from_market(data: Dictionary) -> SettlementData:
	var settlement: SettlementData = SettlementData.new()
	settlement.id = str(data.get("id", ""))
	settlement.name = str(data.get("name", "Roadside trader"))
	settlement.is_city = bool(data.get("is_city", false))
	settlement.treasury = int(data.get("treasury", 0))
	settlement.caravan_trips = int(data.get("caravan_trips", 0))
	settlement.is_roi_achieved = bool(data.get("is_roi_achieved", false))
	settlement.stock_tier = int(data.get("stock_tier", 1))
	return settlement

func get_settlement_for_trader(trader: Node) -> SettlementData:
	var result: Dictionary = {}
	SignalBus.alife_market_queried.emit(trader, result)
	return _from_market(result)

func get_exchange_rate(_trader: Node) -> int:
	return CurrencyPolicy.SILVER_PER_GOLD

func record_caravan_trip(_settlement_id: String, _success: bool = true) -> void:
	# Compatibility for older callers: only actual route arrivals can grant revenue.
	SignalBus.notification_posted.emit("Caravan results are recorded when an actual expedition finishes.")

func _on_day_passed(_day: int) -> void:
	pass # The A-Life global tick owns caravan time and outcomes.

func _on_currency_exchange_requested(trader: Node, to_gold: bool, amount: int) -> void:
	if amount <= 0:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if inv == null:
		return
	if CurrencyPolicy.exchange(inv, to_gold, amount):
		SignalBus.notification_posted.emit("Currency exchanged at 1 Gold = %d Silver." % CurrencyPolicy.SILVER_PER_GOLD)
	else:
		SignalBus.notification_posted.emit("Not enough currency to exchange.")
