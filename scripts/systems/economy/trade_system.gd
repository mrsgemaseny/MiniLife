class_name TradeSystem
extends Node

# Resolves barter and gold transactions between Player and NPC traders via SignalBus.

func _ready() -> void:
	SignalBus.trade_transaction_requested.connect(_on_trade_transaction_requested)

func _on_trade_transaction_requested(trader: Node, item_id: String, count: int, is_buying: bool) -> void:
	if count <= 0 or item_id.is_empty():
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var player_inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if player_inv == null:
		return

	var item_def: Dictionary = DataRegistry.get_item(item_id)
	if item_def.is_empty():
		return

	var base_value: int = maxi(1, int(item_def.get("value", 5)))
	var trading_level: int = 0
	var persuasion_level: int = 0
	var skills_comp: SkillsComponent = player.get("skills") as SkillsComponent
	if skills_comp != null:
		trading_level = skills_comp.get_level("trading")
		persuasion_level = skills_comp.get_level("persuasion")

	var memory_mult: float = 1.0
	if trader != null and trader.get("memory") is MemoryComponent:
		memory_mult = (trader.get("memory") as MemoryComponent).get_price_discount_multiplier()

	var skill_mod: float = clampf(float(trading_level + persuasion_level) * 0.004, 0.0, 0.30)

	if is_buying:
		var unit_price: int = maxi(1, int(round(float(base_value) * (1.25 - skill_mod) * memory_mult)))
		var total_cost: int = unit_price * count
		if player_inv.gold < total_cost:
			SignalBus.notification_posted.emit("Not enough gold (%d required)." % total_cost)
			return
		var bought: int = player_inv.add_item(item_id, count)
		if bought <= 0:
			SignalBus.notification_posted.emit("Inventory is too full to buy items.")
			return
		player_inv.spend_gold(unit_price * bought)
		if skills_comp != null:
			skills_comp.gain_xp("trading", float(bought) * 4.0)
		if trader != null and trader.get("memory") is MemoryComponent:
			(trader.get("memory") as MemoryComponent).record_trade(unit_price * bought, GameManager.get_day())
		var npc_id_str: String = str(trader.get("npc_id")) if (trader != null and "npc_id" in trader) else "trader"
		SignalBus.trade_completed.emit(npc_id_str, -(unit_price * bought))
		SignalBus.notification_posted.emit("Bought %d x %s for %d gold." % [bought, str(item_def.get("name", item_id)), unit_price * bought])
	else:
		if not player_inv.has_item(item_id, count):
			SignalBus.notification_posted.emit("You do not have enough %s to sell." % str(item_def.get("name", item_id)))
			return
		var unit_sell: int = maxi(1, int(round(float(base_value) * (0.65 + skill_mod * 0.5))))
		var removed: int = player_inv.remove_item(item_id, count)
		var earned: int = removed * unit_sell
		player_inv.add_gold(earned)
		if skills_comp != null:
			skills_comp.gain_xp("trading", float(removed) * 3.5)
		if trader != null and trader.get("memory") is MemoryComponent:
			(trader.get("memory") as MemoryComponent).record_trade(earned, GameManager.get_day())
		var npc_id_str: String = str(trader.get("npc_id")) if (trader != null and "npc_id" in trader) else "trader"
		SignalBus.trade_completed.emit(npc_id_str, earned)
		SignalBus.notification_posted.emit("Sold %d x %s for %d gold." % [removed, str(item_def.get("name", item_id)), earned])
