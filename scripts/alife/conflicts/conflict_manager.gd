class_name ConflictManager
extends RefCounted

static func get_for_faction(world: AlifeWorldContext, faction_id: String) -> Array:
	var result: Array = []
	for conflict: AlifeConflict in world.conflicts.all():
		if not conflict.resolved and faction_id in [conflict.attacker_id, conflict.defender_id]:
			result.append(conflict)
	return result

static func prepare_operation(world: AlifeWorldContext, conflict: AlifeConflict) -> bool:
	var target: AlifeSettlement = world.settlements.find(conflict.target_settlement) as AlifeSettlement
	if target == null or target.owner_faction != conflict.defender_id or target.status != AlifeSettlement.Status.NORMAL:
		return false
	conflict.attacker_agents.clear()
	conflict.defender_agents.clear()
	for agent: GlobalAgent in world.agents.by_settlement(target.settlement_id):
		if agent.alive and agent.faction_id == conflict.defender_id and agent.role in ["guard", "soldier"]:
			conflict.defender_agents.append(agent.agent_id)
	var homes: Array = world.settlements.matching("owner_faction", conflict.attacker_id)
	homes.sort_custom(func(a: AlifeSettlement, b: AlifeSettlement) -> bool: return Vector2(a.tile).distance_squared_to(Vector2(target.tile)) < Vector2(b.tile).distance_squared_to(Vector2(target.tile)))
	var maximum_distance: float = 0.0
	for home: AlifeSettlement in homes:
		var reserve: int = maxi(1, home.garrison / 2)
		var selected: int = 0
		for agent: GlobalAgent in world.agents.by_settlement(home.settlement_id):
			if not agent.alive or not agent.deployment_id.is_empty() or not agent.caravan_id.is_empty() or not agent.role in ["guard", "soldier"]:
				continue
			if selected >= reserve or conflict.attacker_agents.size() >= 48:
				break
			agent.deployment_id = conflict.conflict_id
			agent.destination_tile = target.tile + Vector2i(-2, 0)
			agent.current_goal = "march_to_frontline"
			agent.local_state.clear()
			conflict.attacker_agents.append(agent.agent_id)
			selected += 1
			maximum_distance = maxf(maximum_distance, Vector2(home.tile).distance_to(Vector2(target.tile)))
	if conflict.attacker_agents.is_empty():
		return false
	conflict.phase = "marching"
	conflict.phase_started_hour = world.simulated_hour
	conflict.assault_hour = world.simulated_hour + maxf(1.0, maximum_distance / 8.0) + 24.0
	return true

static func release_operation(world: AlifeWorldContext, conflict: AlifeConflict) -> void:
	for id: String in conflict.attacker_agents:
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent == null:
			continue
		agent.deployment_id = ""
		agent.current_goal = "return_home" if agent.alive else "dead"
		agent.destination_tile = agent.home_tile
		agent.local_state.clear()
	conflict.attacker_agents.clear()
	conflict.defender_agents.clear()

static func has_local_participants(world: AlifeWorldContext, conflict: AlifeConflict) -> bool:
	for id: String in conflict.attacker_agents + conflict.defender_agents:
		if world.agents.materialized.has(id):
			return true
	return false

static func next_target(world: AlifeWorldContext, conflict: AlifeConflict) -> String:
	var result: String = ""
	var weakest: int = 2147483647
	for home: AlifeSettlement in world.settlements.matching("owner_faction", conflict.attacker_id):
		for neighbor: AlifeSettlement in world.settlements.get_connected(home.settlement_id):
			if neighbor.owner_faction == conflict.defender_id and neighbor.status == AlifeSettlement.Status.NORMAL and neighbor.garrison < weakest:
				weakest = neighbor.garrison
				result = neighbor.settlement_id
	return result
