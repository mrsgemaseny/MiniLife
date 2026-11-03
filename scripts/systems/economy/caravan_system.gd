class_name CaravanSystem
extends Node

# Simulates Battle Brothers-style caravan economy, Rule of 5 Trips ROI, and two-currency regional arbitrage.

const RATE_VILLAGE: int = 15
const RATE_CITY: int = 25
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
	_init_settlements()
	SignalBus.currency_exchange_requested.connect(_on_currency_exchange_requested)
	SignalBus.day_passed.connect(_on_day_passed)

func _init_settlements() -> void:
	var village: SettlementData = SettlementData.new()
	village.id = "village_oakhaven"
	village.name = "Oakhaven Hamlet"
	village.is_city = false
	village.treasury = 800
	village.caravan_trips = 0
	village.stock_tier = 1
	settlements[village.id] = village

	var city: SettlementData = SettlementData.new()
	city.id = "city_ironford"
	city.name = "Ironford Trade Metropolis"
	city.is_city = true
	city.treasury = 5000
	city.caravan_trips = 0
	city.stock_tier = 2
	settlements[city.id] = city

func get_settlement_for_trader(trader: Node) -> SettlementData:
	if trader != null:
		if (trader.has_meta("is_in_city") and bool(trader.get_meta("is_in_city"))) or bool(trader.get("is_in_city")):
			return settlements["city_ironford"] as SettlementData
		var nid: String = ""
		if "npc_id" in trader:
			nid = str(trader.get("npc_id"))
		elif trader.has_meta("npc_id"):
			nid = str(trader.get_meta("npc_id"))
		if nid.find("city") != -1 or nid.find("guild") != -1 or nid.find("noble") != -1:
			return settlements["city_ironford"] as SettlementData
	return settlements["village_oakhaven"] as SettlementData

func get_exchange_rate(trader: Node) -> int:
	var s: SettlementData = get_settlement_for_trader(trader)
	return RATE_CITY if s.is_city else RATE_VILLAGE

func record_caravan_trip(settlement_id: String, success: bool = true) -> void:
	if not settlements.has(settlement_id):
		return
	var s: SettlementData = settlements[settlement_id] as SettlementData
	if not success:
		s.caravan_trips = 0
		s.treasury = maxi(0, s.treasury - CARAVAN_INITIAL_INVESTMENT)
		SignalBus.notification_posted.emit("Caravan of %s was raided by bandits! Treasury suffered deficit." % s.name)
		return

	s.caravan_trips += 1
	var achieved: bool = (s.caravan_trips >= ROI_TRIP_THRESHOLD)
	if achieved and not s.is_roi_achieved:
		s.is_roi_achieved = true
		s.stock_tier = 3
		s.treasury += 3000
		SignalBus.notification_posted.emit("Caravan of %s completed 5 trips! Full ROI achieved: city enriched with T3-T4 goods!" % s.name)
	else:
		s.treasury += 400
		SignalBus.notification_posted.emit("Caravan of %s arrived safely (Trip %d/%d)." % [s.name, s.caravan_trips, ROI_TRIP_THRESHOLD])

	SignalBus.caravan_trip_completed.emit(settlement_id, s.caravan_trips, s.is_roi_achieved)

func _on_day_passed(_day: int) -> void:
	# Passive A-life simulation: caravans progress between settlements
	if randf() < 0.45:
		record_caravan_trip("city_ironford", randf() > 0.15)
	if randf() < 0.35:
		record_caravan_trip("village_oakhaven", randf() > 0.20)

func _on_currency_exchange_requested(trader: Node, to_gold: bool, amount: int) -> void:
	if amount <= 0:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if inv == null:
		return

	var rate: int = get_exchange_rate(trader)
	var s: SettlementData = get_settlement_for_trader(trader)

	if to_gold:
		# Player exchanges Silver for Gold (needs `rate * amount` Silver)
		var cost_silver: int = rate * amount
		# Check either inv.silver or inv.count_of("silver_coin")
		var total_silver: int = inv.silver + inv.count_of("silver_coin")
		if total_silver < cost_silver:
			SignalBus.notification_posted.emit("Not enough Silver! Need %d Silver for %d Gold at %s (Rate: 1:%d)." % [cost_silver, amount, s.name, rate])
			return

		# Deduct silver
		var rem_cost: int = cost_silver
		if inv.silver >= rem_cost:
			inv.spend_silver(rem_cost)
			rem_cost = 0
		else:
			rem_cost -= inv.silver
			inv.spend_silver(inv.silver)
			inv.remove_item("silver_coin", rem_cost)

		# Add gold
		inv.add_gold(amount)
		inv.add_item("gold_coin", amount)
		SignalBus.notification_posted.emit("Exchanged %d Silver for %d Gold in %s (Rate 1:%d)." % [cost_silver, amount, s.name, rate])
	else:
		# Player exchanges Gold for Silver (gives `amount` Gold, receives `rate * amount` Silver)
		var total_gold: int = inv.gold + inv.count_of("gold_coin")
		if total_gold < amount:
			SignalBus.notification_posted.emit("Not enough Gold! You need %d Gold to exchange." % amount)
			return

		# Deduct gold
		var rem_gold: int = amount
		if inv.gold >= rem_gold:
			inv.spend_gold(rem_gold)
			rem_gold = 0
		else:
			rem_gold -= inv.gold
			inv.spend_gold(inv.gold)
			inv.remove_item("gold_coin", rem_gold)

		var gain_silver: int = rate * amount
		inv.add_silver(gain_silver)
		inv.add_item("silver_coin", gain_silver)
		SignalBus.notification_posted.emit("Exchanged %d Gold for %d Silver in %s (Rate 1:%d)." % [amount, gain_silver, s.name, rate])
