class_name CaravanEventGenerator
extends RefCounted

static func fail(world: AlifeWorldContext, route: CaravanRoute, reason: String) -> void:
	if not route.active and not route.paid_investment:
		return
	CaravanAmbush.release(world, route)
	EscortContracts.fail_route(world, route, reason)
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	var location: Vector2i = merchant.tile if merchant != null else Vector2i.ZERO
	if reason == "bandits":
		for guard: GlobalAgent in AgentLifecycle.living(world, route.guards):
			if world.rng.randf() < 0.5:
				AgentLifecycle.mark_dead(world, guard, "caravan_raid")
	var home: AlifeSettlement = world.settlements.find(route.from_id) as AlifeSettlement
	for id: String in [route.merchant_id] + route.guards:
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent == null:
			continue
		agent.caravan_id = ""
		if agent.alive:
			agent.current_goal = "return_home"
			agent.destination_tile = agent.home_tile
			if agent.role == "caravan_guard":
				var guard_home: AlifeSettlement = world.settlements.find(agent.settlement_id) as AlifeSettlement
				if guard_home != null and guard_home.owner_faction == agent.faction_id:
					agent.role = "guard"
					guard_home.garrison += 1
				else:
					agent.role = "deserter"
	route.guards.clear()
	CaravanCargo.make_wreck(world, route, location)
	route.cargo.clear()
	route.active = false
	route.paid_investment = false
	route.recovered_investment = 0
	route.successful_trips = 0
	route.at_id = route.from_id
	route.next_departure_hour = world.simulated_hour + float(world.rng.randi_range(1, 3)) * 24.0
	route.success_history.append({"success": false, "hour": world.simulated_hour, "reason": reason})
	if route.success_history.size() > 30:
		route.success_history.pop_front()
	world.record_event("caravan_raided" if reason in ["bandits", "guard_lost", "merchant_lost", "player"] else "caravan_failed", location, [home.owner_faction] if home != null else [], {"route_id": route.route_id, "settlement_id": route.from_id, "reason": reason})
