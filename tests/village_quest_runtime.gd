extends Node

var inventory: InventoryComponent = InventoryComponent.new()
var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	add_to_group("player")
	call_deferred("run")

func run() -> void:
	var reputation: ReputationSystem = ReputationSystem.new()
	add_child(reputation)
	var quests: QuestSystem = QuestSystem.new()
	add_child(quests)
	SignalBus.game_started.emit(4321, "village_quest_verification", true)
	var village: AlifeSettlement = null
	for candidate: AlifeSettlement in WorldSimulation.world.settlements.all():
		if candidate.settlement_type == "village" and candidate.status == AlifeSettlement.Status.NORMAL:
			village = candidate
			break
	check(village != null, "A real village exists")
	check(DataRegistry.get_rows("quests_village").size() == 30, "All village templates load")
	if village == null:
		get_tree().quit(1)
		return
	var id: String = village.settlement_id
	var before: float = float(village.stockpile.get("wood", 0.0))
	check(quests.start_village_quest("q_village_wood_01", id), "Village quest binds to a real settlement")
	var quest_id: String = "q_village_wood_01@" + id
	check(str(quests._active_quests[quest_id].get("settlement_id", "")) == id, "Quest state stores settlement id")
	quests.complete_quest(quest_id)
	check(quests._active_quests.has(quest_id) and float(village.stockpile.get("wood", 0.0)) == before, "Delivery cannot complete without goods")
	check(inventory.add_item("wood", 6) == 6, "Player can carry quest goods")
	quests.complete_quest(quest_id)
	check(quests._completed_quests.has(quest_id) and not quests._active_quests.has(quest_id), "Delivery completes once")
	check(inventory.count_of("wood") == 0 and float(village.stockpile.get("wood", 0.0)) == before + 6.0, "Goods move from player to village")
	check(inventory.silver == 12 and reputation.get_local(id) == 5, "Player receives silver and local reputation")
	quests.complete_quest(quest_id)
	check(float(village.stockpile.get("wood", 0.0)) == before + 6.0, "Repeated turn in cannot duplicate village stock")
	var prosperity_before: float = village.prosperity
	check(quests.start_village_quest("q_village_water_05", id), "Second template loads for same village")
	quests.fail_quest("q_village_water_05@" + id, "verification")
	check(village.prosperity == maxf(0.0, prosperity_before - 2.0), "Failed quest changes village prosperity")
	var bundle: Dictionary = {"world": {}}
	SignalBus.save_data_requested.emit(bundle)
	check(bundle.get("world", {}).has("alife") and bundle.get("world", {}).has("quests"), "Village and quest state enter same save bundle")
	SignalBus.save_data_loaded.emit(bundle)
	SignalBus.game_started.emit(4321, "village_quest_verification", false)
	var restored: AlifeSettlement = WorldSimulation.world.settlements.find(id) as AlifeSettlement
	check(restored != null and float(restored.stockpile.get("wood", 0.0)) == before + 6.0, "Village ripple survives reload")
	check(quests._completed_quests.has(quest_id), "Quest completion survives reload")
	SignalBus.local_rep_change_requested.emit(id, 95, "verification")
	for row: Dictionary in DataRegistry.get_rows("quests_village"):
		var template_id: String = str(row.get("id", ""))
		if template_id in ["q_village_wood_01", "q_village_water_05"]:
			continue
		check(quests.start_village_quest(template_id, id), "Village template can bind: " + template_id)
	var food_before: float = restored.food
	var hunt_id: String = "q_village_boar_29@" + id
	SignalBus.npc_killed.emit("forest_boar", "wildlife", "player")
	quests.complete_quest(hunt_id)
	check(quests._completed_quests.has(hunt_id) and restored.food == food_before + 8.0, "Real kill signal completes hunt and changes village food")
	print("VILLAGE QUEST RUNTIME: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
