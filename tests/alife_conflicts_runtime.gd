extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func fixture() -> AlifeWorldContext:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(12345, 10.0)
	var terrain: TerrainGenerator = TerrainGenerator.new(world.world_seed)
	var anchor: Vector2i = Vector2i(-1, -1)
	for cx: int in range(1, 15):
		anchor = WorldSeedBuilder._find_anchor(terrain, Vector2i(cx, 5), 8)
		if anchor.x >= 0:
			break
	for id: String in ["a", "b"]:
		var settlement: AlifeSettlement = AlifeSettlement.new()
		settlement.settlement_id = id
		settlement.name = id
		settlement.owner_faction = "merchants" if id == "a" else "bandits"
		settlement.tile = anchor + (Vector2i(2, 2) if id == "a" else Vector2i(6, 6))
		settlement.connections = ["b" if id == "a" else "a"]
		settlement.population = 40 if id == "a" else 10
		settlement.garrison = settlement.population
		settlement.treasury = 100
		world.settlements.register(settlement)
		for index: int in range(settlement.population):
			var agent: GlobalAgent = GlobalAgent.new()
			agent.agent_id = "%s_%d" % [id, index]
			agent.role = "guard"
			agent.definition_id = "border_guard"
			agent.settlement_id = id
			agent.faction_id = settlement.owner_faction
			agent.tile = settlement.tile
			agent.home_tile = agent.tile
			agent.equipment_tier = 4 if id == "a" else 1
			world.agents.register(agent)
	FactionDiplomacy.declare_war(world, "merchants", "bandits")
	return world

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var world: AlifeWorldContext = fixture()
	var tick: ConflictTick = ConflictTick.new()
	var conflict: AlifeConflict = world.conflicts.all()[0] as AlifeConflict
	var a_tile: Vector2i = (world.settlements.find("a") as AlifeSettlement).tile
	var b_tile: Vector2i = (world.settlements.find("b") as AlifeSettlement).tile
	var route: Array[Vector2i] = world.travel.path(world.world_seed, a_tile, b_tile)
	check(not route.is_empty() and route[0] == a_tile and route[-1] == b_tile, "Army has a concrete A-star land route")
	var terrain: TerrainGenerator = TerrainGenerator.new(world.world_seed)
	for tile: Vector2i in route:
		check(not terrain.get_biome_at(tile) in ["water", "mountains"], "Army route never crosses water or impassable mountains")
	check(world.travel.path(world.world_seed, Vector2i(-1, -1), b_tile).is_empty(), "Invalid travel endpoints are rejected")
	tick.tick(world, 0.5)
	check(conflict.phase == "marching" and conflict.attacker_agents.size() == 20, "Muster real agents while keeping half of home garrison")
	check(conflict.defender_agents.size() == 10, "Defenders are real settlement guards")
	tick.tick(world, 0.5)
	check(conflict.phase == "siege" and is_equal_approx(conflict.assault_hour - world.simulated_hour, 24.0), "Siege starts only after arrival and lasts one day")
	var resumed: AlifeWorldContext = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	world.simulated_hour = conflict.assault_hour
	resumed.simulated_hour = world.simulated_hour
	tick.tick(world, 0.5)
	tick.tick(resumed, 0.5)
	var target: AlifeSettlement = world.settlements.find("b") as AlifeSettlement
	check(target.owner_faction == "merchants" and conflict.last_winner == "merchants", "Stronger army captures settlement")
	check(target.population < 10 and (world.settlements.find("a") as AlifeSettlement).population < 40, "Battle casualties change actual populations")
	check(world.agents.matching("alive", false).size() > 0, "Casualties persist as dead identities")
	check(target.population == world.agents.by_settlement("b").filter(func(a: GlobalAgent) -> bool: return a.alive).size(), "Population is consistent with surviving agents")
	check(world.agents.to_array() == resumed.agents.to_array(), "Save continuation has identical casualty identities and morale")
	var dead_count: int = world.agents.matching("alive", false).size()
	tick.tick(world, 0.5)
	check(world.agents.matching("alive", false).size() == dead_count, "Completed battle cannot apply losses twice")
	for agent: GlobalAgent in world.agents.by_faction("merchants"):
		check(agent.deployment_id.is_empty(), "Released army has no stale deployment")

	world = fixture()
	(world.factions.find("bandits") as AlifeFaction).capital_id = "b"
	conflict = world.conflicts.all()[0] as AlifeConflict
	tick.tick(world, 0.5)
	tick.tick(world, 0.5)
	world.simulated_hour = conflict.assault_hour
	tick.tick(world, 0.5)
	check(conflict.resolved and (world.factions.find("bandits") as AlifeFaction).state == AlifeFaction.State.COLLAPSED, "Capital capture ends faction and war")
	check((world.factions.find("merchants") as AlifeFaction).state == AlifeFaction.State.STABLE, "Winner returns to peace after capital capture")

	world = fixture()
	target = world.settlements.find("b") as AlifeSettlement
	check(SettlementStatus.transition(world, target, AlifeSettlement.Status.UNGOVERNED) and target.owner_faction.is_empty(), "Ungoverned settlement loses political owner")
	check(SettlementStatus.transition(world, target, AlifeSettlement.Status.RUINS), "Settlement can become ruins")
	check(target.population == 0 and world.agents.by_settlement("b").filter(func(a: GlobalAgent) -> bool: return a.alive).is_empty(), "Ruins have no living residents")
	check(not SettlementStatus.transition(world, target, AlifeSettlement.Status.NORMAL), "Ruins do not spontaneously respawn population")

	# Local combat uses NPC scenes and the existing combat resolver, not abstract rolls.
	world = fixture()
	WorldSimulation.materializer.reset(world)
	WorldSimulation.world = world
	var layer: Node2D = Node2D.new()
	add_child(layer)
	WorldSimulation.materializer.parent = layer
	conflict = world.conflicts.all()[0] as AlifeConflict
	tick.tick(world, 0.5)
	tick.tick(world, 0.5)
	conflict.attacker_agents = ["a_0"]
	conflict.defender_agents = ["b_0"]
	var attacker: GlobalAgent = world.agents.find("a_0") as GlobalAgent
	var defender: GlobalAgent = world.agents.find("b_0") as GlobalAgent
	WorldSimulation.materializer.loaded_chunks[Config.tile_to_chunk(attacker.tile)] = true
	WorldSimulation.materializer.loaded_chunks[Config.tile_to_chunk(defender.tile)] = true
	var attacker_scene: NPCBase = WorldSimulation.materializer.materialize(attacker)
	var defender_scene: NPCBase = WorldSimulation.materializer.materialize(defender)
	attacker_scene.set_physics_process(false)
	defender_scene.set_physics_process(false)
	defender_scene.global_position = attacker_scene.global_position + Vector2(16.0, 0.0)
	world.simulated_hour = conflict.assault_hour
	tick.tick(world, 0.5)
	check(conflict.phase == "siege" and defender.alive and attacker.alive, "Global resolver does not apply casualties to live local combat")
	var combat: CombatSystem = CombatSystem.new()
	add_child(combat)
	seed(1)
	for step: int in range(200):
		attacker_scene._tick_ai(0.1)
		if not defender.alive:
			break
	check(not defender.alive, "NPC attacks use existing CombatSystem and kill actual opponent")
	tick.tick(world, 0.5)
	check(conflict.last_winner == "merchants" and attacker.alive, "Actual local outcome determines siege winner without extra abstract casualties")
	WorldSimulation.materializer.reset(AlifeWorldContext.new())
	WorldSimulation.materializer.parent = null
	await get_tree().process_frame
	layer.queue_free()
	combat.queue_free()
	_check_refugee_migration()
	print("ALIFE CONFLICT TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_refugee_migration() -> void:
	var world: AlifeWorldContext = fixture()
	var source: AlifeSettlement = world.settlements.find("a") as AlifeSettlement
	var destination: AlifeSettlement = world.settlements.find("b") as AlifeSettlement
	var refugee: GlobalAgent = world.agents.find("a_0") as GlobalAgent
	refugee.role = "civilian"
	source.garrison -= 1
	destination.food = 100.0
	SettlementStatus.transition(world, source, AlifeSettlement.Status.RAZED)
	var tick: AgentTick = AgentTick.new()
	tick.tick(world, 0.5)
	check(world.narrative.get("refugee_travelers", {}).has(refugee.agent_id) and refugee.settlement_id == "a",
		"Refugee leaves a razed town with its original identity")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	world = AlifeWorldContext.from_dict(saved)
	refugee = world.agents.find("a_0") as GlobalAgent
	for step: int in range(16):
		world.simulated_hour += 0.5
		tick.tick(world, 0.5)
	source = world.settlements.find("a") as AlifeSettlement
	destination = world.settlements.find("b") as AlifeSettlement
	check(refugee.alive and refugee.settlement_id == "b" and source.population == 39 and destination.population == 11,
		"Loaded refugee arrives and transfers exactly one resident")
	_check_stranded_refugee()

func _check_stranded_refugee() -> void:
	var world: AlifeWorldContext = fixture()
	var source: AlifeSettlement = world.settlements.find("a") as AlifeSettlement
	var destination: AlifeSettlement = world.settlements.find("b") as AlifeSettlement
	var refugee: GlobalAgent = world.agents.find("a_0") as GlobalAgent
	refugee.role = "civilian"
	source.garrison -= 1
	destination.food = 100.0
	SettlementStatus.transition(world, source, AlifeSettlement.Status.RAZED)
	var tick: AgentTick = AgentTick.new()
	tick.tick(world, 0.5)
	SettlementStatus.transition(world, source, AlifeSettlement.Status.RUINS)
	SettlementStatus.transition(world, destination, AlifeSettlement.Status.RAZED)
	tick.tick(world, 0.5)
	var camps: Dictionary = world.narrative.get("refugee_camps", {})
	check(refugee.alive and refugee.settlement_id.is_empty() and refugee.current_goal == "refugee_camp", "Displaced resident camps after losing both towns")
	check(camps.size() == 1 and camps.values()[0]["members"] == ["a_0"], "Camp retains the original refugee identity")
	camps.values()[0]["food"] = 2.0
	var morale: float = refugee.morale
	tick.tick(world, 0.5)
	check(float(world.narrative["refugee_camps"].values()[0]["food"]) < 2.0 and refugee.morale > morale,
		"Camp provisions are consumed and improve morale")
	world = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(preload("res://scripts/alife/save_reference_validator.gd").validate(world).is_empty(), "A stranded camp passes save reference validation")
	destination = world.settlements.find("b") as AlifeSettlement
	destination.food = 100.0
	SettlementStatus.transition(world, destination, AlifeSettlement.Status.NORMAL)
	for step: int in range(16):
		world.simulated_hour += 0.5
		tick.tick(world, 0.5)
	refugee = world.agents.find("a_0") as GlobalAgent
	check(refugee.settlement_id == "b" and world.narrative.get("refugee_camps", {}).is_empty(), "Camp dissolves once a loaded refugee resettles")
