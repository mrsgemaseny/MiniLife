extends Node2D

class Actor extends Node2D:
	var inventory: InventoryComponent = InventoryComponent.new()
	var equipment: EquipmentComponent = EquipmentComponent.new()
	var skills: SkillsComponent = SkillsComponent.new()

class Raider extends Node2D:
	var faction_id: String = "bandits"
	var spawn_uid: String = "integrity_raider"

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("PROGRESSION_INTEGRITY_FAILURE: " + message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	GameManager.resume()
	var player: Player = load("res://scenes/entities/player.tscn").instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	check(player.inventory.get_item_count("stone_axe") == 1 and player.inventory.get_item_count("stone_pickaxe") == 1, "Current starter kit is missing tools")
	player._grant_starter_kit()
	check(player.inventory.get_item_count("stone_axe") == 1 and player.inventory.get_item_count("stone_pickaxe") == 1, "Starter kit duplicated tools")
	player.free()
	for seed_value in [12345, 1401, 90001]:
		var terrain: TerrainGenerator = TerrainGenerator.new(seed_value)
		var found: int = 0
		for x in range(8, 992, 4):
			for y in range(8, 992, 4):
				var tile: Vector2i = Vector2i(x, y)
				if terrain.get_resource_node_at(tile) == "clay_bank":
					check(terrain.get_biome_at(tile) != "water", "Clay spawned in water")
					check(terrain.get_resource_node_at(tile) == "clay_bank", "Clay placement is not deterministic")
					found += 1
					break
			if found >= 3:
				break
		check(found >= 3, "Clay unavailable in seed " + str(seed_value))
	var actor: Actor = Actor.new()
	add_child(actor)
	var ground: GroundLoot = GroundLoot.new()
	add_child(ground)
	actor.inventory.max_slots = 1
	actor.inventory.slots = [{"item_id": "stone_axe", "count": 1, "durability": 20}]
	var clay: ResourceNode = ResourceNode.new()
	clay.node_def_id = "clay_bank"
	add_child(clay)
	check(clay.can_harvest(actor).ok, "Clay requires an unavailable tool")
	clay._def = clay._def.duplicate(true)
	clay._def["drops"] = [{"item_id": "clay", "min": 3, "max": 3}]
	clay.interact(actor)
	check(ground.snapshot().size() == 1 and int(ground.snapshot()[0]["items"][0]["count"]) == 3, "Harvest overflow lost materials")
	clay.free()
	var corpse: CorpseEntity = CorpseEntity.new()
	corpse.species = "wolf"
	corpse.lifetime = 111.0
	corpse.items = [{"item_id": "iron_sword", "count": 1, "durability": 13}]
	add_child(corpse)
	var loot_save: Array = JSON.parse_string(JSON.stringify(ground.snapshot())) as Array
	ground.restore(loot_save)
	var restored_body: CorpseEntity = null
	for body in get_tree().get_nodes_in_group("corpses"):
		if body.is_inside_tree():
			restored_body = body
	check(restored_body != null and restored_body.species == "wolf" and restored_body.lifetime == 111.0, "Body identity or expiry lost on load")
	if restored_body != null:
		actor.inventory.max_slots = 2
		actor.inventory.slots.clear()
		restored_body.interact(actor)
		check(actor.inventory.get_item_count("iron_sword") == 1 and restored_body.items.is_empty(), "Restored corpse lost or duplicated loot")
		var count_empty: int = 0
		for row in ground.snapshot():
			if row.get("kind", "") == "corpse" and row.items.is_empty():
				count_empty += 1
		check(count_empty == 1, "Looted body disappeared from save")
	var progression: ProgressionSystem = ProgressionSystem.new()
	add_child(progression)
	SignalBus.npc_interacted.emit("early_contact")
	check(progression.npc_contact_made, "Early NPC contact not remembered")
	var raider: Raider = Raider.new()
	add_child(raider)
	raider.add_to_group("enemies")
	SignalBus.entity_died.emit(raider, "world")
	check(progression.defeated_raiders.is_empty(), "Ambient death credited to player")
	SignalBus.entity_died.emit(raider, "player")
	SignalBus.entity_died.emit(raider, "player")
	check(progression.defeated_raiders.size() == 1, "Duplicate death counted twice")
	for id in ["second", "third"]:
		raider.spawn_uid = id
		SignalBus.entity_died.emit(raider, "player")
	check(progression.repelled_bandit, "Three confirmed victories did not unlock milestone")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(progression.to_dict())) as Dictionary
	progression.reset_progression()
	progression.from_dict(saved)
	check(progression.repelled_bandit and progression.defeated_raiders.size() == 3 and progression.npc_contact_made, "Milestones lost on roundtrip")
	var building: BuildingSystem = BuildingSystem.new()
	add_child(building)
	building.set_process(false)
	var world: WorldSystem = WorldSystem.new()
	SignalBus.structure_built.connect(world._record_built_structure)
	SignalBus.world_tile_queried.connect(func(tile: Vector2i, response: Dictionary) -> void:
		response.merge({"passable": tile != Vector2i(2, 0), "occupied": false, "structure_id": ""}))
	actor.inventory.max_slots = 32
	actor.inventory.slots.clear()
	SignalBus.build_requested.emit("furnace", Vector2i(1, 0), actor)
	check(world.get_save_data()["chunk_deltas"].is_empty(), "Unaffordable build created a ghost world delta")
	SignalBus.resource_harvested.emit("wood", 30, Vector2i.ZERO)
	actor.inventory.add_item("stone", 12)
	SignalBus.build_requested.emit("furnace", Vector2i(2, 0), actor)
	check(actor.inventory.get_item_count("stone") == 12, "Blocked terrain consumed building materials")
	SignalBus.build_requested.emit("furnace", Vector2i(1, 0), actor)
	check(actor.inventory.get_item_count("stone") == 6 and building._placed_structures.size() == 1, "Build did not spend exactly once")
	check(not world.get_save_data()["chunk_deltas"].is_empty() and progression.built_furnace, "Successful construction not recorded")
	SignalBus.build_requested.emit("furnace", Vector2i(1, 0), actor)
	check(actor.inventory.get_item_count("stone") == 6 and building._placed_structures.size() == 1, "Repeated build duplicated or charged twice")
	SignalBus.build_requested.emit("furnace", Vector2i(10, 0), actor)
	check(actor.inventory.get_item_count("stone") == 6, "Remote construction consumed resources")
	world.free()
	print("PROGRESSION_INTEGRITY_RESULT: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
