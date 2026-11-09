extends RefCounted

static func validate(world: AlifeWorldContext) -> String:
	var history_error: String = _validate_history(world)
	if not history_error.is_empty():
		return history_error
	var travelers: Variant = world.narrative.get("refugee_travelers", {})
	if not travelers is Dictionary:
		return "Invalid refugee travel data."
	for id: Variant in travelers:
		if not id is String or not travelers[id] is String or world.agents.find(id) == null or world.settlements.find(travelers[id]) == null:
			return "Invalid refugee traveler or destination."
	var camps: Variant = world.narrative.get("refugee_camps", {})
	if not camps is Dictionary:
		return "Invalid refugee camps."
	var camp_members: Dictionary = {}
	for row: Variant in camps.values():
		if not row is Dictionary or not _tile_pair(row.get("tile")) or not row.get("members") is Array:
			return "Invalid refugee camp data."
		if not _finite_number(row.get("food", 0.0)) or float(row.get("food", 0.0)) < 0.0:
			return "Invalid refugee camp provisions."
		for id: Variant in row["members"]:
			if not id is String or not travelers.has(id) or camp_members.has(id):
				return "Invalid or repeated refugee camp member."
			camp_members[id] = true
	for faction: AlifeFaction in world.factions.all():
		var error: String = _validate_faction(world, faction)
		if not error.is_empty():
			return error
	for treaty: AlifeTreaty in world.treaties.all():
		if treaty.factions.size() != 2:
			return "Treaty %s does not have two parties." % treaty.treaty_id
		var error: String = _validate_ids(treaty.factions, world.factions, treaty.treaty_id)
		if not error.is_empty():
			return error
	for settlement: AlifeSettlement in world.settlements.all():
		if not settlement.owner_faction.is_empty() and world.factions.find(settlement.owner_faction) == null:
			return "Unknown owner for settlement %s." % settlement.settlement_id
		var error: String = _validate_ids(settlement.connections, world.settlements, settlement.settlement_id)
		if not error.is_empty():
			return error
	for agent: GlobalAgent in world.agents.all():
		if not agent.settlement_id.is_empty() and world.settlements.find(agent.settlement_id) == null:
			return "Unknown home settlement for %s." % agent.agent_id
		if not agent.faction_id.is_empty() and world.factions.find(agent.faction_id) == null:
			return "Unknown faction for %s." % agent.agent_id
		if not agent.caravan_id.is_empty() and world.routes.find(agent.caravan_id) == null:
			return "Unknown caravan for %s." % agent.agent_id
		if not agent.ambush_route_id.is_empty() and world.routes.find(agent.ambush_route_id) == null:
			return "Unknown ambush route for %s." % agent.agent_id
		if not agent.deployment_id.is_empty() and world.conflicts.find(agent.deployment_id) == null:
			return "Unknown deployment for %s." % agent.agent_id
	for route: CaravanRoute in world.routes.all():
		var error: String = _validate_caravan(world, route)
		if not error.is_empty():
			return error
	for conflict: AlifeConflict in world.conflicts.all():
		if conflict.resolved:
			continue
		if world.factions.find(conflict.attacker_id) == null or world.factions.find(conflict.defender_id) == null:
			return "Unknown participant in conflict %s." % conflict.conflict_id
		if not conflict.target_settlement.is_empty() and world.settlements.find(conflict.target_settlement) == null:
			return "Unknown target for conflict %s." % conflict.conflict_id
		if conflict.phase in ["marching", "siege", "assault"] and conflict.target_settlement.is_empty():
			return "Active conflict %s has no target." % conflict.conflict_id
		var error: String = _validate_ids(conflict.attacker_agents + conflict.defender_agents, world.agents, conflict.conflict_id)
		if not error.is_empty():
			return error
	return ""

