class_name CaravanRouteManager
extends RefCounted

const CARGO_VALUES: Dictionary = {"food": 1, "iron_ore": 3, "stone": 1, "plank": 2, "wool": 2, "cloth": 5, "iron_ingot": 10}
const TRIP_MARGIN: int = 300

static func seed_routes(world: AlifeWorldContext) -> void:
	for source: AlifeSettlement in world.settlements.all():
		for target_id: String in source.connections:
			var route: CaravanRoute = CaravanRoute.new()
			route.route_id = source.settlement_id + "->" + target_id
			route.from_id = source.settlement_id
			route.to_id = target_id
			route.at_id = source.settlement_id
			route.next_departure_hour = world.simulated_hour + float(world.routes.all().size() % 6)
			world.routes.register(route)

static func is_blockaded(world: AlifeWorldContext, settlement_id: String) -> bool:
	for conflict: AlifeConflict in world.conflicts.all():
		if not conflict.resolved and conflict.phase == "siege" and conflict.target_settlement == settlement_id:
			return true
	return false

static func dispatch(world: AlifeWorldContext, route: CaravanRoute) -> bool:
	if route.active or world.simulated_hour < route.next_departure_hour:
		return false
	if route.at_id.is_empty():
		route.at_id = route.from_id
	var home: AlifeSettlement = world.settlements.find(route.from_id) as AlifeSettlement
	var source: AlifeSettlement = world.settlements.find(route.at_id) as AlifeSettlement
	var destination_id: String = route.to_id if route.at_id == route.from_id else route.from_id
	var destination: AlifeSettlement = world.settlements.find(destination_id) as AlifeSettlement
	if home == null or source == null or destination == null or home.status != AlifeSettlement.Status.NORMAL or source.status != AlifeSettlement.Status.NORMAL or destination.status != AlifeSettlement.Status.NORMAL:
		return false
	if is_blockaded(world, source.settlement_id) or is_blockaded(world, destination.settlement_id):
		return false
	if FactionDiplomacy.at_war(world, source.owner_faction, destination.owner_faction):
		return false
	var cargo: Dictionary = _select_cargo(source, destination)
	var cost: int = cargo_value(cargo)
	if cost <= 0 or destination.market_funds < cost + TRIP_MARGIN:
		return false
	var destination_tile: Vector2i = destination.tile + Vector2i(2, 2)
	var path: Array[Vector2i] = world.travel.request_path(world.world_seed, source.tile, destination_tile)
	if path.is_empty():
		return false
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	if merchant == null or not merchant.alive:
		merchant = null
		for candidate: GlobalAgent in world.agents.by_settlement(home.settlement_id):
			if candidate.alive and candidate.role == "trader" and candidate.caravan_id.is_empty():
				merchant = candidate
				break
	if merchant == null:
		return false
	if Config.tile_distance(merchant.tile, source.tile) > 8.0:
		return false
	var guard_ids: Array = route.guards.duplicate()
	guard_ids = guard_ids.filter(func(id: String) -> bool:
		var guard: GlobalAgent = world.agents.find(id) as GlobalAgent
		return guard != null and guard.alive)
	if not route.paid_investment:
		guard_ids.clear()
	var recruits: Array = []
	if guard_ids.size() < 4:
		for guard: GlobalAgent in world.agents.by_settlement(source.settlement_id):
			if guard.alive and guard.role == "guard" and guard.caravan_id.is_empty() and guard.deployment_id.is_empty() and guard.faction_id == source.owner_faction:
				guard_ids.append(guard.agent_id)
				recruits.append(guard.agent_id)
				if guard_ids.size() >= 4:
					break
	if guard_ids.size() < 4:
		return false
	var recruitment_cost: int = recruits.size() * 50 if route.paid_investment else 0
	var required: int = cost + recruitment_cost + (0 if route.paid_investment else route.investment)
	var faction: AlifeFaction = world.factions.find(home.owner_faction) as AlifeFaction
	var credit: int = maxi(0, required - home.treasury)
	if credit > 0 and (faction == null or faction.treasury < credit):
		return false
	if credit > 0:
		faction.treasury -= credit
		home.treasury += credit
	if not route.paid_investment:
		home.treasury -= route.investment
		route.pack_state.clear()
		home.market_funds += route.investment
		route.invested_total += route.investment
		route.paid_investment = true
		route.successful_trips = 0
		route.recovered_investment = 0
	for id: String in recruits:
		var guard: GlobalAgent = world.agents.find(id) as GlobalAgent
		guard.role = "caravan_guard"
		source.garrison = maxi(0, source.garrison - 1)
	home.treasury -= recruitment_cost
	source.market_funds += recruitment_cost
	home.treasury -= cost
	source.market_funds += cost
	for item: String in cargo:
		if item == "food":
			source.food -= float(cargo[item])
		else:
			source.stockpile[item] = float(source.stockpile.get(item, 0.0)) - float(cargo[item])
	route.cargo = cargo
	route.cargo_cost = cost
	route.guards = guard_ids
	route.merchant_id = merchant.agent_id
	route.destination_id = destination_id
	route.active = true
	route.progress = 0.0
	route.risk_checked = false
	route.ambush_phase = "none"
	route.attacked_by_player = false
	route.departure_hour = world.simulated_hour
	route.trip_id += 1
	route.outbound_distance = maxf(1.0, float(path.size() - 1))
	for id: String in [merchant.agent_id] + guard_ids:
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		agent.caravan_id = route.route_id
		agent.current_goal = "caravan_travel"
		agent.destination_tile = destination_tile
		agent.local_state.clear()
	world.record_event("caravan_departed", source.tile, [home.owner_faction], {"route_id": route.route_id, "settlement_id": source.settlement_id, "destination_id": destination_id, "cargo": cargo.duplicate()})
	return true

