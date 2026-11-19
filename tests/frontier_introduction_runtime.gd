extends Node

const FIRST_VILLAGE := Vector2i(7, 14)
const QUEST: String = "frontier_visit_valden"
const SUPPLY_QUEST: String = "valden_timber"
const SOLDIER: String = "frontier_unmarked_soldier"

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var slot: String = "__frontier_" + Crypto.new().generate_random_bytes(16).hex_encode()
	GameManager.start_new_game(12345, slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	await _check_scenario(scene, save_system, slot)
	save_system.delete_slot(slot)
	if failures == 0:
		print("FRONTIER_INTRODUCTION_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check_scenario(scene: Node, save_system: SaveSystem, slot: String) -> void:
	var player: Player = scene.get_node("World/Player")
	var world: WorldSystem = scene.get_node("World")
	var dialogue: DialogueUI = scene.get_node("UILayer/Dialogue")
	var map: GlobalMapUI = scene.get_node("UILayer/GlobalMapUI")
	var world_path: String = SaveSystem._slot_dir(slot) + "world.json"
	var start_tile: Vector2i = GameManager.get_player_tile()
	_check(GlobalLandscapeMap.cell_for_tile(start_tile) == Vector2i(9, 14), "Spawn moved out of (9,14)")
	_check(player.inventory.count_of("stone_axe") == 1 and player.inventory.count_of("stone_pickaxe") == 1
		and player.inventory.gold == 0 and player.inventory.silver == 0, "Unexpected starter inventory")
	_check(SaveSystem._read_json(world_path).get("quests", {}).get("active", {}).is_empty(),
		"A quest appeared before the soldiers")
	_check(_patrol().is_empty(), "The patrol appeared on day one")

	var site: Dictionary = world.get_terrain().get_graph().site_for_cell(FIRST_VILLAGE)
	if not _check(site.has("tile"), "Village site is missing"):
		return
	var elder_approach: Vector2i = (site["tile"] as Vector2i) + Vector2i.LEFT
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(elder_approach))
	await get_tree().process_frame
	var elder: NPCBase = _elder()
	if not _check(elder != null, "Village elder is missing"):
		return
	elder.interact(player)
	_check(_quest_state(SUPPLY_QUEST).is_empty() and not _has_choice(dialogue, "Возьмусь за поставку дерева."),
		"An early visit unlocked the village quests")
	SignalBus.dialogue_end_requested.emit()
	GameManager.set_day_and_hour(2, Config.START_HOUR)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_patrol().is_empty(), "The patrol spawned inside the village")

	SignalBus.player_teleport_requested.emit(Config.world_to_iso(start_tile))
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.set_day_and_hour(5, Config.START_HOUR - 0.1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_patrol().is_empty(), "Time in the village counted as wilderness survival")
	if not _check(save_system.save_slot(slot), "Could not save the survival stage"):
		return
	var saved: Dictionary = SaveSystem._read_json(world_path).get("frontier_introduction", {})
	_check(float(saved.get("wilderness_hours", 0.0)) > 71.5 and float(saved.get("wilderness_hours", 0.0)) < 72.0,
		"Did not record the expected wilderness hours")
	if not _check(save_system.load_slot(slot), "Could not resume wilderness survival"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.set_day_and_hour(5, Config.START_HOUR + 0.2)
	if not await _check_patrol(dialogue):
		return
	if not _check(save_system.save_slot(slot) and save_system.load_slot(slot), "The issued summons did not reload"):
		return
	await get_tree().process_frame
	_check(_quest_state(QUEST) == "active" and _patrol().is_empty(), "Loading reissued the summons")
	map.open_panel()
	map._selected_region = FIRST_VILLAGE
	map._enter_selected_chunk()
	await get_tree().process_frame
	_check(GlobalLandscapeMap.cell_for_tile(GameManager.get_player_tile()) == FIRST_VILLAGE and _quest_state(QUEST) == "active",
		"Arriving in the cell completed the summons before meeting the elder")
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(elder_approach))
	await get_tree().process_frame
	elder = _elder()
	if not _check(elder != null, "Could not find the summoned elder"):
		return
	elder.interact(player)
	_check(_quest_state(QUEST) == "completed" and _quest_state(SUPPLY_QUEST) == "available"
		and _has_choice(dialogue, "Возьмусь за поставку дерева."),
		"The elder did not complete the summons and offer village work")
	SignalBus.dialogue_end_requested.emit()
	if not _check(save_system.save_slot(slot) and save_system.load_slot(slot), "Could not reload the completed introduction"):
		return
	await get_tree().process_frame
	_check(_quest_state(QUEST) == "completed" and _quest_state(SUPPLY_QUEST) == "available" and _patrol().is_empty(),
		"Completed introduction or village access did not survive reload")


func _check_patrol(dialogue: DialogueUI) -> bool:
	for frame: int in range(600):
		if dialogue.visible:
			break
		await get_tree().physics_frame
	if not _check(dialogue.visible and dialogue.speaker_label.text == "Солдат" and _quest_state(QUEST) == "active",
			"The patrol did not walk up and deliver the summons"):
		return false
	var soldiers: Array[NPCBase] = _patrol()
	_check(soldiers.size() == 3 and _has_choice(dialogue, "Понял.") and not _has_choice(dialogue, "Торговля"),
		"The summons did not come from a military group")
	for soldier: NPCBase in soldiers:
		_check(soldier.faction_id.is_empty(), "The patrol revealed its faction")
	_press(dialogue, "Понял.")
	for frame: int in range(850):
		if _patrol().is_empty():
			break
		await get_tree().physics_frame
	return _check(_patrol().is_empty(), "The patrol did not leave after the order")


func _elder() -> NPCBase:
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if node is NPCBase and node.npc_id == "village_elder" \
				and node.get_meta("settlement_id", "") == "settlement_07_14" and not node.is_queued_for_deletion():
			return node
	return null


func _patrol() -> Array[NPCBase]:
	var result: Array[NPCBase] = []
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if node is NPCBase and node.npc_id == SOLDIER and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _quest_state(id: String) -> String:
	var result: Dictionary = {}
	SignalBus.quest_state_queried.emit(id, result)
	return str(result.get("state", ""))


func _has_choice(dialogue: DialogueUI, label: String) -> bool:
	for node: Node in dialogue.choices_box.get_children():
		if node is Button and node.text == label:
			return true
	return false


func _press(dialogue: DialogueUI, label: String) -> void:
	for node: Node in dialogue.choices_box.get_children():
		if node is Button and node.text == label:
			node.pressed.emit()
			return


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error("FRONTIER_INTRODUCTION_FAILURE: " + message)
	return condition
