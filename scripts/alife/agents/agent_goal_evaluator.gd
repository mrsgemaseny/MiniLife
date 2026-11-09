class_name AgentGoalEvaluator
extends RefCounted

static func evaluate(agent: GlobalAgent, world: AlifeWorldContext) -> String:
	if world.narrative.get("refugee_travelers", {}).has(agent.agent_id):
		if agent.settlement_id.is_empty() and agent.tile == agent.destination_tile:
			return "refugee_camp"
		return "refugee_travel"
	if agent.health < 30.0 or agent.morale < 0.2:
		return "retreat_to_safety"
	if not agent.ambush_route_id.is_empty():
		return "ambush_caravan"
	if not agent.caravan_id.is_empty():
		var caravan: CaravanRoute = world.routes.find(agent.caravan_id) as CaravanRoute
		if caravan != null:
			if caravan.ambush_phase in ["active", "preparing"]:
				return "defend_caravan" if agent.role == "caravan_guard" else "caravan_hold"
			return "caravan_travel" if caravan.active else "caravan_rest"
	if not agent.deployment_id.is_empty():
		var deployment: AlifeConflict = world.conflicts.find(agent.deployment_id) as AlifeConflict
		if deployment != null and not deployment.resolved:
			return "assault_settlement" if deployment.phase == "siege" else "march_to_frontline"
	if agent.current_goal == "return_home" and agent.tile != agent.home_tile:
		return "return_home"
	for conflict: AlifeConflict in world.conflicts.all():
		if not conflict.resolved and conflict.phase == "siege" and conflict.target_settlement == agent.settlement_id:
			return "defend_settlement" if agent.role in ["guard", "soldier"] else "flee_settlement"
	var faction: AlifeFaction = world.factions.find(agent.faction_id) as AlifeFaction
	if faction != null and faction.state == AlifeFaction.State.AT_WAR:
		if agent.role in ["guard", "soldier"]:
			return "reinforce_frontline"
		if agent.role == "noble":
			return "manage_war_resources"
	var hour: float = fposmod(world.simulated_hour, 24.0)
	if (hour < 8.0 or hour >= 20.0) and agent.role not in ["guard", "bandit", "innkeeper"]:
		return "sleep"
	match agent.role:
		"trader": return "run_trade_route"
		"guard": return "patrol_settlement"
		"smith", "farmer", "worker": return "work"
		"bandit": return "raid_target"
		_: return "socialize" if hour >= 17.0 else "idle"

static func routine_destination(agent: GlobalAgent, world: AlifeWorldContext) -> Vector2i:
	var settlement: AlifeSettlement = world.settlements.find(agent.settlement_id) as AlifeSettlement
	if settlement == null or agent.current_goal == "sleep":
		return agent.home_tile
	var offset: int = posmod(agent.agent_id.hash(), 5) - 2
	match agent.current_goal:
		"run_trade_route":
			return settlement.tile + Vector2i(offset, 2)
		"work":
			var side: int = -1 if agent.role in ["smith", "worker"] else 1
			return settlement.tile + Vector2i(side * 3, 2 + offset)
		"socialize":
			return settlement.tile + Vector2i(offset, -2)
		"patrol_settlement":
			var corners: Array[Vector2i] = [Vector2i(-4, -4), Vector2i(4, -4), Vector2i(4, 4), Vector2i(-4, 4)]
			var patrol_index: int = posmod(int(world.simulated_hour * 2.0) + agent.agent_id.hash(), corners.size())
			return settlement.tile + corners[patrol_index]
		_:
			return agent.home_tile
