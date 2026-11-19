extends Node

const SOUTH: String = "army.south"
const SEED_VALUE: int = 12345
const FAR: Vector2i = Vector2i(9000, 14000)
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--distant" in OS.get_cmdline_user_args():
		_check_distant_march()
	else:
		var scene: Node = load("res://scenes/main.tscn").instantiate()
		add_child(scene)
		var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
		var slot: String = "__imperial_army_" + Crypto.new().generate_random_bytes(16).hex_encode()
		GameManager.start_new_game(SEED_VALUE, slot)
		scene.get_node("UILayer/MainMenu").close_menu()
		await _check_materialized_march(save_system, slot)
		save_system.delete_slot(slot)
	if failures == 0:
		print("IMPERIAL_ARMIES_DISTANT_OK" if "--distant" in OS.get_cmdline_user_args() else "IMPERIAL_ARMIES_RUNTIME_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check_distant_march() -> void:
	var context: AlifeWorldContext = AlifeWorldContext.new()
	context.seed_world(SEED_VALUE, 0.0)
	var system: ImperialArmySystem = ImperialArmySystem.new()
	system.initialize(context, 0.0)
	var authored: Dictionary[String, Dictionary] = WorldData.imperial_armies()
	_check(system.active_army_ids().size() == 4 and not system.active_army_ids().has("army.girdenburg"), "Incorrect roster from WorldStudio")
	for id: String in system.active_army_ids():
		var units: Array[GlobalAgent] = ImperialArmySystem.living_units(context, id)
		_check(units.size() == ImperialArmySystem.COLUMN_SIZE, "Incomplete column " + id)
		for unit: GlobalAgent in units:
			_check(GlobalLandscapeMap.cell_for_tile(unit.tile) == authored[id]["position"], "Army started outside its authored position")
	var south: Array[GlobalAgent] = ImperialArmySystem.living_units(context, SOUTH)
	if not _check(not south.is_empty(), "The southern column is missing"):
		return
	var commander: GlobalAgent = south[0]
	var authored_route: Array = authored[SOUTH]["route"]
	var first_waypoint: Vector2i = authored_route.back()
	var first_goal: Vector2i = commander.destination_tile
	_check(GlobalLandscapeMap.cell_for_tile(first_goal) == first_waypoint, "The column did not target the previous WorldStudio waypoint")
	var start: Vector2i = commander.tile
	var hours: float = 0.0
	system.update(context, FAR, 0.25)
	_check(commander.tile == start, "Distant march updated before its LOD interval")
	while commander.destination_tile == first_goal and hours < 24.0:
		hours += 0.5
		system.update(context, FAR, hours)
		var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(commander.tile)
		_check(cell in [first_waypoint, authored[SOUTH]["position"]], "March left the authored corridor")
	_check(commander.tile == first_goal and GlobalLandscapeMap.cell_for_tile(commander.destination_tile) == authored_route[-2],
		"The column did not complete the first leg and proceed to the next waypoint")
	_check(context.agents.materialized.is_empty(), "An offscreen army created scene entities")
	_check_bypass(context, system, commander)
	system.shutdown()
	context.travel.shutdown()


func _check_bypass(context: AlifeWorldContext, system: ImperialArmySystem, commander: GlobalAgent) -> void:
	context.travel.imperial_zones = system.avoidance_zones(context)
	var formation: Array[GlobalAgent] = ImperialArmySystem.living_units(context, SOUTH)
	var start: Vector2i = commander.tile - Vector2i(14, 0)
	var goal: Vector2i = formation.back().tile + Vector2i(16, 0)
	var regular: GlobalAgent = GlobalAgent.new()
	regular.agent_id = "test_regular_soldier"
	regular.role = "soldier"
	regular.tile = start
	regular.destination_tile = goal
	var direct: Array[Vector2i] = context.travel.path(SEED_VALUE, start, goal, true)
	if not _check(not direct.is_empty() and direct.any(context.travel.near_imperials), "Regular march fixture does not intersect the column"):
		return
	context.travel.assign_path(SEED_VALUE, regular, direct)
	var bypass: Array[Vector2i] = context.travel.regular_bypass(SEED_VALUE, start, goal, goal)
	_check(bypass.size() > 1 and not bypass.any(context.travel.near_imperials), "The detour crossed the imperial column or stalled")
	for iteration: int in range(100):
		var arrived: bool = context.travel.advance(SEED_VALUE, regular, 1.0 / AlifeTravel.WALK_TILES_PER_HOUR,
			AlifeTravel.WALK_TILES_PER_HOUR, true, [], true)
		if not _check(not context.travel.near_imperials(regular.tile), "The regular soldier entered the column"):
			return
		if arrived:
			return
	_check(false, "The regular soldier did not resume the original march after bypassing the column")


func _check_materialized_march(save_system: SaveSystem, slot: String) -> void:
	var commander_id: String = ImperialArmySystem.unit_id(SOUTH, 0)
	var commander: GlobalAgent = WorldSimulation.world.agents.find(commander_id) as GlobalAgent
	if not _check(commander != null and not WorldSimulation.alife_enabled, "The imperial army is missing in the normal game"):
		return
	var start: Vector2i = commander.tile
	_check(not WorldSimulation.world.narrative.get("political_armies", {}).has(SOUTH), "Political map revealed an unseen column")
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(start + Vector2i(0, 4)))
	var unit: NPCBase = await _wait_for_unit(commander_id)
	if not _check(is_instance_valid(unit) and unit.model_id() == "sergeant" and unit.get_parent().y_sort_enabled,
		"The army commander did not materialize as a Y sorted NPC"):
		return
	var deadline: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline and Config.tile_distance(start, Config.iso_to_world(unit.global_position)) < 3:
		await get_tree().process_frame
	if not _check(Config.tile_distance(start, Config.iso_to_world(unit.global_position)) >= 3, "The materialized commander did not walk"):
		return
	_check(WorldSimulation.world.narrative.get("political_armies", {}).has(SOUTH), "A visible column was not observed on the political map")
	var strength: float = ImperialArmySystem.speed_multiplier(commander)
	var escort_id: String = ImperialArmySystem.unit_id(SOUTH, 1)
	var escort: NPCBase = await _wait_for_unit(escort_id)
	if not _check(is_instance_valid(escort), "The marching escort did not materialize"):
		return
	var escort_record: GlobalAgent = WorldSimulation.world.agents.find(escort_id) as GlobalAgent
	var morale_before: float = escort_record.morale
	commander.morale = 0.25
	unit.take_damage(60.0)
	await get_tree().create_timer(1.0).timeout
	_check(ImperialArmySystem.speed_multiplier(commander) < strength and escort_record.morale < morale_before,
		"A wounded, demoralized commander did not slow the column or lower its morale")
	escort.take_damage(escort.stats.health + 1.0)
	var position_before: Vector2i = Config.iso_to_world(unit.global_position)
	var army_before: Dictionary = WorldSimulation.world.narrative[ImperialArmySystem.SAVE_KEY][SOUTH].duplicate()
	if not _check(save_system.save_slot(slot) and save_system.load_slot(slot) and WorldSimulation.last_load_error.is_empty(),
		"The marching army did not survive save/load: " + WorldSimulation.last_load_error):
		return
	commander = WorldSimulation.world.agents.find(commander_id) as GlobalAgent
	escort_record = WorldSimulation.world.agents.find(escort_id) as GlobalAgent
	var army_after: Dictionary = WorldSimulation.world.narrative[ImperialArmySystem.SAVE_KEY][SOUTH]
	_check(commander.tile == position_before and commander.health < commander.max_health and not escort_record.alive
		and army_before["waypoint"] == army_after["waypoint"] and army_before["direction"] == army_after["direction"],
		"Save/load changed column route, position, injuries or casualties")
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(FAR))
	await get_tree().create_timer(0.65).timeout
	_check(not WorldSimulation.world.agents.materialized.has(commander_id), "The army commander did not unload with the chunk")


func _wait_for_unit(id: String) -> NPCBase:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var entity: Variant = WorldSimulation.world.agents.materialized.get(id)
		if is_instance_valid(entity):
			return entity as NPCBase
		await get_tree().process_frame
	return null


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error(message)
	return condition