static func arrive(world: AlifeWorldContext, route: CaravanRoute) -> bool:
	if not route.active:
		return false
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	if merchant == null or not merchant.alive or Config.tile_distance(merchant.tile, merchant.destination_tile) > 2.0:
		return false
	var destination: AlifeSettlement = world.settlements.find(route.destination_id) as AlifeSettlement
	var home: AlifeSettlement = world.settlements.find(route.from_id) as AlifeSettlement
	if destination == null or home == null or destination.status != AlifeSettlement.Status.NORMAL or is_blockaded(world, destination.settlement_id):
		return false
	var delivered_value: int = cargo_value(route.cargo)
	if delivered_value <= 0:
		return false
	var completeness: float = clampf(float(delivered_value) / float(maxi(1, route.cargo_cost)), 0.0, 1.0)
	var margin: int = int(floor(float(TRIP_MARGIN) * completeness))
	var payment: int = delivered_value + margin
	if destination.market_funds < payment:
		return false
	destination.market_funds -= payment
	home.treasury += payment
	for item: String in route.cargo:
		if item == "food":
			destination.food += float(route.cargo[item])
		else:
			destination.stockpile[item] = float(destination.stockpile.get(item, 0.0)) + float(route.cargo[item])
	var profit: int = payment - route.cargo_cost
	EscortContracts.complete(world, route, delivered_value >= route.cargo_cost)
	if delivered_value >= route.cargo_cost:
		route.successful_trips += 1
		home.caravan_successes += 1
	route.recovered_investment += profit
	if route.successful_trips >= 5 and route.recovered_investment >= route.investment:
		home.stock_tier = maxi(3, home.stock_tier)
		home.prosperity = minf(100.0, home.prosperity + 2.0)
	route.success_history.append({"success": delivered_value >= route.cargo_cost, "hour": world.simulated_hour, "profit": profit})
	if route.success_history.size() > 30:
		route.success_history.pop_front()
	route.cargo.clear()
	route.active = false
	route.progress = 1.0
	route.at_id = route.destination_id
	route.next_departure_hour = world.simulated_hour + 24.0
	for id: String in [route.merchant_id] + route.guards:
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent != null and agent.alive:
			agent.current_goal = "caravan_rest"
	world.record_event("caravan_arrived", destination.tile, [home.owner_faction], {"route_id": route.route_id, "settlement_id": destination.settlement_id, "home_id": home.settlement_id, "trips": route.successful_trips, "roi": route.recovered_investment >= route.investment})
	return true

static func cargo_value(cargo: Dictionary) -> int:
	var result: int = 0
	for item: String in cargo:
		result += int(cargo[item]) * int(CARGO_VALUES.get(item, 1))
	return result

static func _select_cargo(source: AlifeSettlement, destination: AlifeSettlement) -> Dictionary:
	var result: Dictionary = {}
	var surplus: int = maxi(0, int(source.food - float(source.population) * 1.2))
	var need: int = maxi(0, int(float(destination.population) * 6.0 - destination.food))
	if surplus > 0 and need > 0:
		result["food"] = mini(400, mini(surplus, need))
	for item: String in CARGO_VALUES:
		if item == "food":
			continue
		var amount: int = int(source.stockpile.get(item, 0.0))
		if amount > int(destination.stockpile.get(item, 0.0)):
			result[item] = mini(50, amount)
	return result