static func _validate_faction(world: AlifeWorldContext, faction: AlifeFaction) -> String:
	if not faction.capital_id.is_empty() and world.settlements.find(faction.capital_id) == null:
		return "Unknown capital for %s." % faction.faction_id
	if not faction.leader_id.is_empty() and world.agents.find(faction.leader_id) == null:
		return "Unknown leader for %s." % faction.faction_id
	if not faction.recognized_heir_id.is_empty() and world.agents.find(faction.recognized_heir_id) == null:
		return "Unknown recognized heir for %s." % faction.faction_id
	return _validate_ids(faction.succession_list, world.agents, faction.faction_id)

static func _validate_history(world: AlifeWorldContext) -> String:
	if world.next_event_id < 1 or world.rumor_cursor < 0 or world.rumor_cursor >= world.next_event_id:
		return "Invalid chronicle cursor."
	var previous: int = 0
	for row: Dictionary in world.events:
		var id: Variant = row.get("event_id")
		if not _whole_number(id) or int(id) <= previous or int(id) >= world.next_event_id:
			return "Out-of-order or duplicate event in the chronicle."
		previous = int(id)
		if not row.get("event_type") is String or str(row["event_type"]).is_empty() \
				or not _tile_pair(row.get("location")) or not _finite_number(row.get("timestamp")) \
				or not row.get("participants") is Array or not row.get("data") is Dictionary:
			return "Invalid event %d in the chronicle." % previous
	var rumor_ids: Dictionary = {}
	for row: Dictionary in world.rumors:
		var rumor_id: Variant = row.get("rumor_id")
		var event_id: Variant = row.get("event_id")
		if not _whole_number(rumor_id) or int(rumor_id) < 1 or rumor_ids.has(int(rumor_id)) \
				or not _whole_number(event_id) or int(event_id) < 1 or int(event_id) > world.rumor_cursor:
			return "Invalid rumor identity or source event."
		rumor_ids[int(rumor_id)] = true
		if not _tile_pair(row.get("origin_tile")) or not _finite_number(row.get("created_hour")) \
				or not row.get("content") is String or not row.get("known_by") is Array or not row.get("received_at") is Dictionary:
			return "Invalid rumor %d." % int(rumor_id)
		var error: String = _validate_ids(row["known_by"], world.settlements, "rumor %d" % int(rumor_id))
		if not error.is_empty():
			return error
		var receptions: Dictionary = row["received_at"]
		if receptions.size() != row["known_by"].size():
			return "Rumor %d has inconsistent carriers." % int(rumor_id)
		for id: String in row["known_by"]:
			var reception: Variant = receptions.get(id)
			if not reception is Dictionary or not reception.get("content") is String \
					or not _finite_number(reception.get("hour")) or not _whole_number(reception.get("hops")) \
					or int(reception["hops"]) < 0:
				return "Invalid reception in rumor %d." % int(rumor_id)
	return ""

static func _tile_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _whole_number(value[0]) and _whole_number(value[1])

static func _whole_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) == floorf(float(value)) and absf(float(value)) < 9.0e18

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _validate_caravan(world: AlifeWorldContext, route: CaravanRoute) -> String:
	if world.settlements.find(route.from_id) == null or world.settlements.find(route.to_id) == null:
		return "Unknown endpoint for caravan %s." % route.route_id
	if not route.at_id.is_empty() and route.at_id not in [route.from_id, route.to_id]:
		return "Invalid departure point for caravan %s." % route.route_id
	if not route.active:
		return ""
	if route.destination_id not in [route.from_id, route.to_id] or route.destination_id == route.at_id:
		return "Invalid destination for active caravan %s." % route.route_id
	return _validate_ids([route.merchant_id] + route.guards + route.ambushers, world.agents, route.route_id)

static func _validate_ids(ids: Array, registry: AlifeRegistry, owner: String) -> String:
	var seen: Dictionary = {}
	for id: Variant in ids:
		if not id is String or registry.find(id) == null or seen.has(id):
			return "Unknown or repeated reference in %s." % owner
		seen[id] = true
	return ""
