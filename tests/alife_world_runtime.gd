extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures <= 10:
			push_error(message)

func _ready() -> void:
	call_deferred("run")

func make_world(seed_value: int) -> AlifeWorldContext:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(seed_value, 10.0)
	WorldSeedBuilder.populate(world)
	return world

func signature(world: AlifeWorldContext) -> String:
	var rows: Array = []
	for settlement: AlifeSettlement in world.settlements.all():
		rows.append([settlement.settlement_id, settlement.tile.x, settlement.tile.y, settlement.population, settlement.owner_faction, settlement.connections])
	return JSON.stringify(rows)

func run() -> void:
	for seed_value: int in [12345, 54321, 77777]:
		var started: int = Time.get_ticks_msec()
		var world: AlifeWorldContext = make_world(seed_value)
		check(world.settlements.all().size() >= 10, "Enough settlements on seed %d" % seed_value)
		check(world.agents.all().size() >= 2000, "Large abstract population on seed %d" % seed_value)
		var terrain: TerrainGenerator = TerrainGenerator.new(seed_value)
		var count: int = 0
		for settlement: AlifeSettlement in world.settlements.all():
			count += settlement.population
			check(not PoiGenerator.RUIN_ANCHORS.has(Config.tile_to_chunk(settlement.tile)), "Preserve authored ruins")
			var layout: Dictionary = SettlementLayout.describe(settlement)
			var origin: Vector2i = layout["origin"]
			for x: int in range(settlement.footprint):
				for y: int in range(settlement.footprint):
					check(not terrain.get_biome_at(origin + Vector2i(x, y)) in ["water", "mountains"], "Dry settlement footprint")
			for other_id: String in settlement.connections:
				var other: AlifeSettlement = world.settlements.find(other_id) as AlifeSettlement
				check(other != null and other.connections.has(settlement.settlement_id), "Bidirectional graph")
		check(count == world.agents.all().size(), "Population and agent count agree")
		var reached: Dictionary = {}
		var pending: Array = [world.settlements.all()[0].settlement_id]
		while not pending.is_empty():
			var id: String = str(pending.pop_back())
			if reached.has(id):
				continue
			reached[id] = true
			for neighbor: String in (world.settlements.find(id) as AlifeSettlement).connections:
				pending.append(neighbor)
		check(reached.size() == world.settlements.all().size(), "Whole graph is reachable")
		var again: AlifeWorldContext = make_world(seed_value)
		check(signature(world) == signature(again), "Deterministic settlement layout and graph")
		check((world.agents.all()[12] as GlobalAgent).to_dict() == (again.agents.all()[12] as GlobalAgent).to_dict(), "Deterministic named population")
		print("ALIFE SEED ", seed_value, " settlements=", world.settlements.all().size(), " agents=", count, " generation_pair_ms=", Time.get_ticks_msec() - started)

	# Exercise a real NPC scene through an isolated A-Life world without writing saves.
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(42, 10.0)
	var settlement: AlifeSettlement = AlifeSettlement.new()
	settlement.settlement_id = "lifecycle"
	settlement.population = 1
	settlement.garrison = 1
	world.settlements.register(settlement)
	var agent: GlobalAgent = GlobalAgent.new()
	agent.agent_id = "lifecycle_guard"
	agent.definition_id = "border_guard"
	agent.faction_id = "village_folk"
	agent.settlement_id = settlement.settlement_id
	agent.role = "guard"
	agent.tile = Vector2i(32, 32)
	agent.max_health = 120.0
	agent.health = 73.0
	world.agents.register(agent)
	WorldSimulation.materializer.reset(world)
	WorldSimulation.world = world
	var layer: Node2D = Node2D.new()
	add_child(layer)
	var materializer: AgentMaterializer = WorldSimulation.materializer
	materializer.parent = layer
	materializer.player_tile = agent.tile
	materializer.loaded_chunks[Config.tile_to_chunk(agent.tile)] = true
	var entity: NPCBase = materializer.materialize(agent)
	check(entity != null and entity.stats.health == 73.0 and entity.stats.max_health == 120.0, "Materialization preserves health")
	check(entity.faction_id == "village_folk", "Snapshot faction overrides scene template")
	check(world.agents.get_all_global().is_empty(), "Materialized agent excluded from abstract tick")
	check(materializer.materialize(agent) == entity and layer.get_child_count() == 1, "Materialization is idempotent")
	entity.inventory.gold = 13
	entity.inventory.add_item("bread", 2)
	entity.memory.remember("helped", "player", 17, 1)
	entity.global_position += Vector2(3.25, 1.5)
	var saved_position: Vector2 = entity.global_position
	materializer.dematerialize(agent.agent_id)
	await get_tree().process_frame
	check(layer.get_child_count() == 0 and world.agents.get_all_global().size() == 1, "Dematerialize returns to abstract simulation")
	entity = materializer.materialize(agent)
	check(entity.global_position == saved_position, "Exact position survives scene replacement")
	check(entity.inventory.gold == 13 and entity.inventory.count_of("bread") == 2, "Inventory survives scene replacement")
	check(entity.memory.personal_opinion_of_player == 17 and entity.memory.memories.size() == 1, "Social memory survives scene replacement")
	materializer.unload_chunk(Config.tile_to_chunk(agent.tile))
	await get_tree().process_frame
	check(world.agents.materialized.is_empty(), "Chunk unload dematerializes residents")
	materializer.loaded_chunks[Config.tile_to_chunk(agent.tile)] = true
	entity = materializer.materialize(agent)
	entity.take_damage(500.0)
	SignalBus.entity_died.emit(entity, "world")
	await get_tree().process_frame
	check(not agent.alive and agent.health == 0.0, "Death persists globally")
	check(settlement.population == 0 and settlement.garrison == 0, "Death updates counts exactly once")
	check(materializer.materialize(agent) == null, "Dead unique identity never respawns")
	check(world.agents.materialized.is_empty(), "Death removes scene ownership")
	materializer.parent = null
	layer.queue_free()
	print("ALIFE WORLD TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
