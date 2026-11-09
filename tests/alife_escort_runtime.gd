extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func fixture() -> AlifeWorldContext:
	var source: Node = load("res://tests/alife_caravans_runtime.gd").new()
	var world: AlifeWorldContext = source.fixture()
	source.free()
	CaravanRouteManager.dispatch(world, world.routes.find("a_to_b") as CaravanRoute)
	return world

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	WorldSimulation.set_process(false)
	SignalBus.world_tile_queried.connect(_open_test_ground)
	var world: AlifeWorldContext = fixture()
	var route: CaravanRoute = world.routes.find("a_to_b") as CaravanRoute
	var camp: AlifeSettlement = AlifeSettlement.new()
	camp.settlement_id = "camp"
	camp.owner_faction = "bandits"
	camp.population = 4
	camp.garrison = 4
	world.settlements.register(camp)
	for index: int in range(4):
		var bandit: GlobalAgent = GlobalAgent.new()
		bandit.agent_id = "bandit_%d" % index
		bandit.faction_id = "bandits"
		bandit.settlement_id = "camp"
		bandit.role = "guard"
		bandit.definition_id = "border_guard"
		bandit.tile = (world.agents.find(route.merchant_id) as GlobalAgent).tile + Vector2i(12, 0)
		bandit.home_tile = bandit.tile
		world.agents.register(bandit)
	var count_before: int = world.agents.all().size()
	world.travel.background_enabled = true
	check(not CaravanAmbush.begin(world, route) and route.ambush_phase == "preparing", "Background route request leaves ambush preparing rather than dropping the encounter")
	check(route.ambushers.is_empty() and camp.garrison == 4, "Pending path does not deploy guards before a valid road exists")
	check(AgentGoalEvaluator.evaluate(world.agents.find(route.merchant_id) as GlobalAgent, world) == "caravan_hold", "Merchant waits while encounter route is prepared")
	var preparing_save: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	world.travel.shutdown()
	world = AlifeWorldContext.from_dict(preparing_save)
	route = world.routes.find("a_to_b") as CaravanRoute
	camp = world.settlements.find("camp") as AlifeSettlement
	world.travel.background_enabled = true
	check(route.ambush_phase == "preparing" and route.ambush_origin == (world.agents.find(route.merchant_id) as GlobalAgent).tile, "Save preserves pending encounter and fixed path origin")
	var ready_deadline: int = Time.get_ticks_msec() + 5000
	while route.ambush_phase == "preparing" and Time.get_ticks_msec() < ready_deadline:
		CaravanTick.new().tick(world)
		await get_tree().create_timer(0.01).timeout
	world.travel.shutdown()
	check(route.ambush_phase == "active", "Caravan tick resumes a saved encounter after real worker completes")
	check(route.ambushers.size() == 4 and world.agents.all().size() == count_before and camp.garrison == 0, "Ambush neither invents population nor counts deployed raiders as home guards")
	check(not CaravanAmbush.begin(world, route), "Ambush cannot recruit twice for same encounter")
	var loaded: AlifeWorldContext = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(loaded != null and (loaded.routes.find(route.route_id) as CaravanRoute).ambushers == route.ambushers, "Save preserves ambush participants")
	WorldSimulation.world = world
	WorldSimulation.materializer.reset(world)
	var layer: Node2D = Node2D.new()
	add_child(layer)
	WorldSimulation.materializer.parent = layer
	for id: String in route.ambushers + route.guards + [route.merchant_id]:
		var entity: NPCBase = WorldSimulation.materializer.materialize(world.agents.find(id) as GlobalAgent)
		entity.set_physics_process(false)
	var guard_id: String = str(route.guards[0])
	var guard_scene: NPCBase = world.agents.materialized[guard_id] as NPCBase
	for id: String in route.ambushers:
		(world.agents.materialized[id] as NPCBase).global_position = guard_scene.global_position + Vector2(16.0, 0.0)
	var response: Dictionary = {}
	SignalBus.alife_combat_target_queried.emit(guard_id, response)
	check(response.get("target") is NPCBase, "Caravan guard acquires an actual ambusher scene")
	world.simulated_hour += 3.0
	CaravanAmbush.tick(world, route)
	check(AgentLifecycle.living(world, route.ambushers).size() == 4, "No abstract casualties are applied over a local fight")
	var combat: CombatSystem = CombatSystem.new()
	add_child(combat)
	seed(8)
	var cargo_before: int = CaravanRouteManager.cargo_value(route.cargo)
	for step: int in range(150):
		guard_scene._tick_ai(1.1)
		if AgentLifecycle.living(world, route.ambushers).is_empty():
			break
	CaravanAmbush.tick(world, route)
	check(route.ambush_phase == "repelled" and route.active, "Actual defeat of ambushers resumes the expedition")
	check(CaravanRouteManager.cargo_value(route.cargo) == cargo_before, "Defending convoy does not delete its cargo")
	check(camp.population == 0 and camp.garrison == 0, "Dead ambushers affect original population exactly once")
	WorldSimulation.materializer.reset(AlifeWorldContext.new())
	await get_tree().process_frame
	layer.queue_free()
	combat.queue_free()

	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	var home: AlifeSettlement = world.settlements.find("a") as AlifeSettlement
	var treasury: int = home.treasury
	check(EscortContracts.accept(world, route, 10.0), "Accept funded escort contract")
	check(home.treasury == treasury - 150 and not EscortContracts.accept(world, route, 10.0), "Reward is reserved once and contract cannot be accepted twice")
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	for step: int in range(1, 5):
		route.progress = float(step) * 0.2
		EscortContracts.observe(world, merchant.tile, 10.0 + float(step) * 0.1)
	world = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	route = world.routes.find("a_to_b") as CaravanRoute
	world.simulated_hour = 10.4
	EscortContracts.complete(world, route, true)
	var wallet: InventoryComponent = InventoryComponent.new()
	var id: String = EscortContracts.id_for(route)
	check(EscortContracts.claim(world, id, wallet) == 150 and wallet.silver == 150, "Accompanied delivery survives loading and pays reserved silver")
	check(EscortContracts.claim(world, id, wallet) == 0 and wallet.silver == 150, "Escort reward cannot be claimed twice")
	check((world.settlements.find("a") as AlifeSettlement).treasury + wallet.silver == treasury, "Reward transfers escrow rather than creating currency")
	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	home = world.settlements.find("a") as AlifeSettlement
	treasury = home.treasury
	EscortContracts.accept(world, route, 10.0)
	for step: int in range(1, 4):
		EscortContracts.observe(world, Vector2i(-1000, -1000), 10.0 + float(step))
	check(str(world.contracts[EscortContracts.id_for(route)]["state"]) == "failed" and home.treasury == treasury, "Leaving convoy fails escort and returns reserved funds")
	check(EscortContracts.claim(world, EscortContracts.id_for(route), wallet) == 0, "Absent escort cannot collect reward")
	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	EscortContracts.accept(world, route, 10.0)
	merchant = world.agents.find(route.merchant_id) as GlobalAgent
	for step: int in range(6):
		route.progress = 0.5 if step % 2 == 0 else 0.1
		EscortContracts.observe(world, merchant.tile, 10.0 + float(step + 1) * 0.1)
	check(float(world.contracts[EscortContracts.id_for(route)]["accompanied_progress"]) <= 0.5, "Convoy backtracking cannot manufacture escort progress")
	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	EscortContracts.accept(world, route, 10.0)
	EscortContracts.observe(world, Vector2i(-1000, -1000), 10.1)
	route.progress = 0.95
	merchant = world.agents.find(route.merchant_id) as GlobalAgent
	EscortContracts.observe(world, merchant.tile, 10.2)
	world.simulated_hour = 10.2
	EscortContracts.complete(world, route, true)
	check(str(world.contracts[EscortContracts.id_for(route)]["state"]) == "failed", "Rejoining at destination cannot claim travel performed while absent")
	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	world.reputation["outlaw_regions"] = {"a": true}
	check(not EscortContracts.accept(world, route, 10.0), "Known regional raider cannot take a fresh escort contract")
	var cadence_world: AlifeWorldContext = AlifeWorldContext.new()
	cadence_world.simulated_hour = 10.0
	var cadence_agent: GlobalAgent = GlobalAgent.new()
	cadence_agent.agent_id = "cadence"
	cadence_agent.role = "guard"
	cadence_world.agents.register(cadence_agent)
	var cadence: AgentTick = AgentTick.new()
	var piece: float = 5.0
	for step: int in range(5):
		cadence.tick(cadence_world, piece / Config.SECONDS_PER_GAME_HOUR)
	check(cadence_agent.current_goal == "idle", "Far agent does not tick before configured thirty-second interval")
	cadence.tick(cadence_world, piece / Config.SECONDS_PER_GAME_HOUR)
	check(cadence_agent.current_goal == "patrol_settlement", "Far agent ticks at thirty seconds under the current game-hour duration")
	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	route.progress = 0.9
	check(not EscortContracts.accept(world, route, 10.0), "Cannot sign escort after almost the whole journey is complete")
	route.progress = 0.0
	EscortContracts.accept(world, route, 10.0)
	CaravanEventGenerator.fail(world, route, "merchant_lost")
	check(str(world.contracts[EscortContracts.id_for(route)]["state"]) == "failed", "Failed expedition also fails its escort contract")
	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	route.risk_checked = true
	route.ambush_phase = "preparing"
	route.ambush_started_hour = world.simulated_hour - 3.0
	route.ambush_origin = (world.agents.find(route.merchant_id) as GlobalAgent).tile
	CaravanTick.new().tick(world)
	check(route.ambush_phase == "cancelled" and route.active and route.ambushers.is_empty(), "Expired background preparation releases convoy without fake losses or permanent hold")
	check(AgentGoalEvaluator.evaluate(world.agents.find(route.merchant_id) as GlobalAgent, world) == "caravan_travel", "Merchant resumes travel after preparation timeout")
	print("ALIFE ESCORT TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _open_test_ground(_tile: Vector2i, result: Dictionary) -> void:
	result["passable"] = true
	result["occupied"] = false
	result["fog_state"] = int(Config.FogState.VISIBLE)
