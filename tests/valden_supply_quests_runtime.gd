extends Node

const SETTLEMENT_ID: String = "settlement_07_14"
const CELL := Vector2i(7, 14)
const TIMBER: String = "valden_timber"
const STONE: String = "valden_stone"
const BERRIES: String = "valden_berries"

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var slot: String = "__valden_supplies_" + Crypto.new().generate_random_bytes(16).hex_encode()
	GameManager.start_new_game(12345, slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	await _check_deliveries(scene, save_system, slot)
	save_system.delete_slot(slot)
	if failures == 0:
		print("VALDEN_SUPPLY_QUESTS_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check_deliveries(scene: Node, save_system: SaveSystem, slot: String) -> void:
	var player: Player = scene.get_node("World/Player")
	var world: WorldSystem = scene.get_node("World")
	var dialogue: DialogueUI = scene.get_node("UILayer/Dialogue")
	var site: Dictionary = world.get_terrain().get_graph().site_for_cell(CELL)
	if not _check(site.has("tile"), "Valden's village site is missing"):
		return
	var approach: Vector2i = (site["tile"] as Vector2i) + Vector2i.LEFT
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(approach))
	await get_tree().process_frame
	var elder: NPCBase = _find_elder()
	if not _check(elder != null, "The streamed elder is missing"):
		return
	var stock_before: Dictionary = _stock(elder)
	var silver_before: int = player.inventory.silver
	var trade_speakers: Array[Node] = []
	var observe_trade := func(actor: Node) -> void: trade_speakers.append(actor)
	SignalBus.trade_session_requested.connect(observe_trade)
	elder.interact(player)
	_check(_press(dialogue, "Торговля") and trade_speakers == [elder], "Trade is not routed to the current speaker")
	SignalBus.trade_session_requested.disconnect(observe_trade)
	SignalBus.ui_close_all_requested.emit()
	elder.interact(player)
	_check(dialogue.speaker_label.text == "Староста деревни Вальдена", "Incorrect dialogue opened in Valden")

	SignalBus.quest_start_requested.emit(TIMBER, "village_elder")
	_check(_quest_state(TIMBER) == "available", "A generic quest request bypassed the local elder")
	_check(_press(dialogue, "Возьмусь за поставку дерева.") and _quest_state(TIMBER) == "active", "Timber offer could not be accepted")
	player.inventory.add_item("wood", 5)
	_check(_press(dialogue, "Сдать 6 единиц дерева.") and _quest_state(TIMBER) == "active"
		and player.inventory.count_of("wood") == 5 and _stock(elder) == stock_before
		and player.inventory.silver == silver_before, "Incomplete delivery changed inventory, stock or reward")
	SignalBus.quest_turn_in_requested.emit(TIMBER)
	_check(_quest_state(TIMBER) == "active", "Generic turn-in completed a delivery")
	_check(_press(dialogue, "Возьмусь за поставку камня.") and _quest_state(STONE) == "active", "Stone offer missing")
	_check(_press(dialogue, "Возьмусь за поставку ягод.") and _quest_state(BERRIES) == "active", "Berry offer missing")
	SignalBus.dialogue_end_requested.emit()

	player.inventory.add_item("wood", 3)
	player.inventory.add_item("stone", 5)
	player.inventory.add_item("berries", 4)
	elder.interact(player)
	_check(_press(dialogue, "Сдать 6 единиц дерева.") and _quest_state(TIMBER) == "completed", "Timber delivery did not complete")
	_check(player.inventory.count_of("wood") == 2, "Timber delivery did not take exactly six units")
	_check(not _press(dialogue, "Сдать 6 единиц дерева."), "Completed delivery remained available")
	_check(_press(dialogue, "Сдать 5 единиц камня.") and _quest_state(STONE) == "completed", "Stone delivery did not complete")
	_check(player.inventory.count_of("stone") == 0, "Stone delivery did not take its goods")
	SignalBus.dialogue_end_requested.emit()
	_check(player.inventory.silver == silver_before + 33, "Wrong reward total")
	var stock: Dictionary = _stock(elder)
	_check(float(stock.get("wood", 0)) == float(stock_before.get("wood", 0)) + 6
		and float(stock.get("stone", 0)) == float(stock_before.get("stone", 0)) + 5, "Delivered goods are missing from the village market")
	if not _check(save_system.save_slot(slot), "The village save failed"):
		return
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(WorldLayout.start_tile()))
	await get_tree().process_frame
	_check(not is_instance_valid(elder), "The village did not unload")
	if not _check(save_system.load_slot(slot), "The village save failed to load"):
		return
	await get_tree().process_frame
	elder = _find_elder()
	if not _check(elder != null, "The elder did not reload"):
		return
	_check(_stock(elder) == stock and player.inventory.silver == silver_before + 33, "Market or rewards did not survive reload")
	var replay: Dictionary = {}
	SignalBus.settlement_delivery_quest_requested.emit(TIMBER, elder, true, replay)
	_check(not replay.get("ok", false) and _quest_state(TIMBER) == "completed" and _stock(elder) == stock,
		"Reload allowed a repeat payment or stock change")
	elder.interact(player)
	_check(_press(dialogue, "Сдать 4 порции ягод.") and _quest_state(BERRIES) == "completed",
		"An active delivery could not be resumed after reload")
	_check(float(_stock(elder).get("berries", 0)) == float(stock_before.get("berries", 0)) + 4
		and player.inventory.count_of("berries") == 0 and player.inventory.silver == silver_before + 45,
		"Berry delivery failed to transfer its goods or reward")
	SignalBus.dialogue_end_requested.emit()
	var purchase: Dictionary = {}
	SignalBus.alife_trade_requested.emit(elder, player.inventory, "wood", 1, true, 0.0, 1.0, purchase)
	_check(purchase.get("ok", false) and player.inventory.count_of("wood") == 3
		and int(_stock(elder).get("wood", 0)) == int(stock.get("wood", 0)) - 1,
		"The market did not sell back a delivered item")


func _find_elder() -> NPCBase:
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if node is NPCBase and node.npc_id == "village_elder" and node.get_meta("settlement_id", "") == SETTLEMENT_ID \
				and not node.is_queued_for_deletion():
			return node
	return null


func _press(dialogue: DialogueUI, label: String) -> bool:
	for child: Node in dialogue.choices_box.get_children():
		if child is Button and child.text == label:
			child.pressed.emit()
			return true
	return false


func _quest_state(id: String) -> String:
	var result: Dictionary = {}
	SignalBus.quest_state_queried.emit(id, result)
	return str(result.get("state", ""))


func _stock(elder: NPCBase) -> Dictionary:
	var market: Dictionary = {}
	SignalBus.alife_market_queried.emit(elder, market)
	return market.get("items", {})


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error("VALDEN_SUPPLY_FAILURE: " + message)
	return ok
