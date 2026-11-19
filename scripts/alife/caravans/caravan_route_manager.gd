class_name CaravanRouteManager
extends RefCounted

const CARGO_VALUES: Dictionary = {"food": 1, "wheat": 3, "iron_ore": 3, "stone": 1, "plank": 2, "wool": 2, "cloth": 5, "iron_ingot": 10}
const TRIP_MARGIN: int = 300
const MARKET_APPROACH: Vector2i = Vector2i(2, 2)
const CONVOY_SPACING: int = 2

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
	var returning: bool = route.grain_relief and destination_id == route.from_id
	var cargo: Dictionary = {}
	if route.grain_relief:
		if not returning and not destination.famine:
			return false
	else:
		cargo = _select_cargo(source, destination)
	var cost: int = cargo_value(cargo)
	if not route.grain_relief and (cost <= 0 or destination.market_funds < cost + TRIP_MARGIN):
		return false
	var source_tile: Vector2i = source.tile + MARKET_APPROACH if returning else source.tile
	var destination_tile: Vector2i = destination.tile if returning else destination.tile + MARKET_APPROACH
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	if merchant == null or not merchant.alive or (route.grain_relief and not _merchant_available(merchant, route, source_tile)):
		merchant = null
		if returning:
			return false
		for candidate: GlobalAgent in world.agents.by_settlement(home.settlement_id):
			if candidate.alive and candidate.role == "trader" and candidate.caravan_id.is_empty() \
					and (not route.grain_relief or _merchant_available(candidate, route, source_tile)):
				merchant = candidate
				break
	if merchant == null or Config.tile_distance(merchant.tile, source_tile) > 8.0:
		return false
	var guard_ids: Array = route.guards.duplicate()
	guard_ids = guard_ids.filter(func(id: String) -> bool:
		var guard: GlobalAgent = world.agents.find(id) as GlobalAgent
		return guard != null and guard.alive)
	if not route.paid_investment:
		guard_ids.clear()
	var recruits: Array = []
	if guard_ids.size() < 4 and not returning:
		for guard: GlobalAgent in world.agents.by_settlement(source.settlement_id):
			if guard.alive and guard.role == "guard" and guard.caravan_id.is_empty() and guard.deployment_id.is_empty() and guard.faction_id == source.owner_faction:
				if route.grain_relief and Config.tile_distance(guard.tile, source_tile) > 8.0:
					continue
				guard_ids.append(guard.agent_id)
				recruits.append(guard.agent_id)
				if guard_ids.size() >= 4:
					break
	if guard_ids.is_empty() or (not returning and guard_ids.size() < 4):
		return false
	var recruitment_cost: int = recruits.size() * 50 if route.paid_investment else 0
	var overhead: int = recruitment_cost + (0 if route.paid_investment else route.investment)
	var faction: AlifeFaction = world.factions.find(home.owner_faction) as AlifeFaction
	if route.grain_relief and not returning:
		var funding: int = home.treasury + (faction.treasury if faction != null else 0) - overhead
		cargo = _select_relief_grain(source, destination, mini(funding, destination.market_funds - TRIP_MARGIN))
		cost = cargo_value(cargo)
		if cost <= 0:
			return false
	var credit: int = maxi(0, cost + overhead - home.treasury)
	if credit > 0 and (faction == null or faction.treasury < credit):
		return false
	var path: Array[Vector2i] = world.travel.request_path(world.world_seed, source_tile, destination_tile, route.grain_relief)
	if path.is_empty():
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
	route.risk_checked = returning
	route.ambush_phase = "none"
	route.attacked_by_player = false
	route.departure_hour = world.simulated_hour
	if not returning:
		route.trip_id += 1
	route.outbound_distance = maxf(1.0, float(path.size() - 1))
	var crew: Array = [merchant.agent_id] + guard_ids
	for index: int in range(crew.size()):
		var id: String = crew[index]
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		agent.caravan_id = route.route_id
		agent.current_goal = "caravan_travel"
		agent.destination_tile = destination_tile
		if route.grain_relief:
			var start_index: int = 0
			if not world.agents.materialized.has(id):
				start_index = mini((crew.size() - 1 - index) * CONVOY_SPACING, path.size() - 1)
				agent.tile = path[start_index]
				agent.world_position.clear()
			world.travel.assign_path(world.world_seed, agent, path.slice(start_index))
		else:
			agent.local_state.clear()
	if not returning:
		world.record_event("caravan_departed", source.tile, [home.owner_faction], {"route_id": route.route_id, "settlement_id": source.settlement_id, "destination_id": destination_id, "cargo": cargo.duplicate()})
	return true

static func _merchant_available(merchant: GlobalAgent, route: CaravanRoute, source_tile: Vector2i) -> bool:
	return (merchant.caravan_id.is_empty() or merchant.caravan_id == route.route_id) \
		and merchant.deployment_id.is_empty() and Config.tile_distance(merchant.tile, source_tile) <= 8.0

static func _select_relief_grain(source: AlifeSettlement, destination: AlifeSettlement, available_funds: int) -> Dictionary:
	if destination.population <= 0 or available_funds <= 0:
		return {}
	var reserve_per_person: float = SettlementEconomy.FOOD_PER_PERSON_HOUR * SettlementEconomy.WHEAT_PER_PROVISION * SettlementEconomy.PROVISION_RESERVE_HOURS
	var reserve: int = ceili(float(source.population) * reserve_per_person)
	var surplus: int = int(source.stockpile.get("wheat", 0.0)) - reserve
	var amount: int = mini(surplus, ceili(float(destination.population) * reserve_per_person))
	amount = mini(amount, floori(float(available_funds) / float(CARGO_VALUES["wheat"])))
	var minimum: int = ceili(float(destination.population) * SettlementEconomy.FOOD_PER_PERSON_HOUR * SettlementEconomy.WHEAT_PER_PROVISION * 2.0)
	return {"wheat": amount} if amount >= minimum else {}

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
	if route.is_returning():
		_finish_leg(world, route, 1.0)
		return true
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
	_finish_leg(world, route, 1.0 if route.grain_relief else 24.0)
	world.record_event("caravan_arrived", destination.tile, [home.owner_faction], {"route_id": route.route_id, "settlement_id": destination.settlement_id, "home_id": home.settlement_id, "trips": route.successful_trips, "roi": route.recovered_investment >= route.investment})
	return true

static func _finish_leg(world: AlifeWorldContext, route: CaravanRoute, rest_hours: float) -> void:
	route.cargo.clear()
	route.active = false
	route.progress = 1.0
	route.at_id = route.destination_id
	route.next_departure_hour = world.simulated_hour + rest_hours
	for id: String in [route.merchant_id] + route.guards:
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent != null and agent.alive:
			agent.current_goal = "caravan_rest"

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
