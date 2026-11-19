extends Node

const CELL := Vector2i(7, 14)
const SEED: int = 12345
const SOURCE_ANCHOR := Vector2i(527, 512)

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var slot: String = "__valden_" + Crypto.new().generate_random_bytes(16).hex_encode()
	GameManager.start_new_game(SEED, slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	await _check_village(scene, save_system, slot)
	save_system.delete_slot(slot)
	if failures == 0:
		print("SETTLEMENT_BASE_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check_village(scene: Node, save_system: SaveSystem, slot: String) -> void:
	var world: WorldSystem = scene.get_node("World")
	var player: Player = scene.get_node("World/Player")
	var building: BuildingSystem = scene.get_node("World/BuildingSystem")
	var map: GlobalMapUI = scene.get_node("UILayer/GlobalMapUI")
	var terrain: TerrainGenerator = world.get_terrain()
	var site: Dictionary = terrain.get_graph().site_for_cell(CELL)
	if site.is_empty():
		_check(false, "The authored village has no site in cell (7,14)")
		return
	var origin: Vector2i = (site["tile"] as Vector2i) - SOURCE_ANCHOR
	var water: Vector2i = origin + Vector2i(508, 524)
	var road: Vector2i = origin + Vector2i(527, 524)
	var door_tile: Vector2i = origin + Vector2i(557, 524)
	var wall: Vector2i = door_tile + Vector2i.UP
	var floor_tile: Vector2i = door_tile + Vector2i.RIGHT
	var door_chunk: Vector2i = Config.tile_to_chunk(door_tile)
	var build_tile: Vector2i = door_tile + Vector2i(-2, 0)

	_check(GlobalLandscapeMap.cell_for_tile(GameManager.get_player_tile()) == Vector2i(9, 14), "The start moved")
	var old_terrain := TerrainGenerator.new(SEED, TerrainGenerator.SEAM_GENERATOR_VERSION)
	_check(old_terrain.get_settlement_block(water).is_empty(), "Version 3 unexpectedly changed its terrain")
	var batch: Dictionary = terrain.generate_chunk(Config.tile_to_chunk(water))
	_check(batch["biomes"].get(water) == "water" and batch["resources"].get(water) == ""
		and terrain.get_biome_at(water) == "water" and not terrain.is_dry_land(water), "Inconsistent river in the authored base")
	_check(not world.is_passable(wall) and world.get_tile(wall).structure_id == "wood_wall", "Walls are solid before chunk load")
	_check(world.is_passable(floor_tile) and world.get_tile(floor_tile).structure_id == "floor", "House has a walkable floor")
	for x: int in range(road.x, door_tile.x):
		var lane := Vector2i(x, road.y)
		_check(world.is_passable(lane) and terrain.get_resource_node_at(lane).is_empty(), "Village street is obstructed at %s" % str(lane))

	map.open_panel()
	map._selected_region = CELL
	_check(map._find_landing_tile(CELL) == road, "The village landing moved off the road")
	map._enter_selected_chunk()
	await get_tree().process_frame
	if not _check(GameManager.get_player_tile() == road, "The region opened outside its street"):
		return
	var elder_approach: Vector2i = (site["tile"] as Vector2i) + Vector2i.LEFT
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(elder_approach))
	await get_tree().process_frame
	var elder: NPCBase
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if node is NPCBase and node.npc_id == "village_elder" \
				and node.get_meta("settlement_id", "") == WorldLayout.settlement_id_for_cell(CELL):
			elder = node
			break
	if _check(elder != null, "The existing village elder did not appear beside the street"):
		var elder_tile: Vector2i = Config.iso_to_world(elder.global_position)
		_check(world.is_passable(elder_tile) and Config.tile_distance(elder_tile, elder_approach) <= 2,
			"The elder is not reachable from the road")
		var dialogue: Array[String] = []
		var hear := func(_npc_id: String, dialogue_id: String) -> void: dialogue.append(dialogue_id)
		SignalBus.dialogue_started.connect(hear)
		elder.interact(player)
		SignalBus.dialogue_started.disconnect(hear)
		_check(dialogue == ["elder_default"], "The elder's dialogue did not open")
		SignalBus.dialogue_end_requested.emit()

	SignalBus.player_teleport_requested.emit(Config.world_to_iso(door_tile + Vector2i.LEFT))
	await get_tree().process_frame
	var door: StructureEntity = _base_door(door_tile)
	if not _check(door != null and not door.is_door_open and not door._collision.disabled, "No closed door in the streamed house"):
		return
	door.interact(player)
	await get_tree().process_frame
	var door_state: Dictionary = {}
	SignalBus.door_state_queried.emit(door_tile, door_state)
	_check(door_state.get("open") == true and door._collision.disabled, "The door did not open with the existing interaction")
	_check(save_system.save_slot(slot), "Could not save the inspected village")
	_check(not FileAccess.file_exists(SaveSystem._chunk_file_path(slot, door_chunk)), "Visiting an unchanged house created a chunk file")
	var saved_buildings: Dictionary = SaveSystem._read_json(SaveSystem._slot_dir(slot) + "buildings.json")
	_check(saved_buildings.get("structures", []).is_empty() and saved_buildings.get("floors", []).is_empty(), "Base pieces leaked into the building save")

	_check(building.place_block_from_hand("wood_wall", build_tile, player), "Player could not build beside the house")
	_check(save_system.save_slot(slot), "Could not save the build")
	var saved_delta: Dictionary = SaveSystem._read_json(SaveSystem._chunk_file_path(slot, Config.tile_to_chunk(build_tile)))
	_check(saved_delta.get("structures", {}) == {Config.vec2i_to_key(build_tile): "wood_wall"}, "The chunk did not save only the player build")
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(WorldLayout.start_tile()))
	await get_tree().process_frame
	_check(not is_instance_valid(door) and _base_door(door_tile) == null, "The old chunk retained a house node")
	_check(save_system.load_slot(slot), "Could not reload the village slot")
	await get_tree().process_frame
	door = _base_door(door_tile)
	_check(door != null and not door.is_door_open, "Reload failed to reconstruct the authored door")
	_check(world.get_tile(build_tile).structure_id == "wood_wall", "The player build did not survive reload")


func _base_door(tile: Vector2i) -> StructureEntity:
	for node: Node in get_tree().get_nodes_in_group(StructureEntity._wall_group(tile)):
		if node is StructureEntity and node.is_settlement_base and node.structure_id == "door" and not node.is_queued_for_deletion():
			return node
	return null


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error("SETTLEMENT_BASE_FAILURE: " + message)
	return ok
