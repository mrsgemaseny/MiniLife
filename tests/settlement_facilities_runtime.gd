extends Node

const VALDEN: Vector2i = Vector2i(7, 14)
const WAREHOUSE: Vector2i = Vector2i(552, 483)
const FORGE: Vector2i = Vector2i(578, 521)
const FIXTURE: String = "res://tests/fixtures/pixelbuilder_services.json"
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_editor_export()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var slot: String = "__settlement_facilities_" + Crypto.new().generate_random_bytes(16).hex_encode()
	GameManager.start_new_game(12345, slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	await _check_valden(scene, save_system, slot)
	save_system.delete_slot(slot)
	if failures == 0:
		print("SETTLEMENT_FACILITIES_RUNTIME_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check_editor_export() -> void:
	var base: SettlementBase = SettlementBase.load_from(FIXTURE, Vector2i(-1, -1), TerrainGenerator.GENERATOR_VERSION)
	if not _check(base != null and base.anchor == Vector2i(503, 506), "The PixelBuilder export did not supply its own entrance"):
		return
	_check(base.facility_at(Vector2i(501, 501)) == {"kind": "storage", "door": Vector2i(503, 505)}
		and base.facility_at(Vector2i(512, 501)) == {"kind": "forge", "door": Vector2i(513, 505)}
		and base.facility_at(Vector2i(523, 501)) == {"kind": "tavern", "door": Vector2i(525, 506)}, "The editor export lost a service or its door")
	var rotated: SettlementBase = base.rotated(1)
	_check(rotated.facility_at(Vector2i(508, 504)) == {"kind": "storage", "door": Vector2i(504, 506)}
		and rotated.block_at(Vector2i(504, 506)) == "door", "Rotating a base separated a fixture from its door")


func _check_valden(scene: Node, save_system: SaveSystem, slot: String) -> void:
	var world: WorldSystem = scene.get_node("World")
	var building: BuildingSystem = scene.get_node("World/BuildingSystem")
	var player: Player = scene.get_node("World/Player")
	var chest: ChestLootUI = scene.get_node("UILayer/ChestLoot")
	var craft: CraftMenuUI = scene.get_node("UILayer/CraftMenu")
	var terrain: TerrainGenerator = world.get_terrain()
	var legacy: TerrainGenerator = TerrainGenerator.new(12345, TerrainGenerator.EXPANDED_SETTLEMENT_BASES_VERSION)
	var site: Vector2i = terrain.get_graph().site_for_cell(VALDEN)["tile"]
	var origin: Vector2i = site - WorldData.settlement_bases()[VALDEN].anchor
	var warehouse: Vector2i = origin + WAREHOUSE
	var forge: Vector2i = origin + FORGE
	_check(legacy.get_settlement_facility(warehouse).is_empty() and legacy.get_settlement_facility(forge).is_empty()
		and legacy.get_settlement_block(warehouse) == "wood_floor" and legacy.is_dry_land(forge), "Version 7 gained a service fixture")
	_check(not terrain.is_dry_land(warehouse) and not world.is_passable(forge), "Service fixtures did not block their tiles")
	var sword_slot: int = 7
	player.inventory.set_slot(sword_slot, {"item_id": "iron_sword", "count": 1, "durability": 10})
	player.select_hotbar_slot(sword_slot)
	player.inventory.add_item("iron_ingot", 2)
	SignalBus.weapon_repair_requested.emit(player)
	_check(int(player.equipment.get_slot_entry("weapon")["durability"]) == 10 and player.inventory.count_of("iron_ingot") == 2,
		"The player repaired a weapon without a nearby forge")

	SignalBus.player_teleport_requested.emit(Config.world_to_iso(warehouse + Vector2i.LEFT))
	var storage: StructureEntity = await _wait_for_fixture("storage", warehouse)
	if not _check(storage != null and storage.is_settlement_base, "Valden's storage did not stream from the base"):
		return
	storage.interact(player)
	if not _check(chest.visible, "The storage fixture did not open the chest inventory"):
		return
	player.inventory.add_item("wood", 3)
	for index: int in range(player.inventory.slots.size()):
		if player.inventory.get_slot(index).get("item_id", "") == "wood":
			chest._on_player_slot_clicked(index, MOUSE_BUTTON_LEFT, false)
			break
	var stored: InventoryComponent = building.get_storage_manager().get_or_create_container(warehouse)
	_check(stored.count_of("wood") == 3 and player.inventory.count_of("wood") == 0, "Wood did not transfer into the warehouse")
	chest.close_panel()
	if not _check(save_system.save_slot(slot) and save_system.load_slot(slot) and WorldSimulation.last_load_error.is_empty(), "The warehouse save did not load"):
		return
	_check(building.get_storage_manager().get_or_create_container(warehouse).count_of("wood") == 3, "The warehouse lost its stored wood")
	var delta: Dictionary = SaveSystem._read_json(SaveSystem._chunk_file_path(slot, Config.tile_to_chunk(warehouse)))
	_check(not delta.get("structures", {}).has(Config.vec2i_to_key(warehouse)), "The warehouse fixture leaked into the chunk delta")

	SignalBus.player_teleport_requested.emit(Config.world_to_iso(forge + Vector2i.LEFT))
	var anvil: StructureEntity = await _wait_for_fixture("forge", forge)
	if not _check(anvil != null and anvil.is_settlement_base, "Valden's forge did not stream from the base"):
		return
	anvil.interact(player)
	if not _check(craft.visible and craft._repair_button.visible, "The forge did not offer the repair action"):
		return
	craft._repair_button.pressed.emit()
	var maximum: int = int(DataRegistry.get_item("iron_sword")["durability"])
	_check(int(player.equipment.get_slot_entry("weapon")["durability"]) == maximum and player.inventory.count_of("iron_ingot") == 1,
		"Repair did not restore durability at the price of one iron ingot")
	craft._repair_button.pressed.emit()
	_check(player.inventory.count_of("iron_ingot") == 1, "Repairing a sound weapon spent another ingot")
	craft.close_panel()
	player.select_hotbar_slot(0)
	player.select_hotbar_slot(sword_slot)
	_check(player.equipment.get_durability("weapon") == maximum, "Reselecting the sword undid the repair")
	_check(save_system.save_slot(slot) and save_system.load_slot(slot) and player.equipment.get_durability("weapon") == maximum,
		"The repaired sword lost durability after loading")


func _wait_for_fixture(kind: String, tile: Vector2i) -> StructureEntity:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		for node: Node in get_tree().get_nodes_in_group("structures"):
			if node is StructureEntity and node.structure_id == kind and node.tile_pos == tile and not node.is_queued_for_deletion():
				return node as StructureEntity
		await get_tree().process_frame
	return null


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error(message)
	return condition
