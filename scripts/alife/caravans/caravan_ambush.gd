class_name CaravanAmbush
extends RefCounted

static func begin(world: AlifeWorldContext, route: CaravanRoute) -> bool:
	if not route.active or route.ambush_phase == "active":
		return false
	var home: AlifeSettlement = world.settlements.find(route.from_id) as AlifeSettlement
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	if home == null or home.owner_faction == "bandits" or merchant == null:
		return false
	if route.ambush_phase != "preparing":
		route.ambush_phase = "preparing"
		route.ambush_origin = merchant.tile
		route.ambush_started_hour = world.simulated_hour
	if world.simulated_hour - route.ambush_started_hour > 2.0:
		route.ambush_phase = "cancelled"
		return false
	var road: Array[Vector2i] = world.travel.request_path(world.world_seed, route.ambush_origin, merchant.destination_tile)
	if road.is_empty() and world.travel.is_path_pending(world.world_seed, route.ambush_origin, merchant.destination_tile):
		return false
	if road.size() < 3:
		route.ambush_phase = "cancelled"
		return false
	var candidates: Array = world.agents.by_faction("bandits")
	candidates.sort_custom(func(a: GlobalAgent, b: GlobalAgent) -> bool: return Vector2(a.tile).distance_squared_to(Vector2(merchant.tile)) < Vector2(b.tile).distance_squared_to(Vector2(merchant.tile)))
	for agent: GlobalAgent in candidates:
		if Config.tile_distance(agent.tile, merchant.tile) > 64.0:
			continue
		if not agent.alive or agent.unique or not agent.role in ["guard", "soldier", "bandit"]:
			continue
		if not agent.caravan_id.is_empty() or not agent.deployment_id.is_empty() or not agent.ambush_route_id.is_empty() or world.agents.materialized.has(agent.agent_id):
			continue
		agent.ambush_original_role = agent.role
		agent.ambush_route_id = route.route_id
		if agent.role in ["guard", "soldier"]:
			var settlement: AlifeSettlement = world.settlements.find(agent.settlement_id) as AlifeSettlement
			if settlement != null:
				settlement.garrison = maxi(0, settlement.garrison - 1)
		agent.role = "bandit"
		agent.tile = road[mini(road.size() - 1, 6 + route.ambushers.size())]
		agent.world_position.clear()
		agent.local_state.clear()
		agent.destination_tile = merchant.tile
		agent.current_goal = "ambush_caravan"
		route.ambushers.append(agent.agent_id)
		if route.ambushers.size() >= 4:
			break
	if route.ambushers.is_empty():
		route.ambush_phase = "cancelled"
		return false
	route.ambush_phase = "active"
	route.ambush_started_hour = world.simulated_hour
	world.record_event("caravan_ambush_started", merchant.tile, [home.owner_faction, "bandits"], {"route_id": route.route_id, "settlement_id": route.from_id})
	return true

static func tick(world: AlifeWorldContext, route: CaravanRoute) -> void:
	if route.ambush_phase != "active":
		return
	var raiders: Array = AgentLifecycle.living(world, route.ambushers)
	var guards: Array = AgentLifecycle.living(world, route.guards)
	if raiders.is_empty():
		route.ambush_phase = "repelled"
		release(world, route)
		world.record_event("caravan_defended", _tile(world, route), [], {"route_id": route.route_id})
		return
	if guards.is_empty():
		CaravanEventGenerator.fail(world, route, "bandits")
		return
	for id: String in route.ambushers + route.guards + [route.merchant_id]:
		if is_instance_valid(world.agents.materialized.get(id)):
			return # Local NPC combat owns all damage while anyone is present.
	if world.simulated_hour - route.ambush_started_hour < 2.0:
		return
	if ConflictResolver.strength(guards) * world.rng.randf_range(0.8, 1.2) >= ConflictResolver.strength(raiders) * world.rng.randf_range(0.8, 1.2):
		ConflictResolver._apply_losses(world, raiders, 0.55)
		ConflictResolver._apply_losses(world, guards, 0.1)
		route.ambush_phase = "repelled"
		release(world, route)
		world.record_event("caravan_defended", _tile(world, route), [], {"route_id": route.route_id})
	else:
		ConflictResolver._apply_losses(world, raiders, 0.2)
		CaravanEventGenerator.fail(world, route, "bandits")

static func release(world: AlifeWorldContext, route: CaravanRoute) -> void:
	for id: String in route.ambushers:
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent == null:
			continue
		agent.ambush_route_id = ""
		if agent.alive:
			agent.role = agent.ambush_original_role
			agent.current_goal = "return_home"
			agent.destination_tile = agent.home_tile
			var home: AlifeSettlement = world.settlements.find(agent.settlement_id) as AlifeSettlement
			if home != null and home.owner_faction == agent.faction_id and agent.role in ["guard", "soldier"]:
				home.garrison += 1
		agent.ambush_original_role = ""
	route.ambushers.clear()
	if route.ambush_phase in ["active", "preparing"]:
		route.ambush_phase = "ended"

static func _tile(world: AlifeWorldContext, route: CaravanRoute) -> Vector2i:
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	return merchant.tile if merchant != null else Vector2i.ZERO
