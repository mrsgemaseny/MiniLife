extends Node

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var slot: String = "__valden_grain_" + Crypto.new().generate_random_bytes(16).hex_encode()
	GameManager.start_new_game(12345, slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	await _check_economy(save_system, slot)
	save_system.delete_slot(slot)
	if failures == 0:
		print("VALDEN_GRAIN_ECONOMY_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check_economy(save_system: SaveSystem, slot: String) -> void:
	var village: AlifeSettlement = _settlement(EconomyTick.VALDEN_VILLAGE_ID)
	var castle: AlifeSettlement = _settlement(EconomyTick.VALDEN_CASTLE_ID)
	if not _check(village != null and castle != null and not WorldSimulation.alife_enabled, "Valden's two settlements must exist in the normal game"):
		return
	_check(village.settlement_type == "village" and castle.settlement_type == "fortress" and village.owner_faction == castle.owner_faction,
		"Grain profiles do not match the village and castle on the map")
	var unrelated: AlifeSettlement = WorldSimulation.world.settlements.all().front() as AlifeSettlement
	if not _check(unrelated != null and unrelated != village and unrelated != castle, "No other settlement was seeded"):
		return
	var unrelated_before: Dictionary = unrelated.to_dict()
	var castle_food: float = castle.food
	var published: Array[String] = []
	SignalBus.alife_event_published.connect(func(event: Dictionary) -> void:
		if event["data"].get("settlement_id") == EconomyTick.VALDEN_CASTLE_ID:
			published.append(str(event["event_type"]))
	)
	_check(not village.stockpile.has("wheat"), "The village starts with generated wheat in its inventory")
	await _advance_to(1, Config.START_HOUR + 2.0)
	_check(int(MarketPricing.items(village).get("wheat", 0)) > 0, "Village harvest did not reach the market")
	_check(castle.food < castle_food and not castle.famine, "The castle should consume its reserves before famine")
	await _advance_to(2, Config.START_HOUR + 2.0)
	_check(castle.famine and is_zero_approx(castle.food) and not village.famine and published == ["famine_started"],
		"The castle did not report famine after consuming its reserves")
	_check(unrelated.to_dict() == unrelated_before, "The isolated economy tick changed another settlement")
	var wheat: float = float(village.stockpile.get("wheat", 0.0))
	if not _check(save_system.save_slot(slot) and save_system.load_slot(slot), "The grain economy save did not reload"):
		return
	village = _settlement(EconomyTick.VALDEN_VILLAGE_ID)
	castle = _settlement(EconomyTick.VALDEN_CASTLE_ID)
	if not _check(village != null and castle != null and is_equal_approx(wheat, float(village.stockpile.get("wheat", 0.0))) and castle.famine,
			"Reload did not preserve the harvest stockpile and famine"):
		return
	# Supply the castle directly here to isolate milling from the transport system.
	castle.stockpile["wheat"] = 240.0
	await _advance_to(2, Config.START_HOUR + 3.0)
	_check(is_equal_approx(castle.food, 40.0) and is_zero_approx(float(castle.stockpile["wheat"]))
		and not castle.famine and published == ["famine_started", "famine_ended"], "Wheat was not consumed exactly once when restoring provisions")


func _advance_to(day: int, hour: float) -> void:
	GameManager.set_day_and_hour(day, hour)
	for frame: int in range(8):
		await get_tree().process_frame


func _settlement(id: String) -> AlifeSettlement:
	return WorldSimulation.world.settlements.find(id) as AlifeSettlement


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error("VALDEN_GRAIN_ECONOMY_FAILURE: " + message)
	return ok
