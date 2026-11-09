class_name AgentLifecycle
extends RefCounted

static func mark_dead(world: AlifeWorldContext, agent: GlobalAgent, cause: String) -> bool:
	if not agent.alive:
		return false
	agent.alive = false
	agent.health = 0.0
	var home: AlifeSettlement = world.settlements.find(agent.settlement_id) as AlifeSettlement
	if home != null:
		home.population = maxi(0, home.population - 1)
		if agent.role in ["guard", "soldier"]:
			home.garrison = maxi(0, home.garrison - 1)
	world.record_event("agent_died", agent.tile, [agent.agent_id], {"cause": cause})
	FactionSuccession.leader_died(world, agent.faction_id, agent.agent_id)
	return true

static func living(world: AlifeWorldContext, ids: Array, include_routed: bool = false) -> Array:
	var result: Array = []
	for id: String in ids:
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent != null and agent.alive and (include_routed or agent.morale >= 0.2):
			result.append(agent)
	return result
