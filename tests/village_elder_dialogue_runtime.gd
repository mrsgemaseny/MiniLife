extends Node

var failures: int = 0
var shown_choices: Array = []
var shown_speaker: String = ""

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	SignalBus.dialogue_node_shown.connect(_on_dialogue_node_shown)
	call_deferred("run")

func _on_dialogue_node_shown(speaker: String, _body: String, choices: Array) -> void:
	shown_speaker = speaker
	shown_choices = choices.duplicate(true)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var saves: Node = main.get_node("Systems/SaveSystem")
	saves.free()
	SaveSystem.instance = null
	GameManager.start_new_game(4321, "elder_dialogue_verification")
	main.get_node("UILayer/MainMenu").call("close_menu")
	var village: AlifeSettlement = null
	var elder_tile: Vector2i = Vector2i.ZERO
	var nearest: int = 2147483647
	for candidate: AlifeSettlement in WorldSimulation.world.settlements.all():
		if candidate.settlement_type == "village" and candidate.status == AlifeSettlement.Status.NORMAL:
			var elder_squad: SettlementSquad = null
			for squad: SettlementSquad in WorldSimulation.squads_of(candidate.settlement_id):
				if squad.npc_id == "village_elder":
					elder_squad = squad
					break
			if elder_squad == null:
				continue
			var distance: int = Config.tile_distance(candidate.tile, WorldLayout.start_tile())
			if distance < nearest:
				nearest = distance
				village = candidate
				elder_tile = elder_squad.anchor_tile
	check(village != null, "A village exists for the elder flow")
	if village == null:
		get_tree().quit(1)
		return
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(elder_tile))
	for frame: int in range(100):
		await get_tree().process_frame
	var elder: NPCBase = null
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if npc is NPCBase and str(npc.get("npc_id")) == "village_elder" and str(npc.get_meta("settlement_id", "")) == village.settlement_id:
			elder = npc as NPCBase
			break
	check(elder != null, "Village elder appears on the local map")
	if elder == null:
		get_tree().quit(1)
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	check(player != null, "Player is present")
	if player == null:
		get_tree().quit(1)
		return
	var elder_position: Vector2i = Config.iso_to_world(elder.global_position)
	var approach: Vector2i = elder_position
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if main.get_node("World").is_passable(elder_position + offset):
			approach = elder_position + offset
			break
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(approach))
	for frame: int in range(3):
		await get_tree().process_frame
	check(Config.tile_distance(GameManager.get_player_tile(), elder_position) <= 2, "Player stands next to the elder")
	elder.interact(player)
	check(shown_speaker == "Староста" and shown_choices.size() >= 3, "Elder shows localized quest choices")
	for choice: Dictionary in shown_choices:
		check(not str(choice.get("text", "")).contains("{"), "Elder choice has no unresolved template placeholder")
	for frame: int in range(3):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		var preview_path: String = ProjectSettings.globalize_path("user://village_elder_dialogue_preview.png")
		var preview: Image = get_viewport().get_texture().get_image()
		if preview != null and preview.save_png(preview_path) == OK:
			print("VILLAGE ELDER PREVIEW: ", preview_path)
	var offer_index: int = -1
	for i: int in range(shown_choices.size()):
		var action: Dictionary = shown_choices[i].get("action", {}) if shown_choices[i].get("action", {}) is Dictionary else {}
		if str(action.get("template_id", "")) == "q_village_wood_01":
			offer_index = i
			break
	check(offer_index >= 0, "Elder offers the starter wood quest")
	if offer_index < 0:
		get_tree().quit(1)
		return
	SignalBus.dialogue_choice_selected.emit(offer_index)
	var quests: QuestSystem = main.get_node("Systems/QuestSystem") as QuestSystem
	var instance_id: String = "q_village_wood_01@" + village.settlement_id
	check(quests._active_quests.has(instance_id), "Choosing offer starts quest for this village")
	var inventory: InventoryComponent = player.get("inventory") as InventoryComponent
	check(inventory.add_item("wood", 6) == 6, "Player receives test delivery goods")
	var before: float = float(village.stockpile.get("wood", 0.0))
	elder.interact(player)
	var turn_in_index: int = -1
	for i: int in range(shown_choices.size()):
		var action: Dictionary = shown_choices[i].get("action", {}) if shown_choices[i].get("action", {}) is Dictionary else {}
		if str(action.get("quest_id", "")) == instance_id:
			turn_in_index = i
			break
	check(turn_in_index >= 0, "Elder offers turn in when goods are held")
	if turn_in_index >= 0:
		SignalBus.dialogue_choice_selected.emit(turn_in_index)
	check(quests._completed_quests.has(instance_id) and float(village.stockpile.get("wood", 0.0)) == before + 6.0, "Dialogue turn in changes actual village")
	check(inventory.count_of("wood") == 0, "Turn in removes goods")
	elder.interact(player)
	var fence_offer: int = _choice_index("template_id", "q_village_fence_03")
	check(fence_offer >= 0, "Elder offers fence repair")
	if fence_offer >= 0:
		SignalBus.dialogue_choice_selected.emit(fence_offer)
	var fence_id: String = "q_village_fence_03@" + village.settlement_id
	SignalBus.structure_built.emit("wood_wall", village.tile + Vector2i(100, 0))
	check(int(quests._active_quests[fence_id]["progress"]["current"]) == 0, "Distant wall does not repair village fence")
	SignalBus.structure_built.emit("wood_wall", village.tile + Vector2i(10, 0))
	check(int(quests._active_quests[fence_id]["progress"]["current"]) == 1, "Wall built near village completes repair objective")
	var food_before: float = village.food
	elder.interact(player)
	var fence_turn_in: int = _choice_index("quest_id", fence_id)
	check(fence_turn_in >= 0, "Elder accepts repaired fence")
	if fence_turn_in >= 0:
		SignalBus.dialogue_choice_selected.emit(fence_turn_in)
	check(quests._completed_quests.has(fence_id) and village.food == food_before + 8.0, "Fence repair raises actual village food")
	elder.interact(player)
	var water_offer: int = _choice_index("template_id", "q_village_water_05")
	check(water_offer >= 0, "Elder offers well dispute")
	if water_offer >= 0:
		SignalBus.dialogue_choice_selected.emit(water_offer)
	var water_id: String = "q_village_water_05@" + village.settlement_id
	var peasant_squads: Array[SettlementSquad] = []
	for squad: SettlementSquad in WorldSimulation.squads_of(village.settlement_id):
		if squad.template_id == "peasants":
			peasant_squads.append(squad)
	check(not peasant_squads.is_empty(), "Village has a peasant group")
	var peasants: Array[NPCBase] = []
	for peasant_squad: SettlementSquad in peasant_squads:
		SignalBus.player_teleport_requested.emit(Config.world_to_iso(peasant_squad.anchor_tile))
		for frame: int in range(100):
			await get_tree().process_frame
		peasants.clear()
		for npc: Node in get_tree().get_nodes_in_group("npc"):
			if npc is NPCBase and str(npc.get_meta("squad_id", "")).contains(village.settlement_id + "/peasants/"):
				peasants.append(npc as NPCBase)
		if peasants.size() >= 2:
			break
	check(peasants.size() >= 2, "Two distinct peasants appear near the village")
	if peasants.size() < 2:
		get_tree().quit(1)
		return
	peasants[0].interact(player)
	check(shown_speaker == "Житель", "Peasant speaks a local Russian greeting")
	SignalBus.dialogue_choice_selected.emit(0)
	peasants[0].interact(player)
	SignalBus.dialogue_choice_selected.emit(0)
	check(int(quests._active_quests[water_id]["progress"]["current"]) == 1, "Repeated conversation with one resident counts once")
	peasants[1].interact(player)
	SignalBus.dialogue_choice_selected.emit(0)
	var prosperity_before: float = village.prosperity
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(elder_tile))
	for frame: int in range(100):
		await get_tree().process_frame
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if npc is NPCBase and str(npc.get("npc_id")) == "village_elder" and str(npc.get_meta("settlement_id", "")) == village.settlement_id:
			elder = npc as NPCBase
			break
	check(is_instance_valid(elder), "Elder reappears after leaving and returning")
	if not is_instance_valid(elder):
		get_tree().quit(1)
		return
	elder.interact(player)
	var water_turn_in: int = _choice_index("quest_id", water_id)
	check(water_turn_in >= 0, "Elder accepts two resident reports")
	if water_turn_in >= 0:
		SignalBus.dialogue_choice_selected.emit(water_turn_in)
	check(quests._completed_quests.has(water_id) and village.prosperity == minf(100.0, prosperity_before + 2.0), "Negotiation changes village prosperity")
	print("VILLAGE ELDER DIALOGUE: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _choice_index(key: String, value: String) -> int:
	for i: int in range(shown_choices.size()):
		var action: Variant = shown_choices[i].get("action", {})
		if action is Dictionary and str((action as Dictionary).get(key, "")) == value:
			return i
	return -1
