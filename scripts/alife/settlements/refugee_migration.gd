extends RefCounted

const MAX_DEPARTURES: int = 12

static func tick(world: AlifeWorldContext, hours: float) -> void:
	var travelers: Dictionary = world.narrative.get("refugee_travelers", {})
	var camps: Dictionary = {}
	var former_camps: Dictionary = world.narrative.get("refugee_camps", {})
	for id: String in travelers.keys():
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent == null or not agent.alive:
			travelers.erase(id)
			continue
		var destination: AlifeSettlement = world.settlements.find(str(travelers[id])) as AlifeSettlement
		if destination == null or destination.status != AlifeSettlement.Status.NORMAL:
			if agent.settlement_id.is_empty():
				var alternate: AlifeSettlement = _reachable_destination(world, agent.tile, world.settlements.all())
				if alternate != null:
					travelers[id] = alternate.settlement_id
					agent.destination_tile = alternate.tile + Vector2i.DOWN
				else:
					agent.destination_tile = agent.tile
					var camp_id: String = Config.vec2i_to_key(Config.tile_to_chunk(agent.tile))
					if not camps.has(camp_id):
						camps[camp_id] = {
							"tile": former_camps.get(camp_id, {}).get("tile", [agent.tile.x, agent.tile.y]),
							"food": float(former_camps.get(camp_id, {}).get("food", 0.0)),
							"members": [],
						}
					camps[camp_id]["members"].append(agent.agent_id)
				continue
			travelers.erase(id)
			agent.destination_tile = agent.home_tile
			agent.current_goal = "return_home"
			continue
		if agent.tile != agent.destination_tile:
			continue
		var source: AlifeSettlement = world.settlements.find(agent.settlement_id) as AlifeSettlement
		if source != null:
			source.population = maxi(0, source.population - 1)
		agent.settlement_id = destination.settlement_id
		agent.faction_id = destination.owner_faction
		agent.home_tile = agent.tile
		destination.population += 1
		travelers.erase(id)
		world.record_event("refugee_arrived", destination.tile, [id], {"settlement_id": destination.settlement_id})
	var pending: Dictionary = world.narrative.get("refugee_departures", {})
	for id: String in pending.keys():
		var source: AlifeSettlement = world.settlements.find(id) as AlifeSettlement
		if source == null or source.status != AlifeSettlement.Status.RAZED or source.population <= 0:
			pending.erase(id)
			continue
		var destination: AlifeSettlement = _safe_destination(world, source)
		if destination == null:
			continue
		var count: int = 0
		var limit: int = clampi(source.population / 4, 1, MAX_DEPARTURES)
		for agent: GlobalAgent in world.agents.by_settlement(id):
			if count >= limit:
				break
			if not agent.alive or agent.unique or agent.role not in ["civilian", "farmer", "worker"]:
				continue
			if travelers.has(agent.agent_id) or not agent.caravan_id.is_empty() or not agent.deployment_id.is_empty() or not agent.ambush_route_id.is_empty():
				continue
			agent.destination_tile = destination.tile + Vector2i.DOWN
			travelers[agent.agent_id] = destination.settlement_id
			count += 1
		pending.erase(id)
		if count > 0:
			world.record_event("refugees_departed", source.tile, [source.owner_faction],
				{"settlement_id": id, "destination_id": destination.settlement_id, "count": count})
	world.narrative["refugee_travelers"] = travelers
	world.narrative["refugee_departures"] = pending
	for id: String in camps:
		var camp: Dictionary = camps[id]
		var demand: float = camp["members"].size() * maxf(0.0, hours) / 24.0
		var supplied: float = minf(float(camp["food"]), demand)
		camp["food"] = maxf(0.0, float(camp["food"]) - supplied)
		if demand > 0.0:
			var morale_delta: float = (supplied / demand * 0.008 - 0.004) * hours
			for member: String in camp["members"]:
				var agent: GlobalAgent = world.agents.find(member) as GlobalAgent
				agent.morale = clampf(agent.morale + morale_delta, 0.0, 1.0)
		if former_camps.has(id):
			continue
		var coords: Array = camps[id]["tile"]
		world.record_event("refugee_camp_formed", Vector2i(coords[0], coords[1]), [], {"count": camps[id]["members"].size()})
	world.narrative["refugee_camps"] = camps

static func _safe_destination(world: AlifeWorldContext, source: AlifeSettlement) -> AlifeSettlement:
	return _reachable_destination(world, source.tile, world.settlements.get_connected(source.settlement_id))

static func _reachable_destination(world: AlifeWorldContext, origin: Vector2i, candidates: Array) -> AlifeSettlement:
	for candidate: AlifeSettlement in candidates:
		if candidate.status != AlifeSettlement.Status.NORMAL or candidate.food <= float(candidate.population):
			continue
		var distance: int = Config.tile_distance(origin, candidate.tile)
		if distance <= 180 and not world.travel.request_path(world.world_seed, origin, candidate.tile + Vector2i.DOWN).is_empty():
			return candidate
	return null
