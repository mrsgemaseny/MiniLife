class_name AgentRegistry
extends AlifeRegistry

var materialized: Dictionary = {}

func _init() -> void:
	super("agent_id", GlobalAgent.from_dict)

func get_all_global() -> Array:
	var result: Array = []
	for agent: GlobalAgent in all():
		if agent.alive and not materialized.has(agent.agent_id):
			result.append(agent)
	return result

func by_faction(id: String) -> Array:
	return matching("faction_id", id)

func by_settlement(id: String) -> Array:
	return matching("settlement_id", id)

func by_role(role: String) -> Array:
	return matching("role", role)
