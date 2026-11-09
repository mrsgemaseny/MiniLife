class_name CaravanTick
extends RefCounted

func tick(world: AlifeWorldContext) -> void:
	for route: CaravanRoute in world.routes.all():
		var home: AlifeSettlement = world.settlements.find(route.from_id) as AlifeSettlement
		if home == null or home.status in [AlifeSettlement.Status.RAZED, AlifeSettlement.Status.RUINS]:
			if route.active or route.paid_investment:
				CaravanEventGenerator.fail(world, route, "home_lost")
			continue
		if not route.active:
			if route.paid_investment:
				var resting_merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
				if resting_merchant == null or not resting_merchant.alive:
					CaravanEventGenerator.fail(world, route, "merchant_lost")
					continue
			CaravanRouteManager.dispatch(world, route)
			continue
		var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
		if route.cargo.is_empty():
			CaravanEventGenerator.fail(world, route, "cargo_lost")
			continue
		if merchant == null or not merchant.alive:
			CaravanEventGenerator.fail(world, route, "merchant_lost")
			continue
		if AgentLifecycle.living(world, route.guards).is_empty():
			CaravanEventGenerator.fail(world, route, "guard_lost")
			continue
		var destination: AlifeSettlement = world.settlements.find(route.destination_id) as AlifeSettlement
		if destination == null or destination.status != AlifeSettlement.Status.NORMAL:
			CaravanEventGenerator.fail(world, route, "destination_lost")
			continue
		if route.ambush_phase == "preparing":
			CaravanAmbush.begin(world, route)
			if route.ambush_phase == "preparing":
				continue
		if route.ambush_phase == "active":
			CaravanAmbush.tick(world, route)
			if route.ambush_phase == "active" or not route.active:
				continue
		var remaining: float = Vector2(merchant.tile).distance_to(Vector2(merchant.destination_tile))
		route.progress = clampf(1.0 - remaining / maxf(1.0, route.outbound_distance), 0.0, 1.0)
		var local: bool = world.agents.materialized.has(route.merchant_id)
		for id: String in route.guards:
			local = local or world.agents.materialized.has(id)
		if not route.risk_checked and route.progress >= 0.5 and remaining > 2.0:
			route.risk_checked = true
			if world.rng.randf() > CaravanSuccessCalc.calc(world, route):
				if local:
					CaravanAmbush.begin(world, route)
					continue
				var reason: String = ["bandits", "weather", "breakdown"][world.rng.randi_range(0, 2)]
				CaravanEventGenerator.fail(world, route, reason)
				continue
		if remaining <= 2.0:
			var gathered: bool = true
			for guard: GlobalAgent in AgentLifecycle.living(world, route.guards):
				if Config.tile_distance(guard.tile, merchant.destination_tile) > 6.0:
					gathered = false
			if gathered and not CaravanRouteManager.arrive(world, route) and world.simulated_hour - route.departure_hour > 96.0:
				CaravanEventGenerator.fail(world, route, "market_closed")
			elif not gathered and world.simulated_hour - route.departure_hour > 96.0:
				CaravanEventGenerator.fail(world, route, "escort_separated")
		elif world.simulated_hour - route.departure_hour > 96.0:
			CaravanEventGenerator.fail(world, route, "route_blocked")
