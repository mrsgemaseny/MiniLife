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
		settlement.tile = anchor + (Vector2i(2, 2) if id == "a" else Vector2i(6, 6))
		settlement.owner_faction = "merchants"
		settlement.population = 20
		settlement.garrison = 8 if id == "a" else 0
		settlement.food = 500.0 if id == "a" else 0.0
		settlement.treasury = 20000
		settlement.market_funds = 30000
		settlement.economy_type = "agricultural" if id == "a" else "mining"
		settlement.stockpile = {"wool": 100} if id == "a" else {"iron_ore": 200}
		settlement.connections = ["b" if id == "a" else "a"]
		world.settlements.register(settlement)
		for index: int in range(20):
			var agent: GlobalAgent = GlobalAgent.new()
			agent.agent_id = "%s_%02d" % [id, index]
			agent.tile = settlement.tile
			agent.home_tile = agent.tile
			agent.settlement_id = id
			agent.faction_id = "merchants"
			agent.role = "trader" if id == "a" and index == 0 else ("guard" if id == "a" and index <= 8 else "farmer")
			world.agents.register(agent)
	var route: CaravanRoute = CaravanRoute.new()
	route.route_id = "a_to_b"
	route.from_id = "a"
	route.to_id = "b"
	route.at_id = "a"
	world.routes.register(route)
	return world

func money(world: AlifeWorldContext) -> int:
	var result: int = 0
	for settlement: AlifeSettlement in world.settlements.all():
		result += settlement.treasury + settlement.market_funds
	for faction: AlifeFaction in world.factions.all():
		result += faction.treasury
	return result

func _ready() -> void:
	var world: AlifeWorldContext = fixture()
	var route: CaravanRoute = world.routes.find("a_to_b") as CaravanRoute
	var home: AlifeSettlement = world.settlements.find("a") as AlifeSettlement
	var initial_treasury: int = home.treasury
	var initial_money: int = money(world)
	var initial_food: float = home.food
	check(CaravanRouteManager.dispatch(world, route), "Dispatch caravan with real stock and crew")
	check(route.active and not route.merchant_id.is_empty() and route.guards.size() == 4, "Caravan owns merchant and four guards")
	check(home.food < initial_food and not route.cargo.is_empty(), "Cargo removed from origin stock")
	check(home.garrison == 4, "Hired guards are not simultaneously counted in garrison")
	check(home.treasury == initial_treasury - route.investment - route.cargo_cost, "Capital and cargo procurement debited once")
	check(money(world) == initial_money, "Dispatch transfers money rather than creating it")
	check(not CaravanRouteManager.dispatch(world, route), "Active caravan cannot dispatch twice")
	check(not CaravanRouteManager.arrive(world, route), "Departure alone cannot claim arrival revenue")
	var resumed: AlifeWorldContext = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(resumed != null and (resumed.routes.find(route.route_id) as CaravanRoute).cargo == route.cargo, "Cargo survives save during expedition")
	var traveler: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	check(AgentGoalEvaluator.evaluate(traveler, world) == "caravan_travel", "Caravan goal overrides ambient routines")
	var agent_tick: AgentTick = AgentTick.new()
	var tick: CaravanTick = CaravanTick.new()
	for trip: int in range(5):
		if trip > 0:
			world.simulated_hour += 24.0
			EconomyTick.new().tick(world, 24.0)
			check(CaravanRouteManager.dispatch(world, route), "Repeat expedition with produced goods")
		route.risk_checked = true # Test transport accounting independently of the random risk model.
		agent_tick.tick(world, 2.0)
		tick.tick(world)
		check(not route.active and route.successful_trips == trip + 1, "Concrete agent arrival completes exactly one trip")
		check(home.treasury == initial_treasury - 1500 + (trip + 1) * 300, "Net revenue matches actual cargo procurement and sale")
		check(money(world) == initial_money, "Arrival preserves money across public and private ledgers")
	check(route.recovered_investment == 1500 and home.treasury == initial_treasury, "Five complete trips repay initial capital exactly")
	check(home.stock_tier >= 3, "ROI unlocks higher settlement stock tier")
	check((world.settlements.find("b") as AlifeSettlement).food > 0.0, "Food actually reaches destination")
	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	CaravanRouteManager.dispatch(world, route)
	route.cargo["food"] = 1
	AgentTick.new().tick(world, 2.0)
	check(CaravanRouteManager.arrive(world, route), "Remaining cargo can still be delivered after loss")
	check(route.successful_trips == 0 and route.recovered_investment < 300, "Partial cargo cannot claim a full successful trip or full margin")

	world = fixture()
	route = world.routes.find("a_to_b") as CaravanRoute
	var blockade: AlifeConflict = AlifeConflict.new()
	blockade.conflict_id = "blockade"
	blockade.target_settlement = "b"
	blockade.phase = "siege"
	world.conflicts.register(blockade)
	check(not CaravanRouteManager.dispatch(world, route), "Siege blocks dispatch")
	check(route.cargo.is_empty() and not route.paid_investment, "Rejected dispatch does not reserve money or goods")
	world.conflicts.clear()
	check(CaravanRouteManager.dispatch(world, route), "Dispatch resumes after blockade")
	home = world.settlements.find("a") as AlifeSettlement
	var after_dispatch: int = home.treasury
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	AgentLifecycle.mark_dead(world, merchant, "test")
	tick.tick(world)
	check(not route.active and not route.paid_investment and route.cargo.is_empty(), "Actual merchant death fails expedition")
	check(home.treasury == after_dispatch, "Failure does not debit already-spent investment twice")
	check(home.garrison == 8, "Surviving hired guards return to garrison accounting")
	check(route.next_departure_hour >= world.simulated_hour + 24.0 and route.next_departure_hour <= world.simulated_hour + 72.0, "Replacement waits one to three game days")
	var event_count: int = world.events.size()
	CaravanEventGenerator.fail(world, route, "merchant_lost")
	check(world.events.size() == event_count, "Failure is idempotent")
	var bridge: CaravanSystem = CaravanSystem.new()
	add_child(bridge)
	bridge.record_caravan_trip("city_ironford", true)
	bridge._on_day_passed(100)
	check(bridge.settlements.is_empty(), "Legacy bridge cannot create fictional towns or random revenue")
	bridge.queue_free()
	print("ALIFE CARAVAN TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
