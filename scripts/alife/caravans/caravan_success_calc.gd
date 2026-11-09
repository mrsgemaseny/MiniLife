class_name CaravanSuccessCalc
extends RefCounted

static func calc(world: AlifeWorldContext, route: CaravanRoute) -> float:
	var source: AlifeSettlement = world.settlements.find(route.at_id) as AlifeSettlement
	var destination: AlifeSettlement = world.settlements.find(route.destination_id) as AlifeSettlement
	if source == null or destination == null:
		return 0.05
	var distance_modifier: float = -minf(0.4, Vector2(source.tile).distance_to(Vector2(destination.tile)) / 500.0)
	var faction_modifier: float = -0.3 if FactionDiplomacy.at_war(world, source.owner_faction, destination.owner_faction) else 0.0
	var prosperity_modifier: float = (source.prosperity + destination.prosperity) * 0.001
	var guard_modifier: float = minf(0.12, float(AgentLifecycle.living(world, route.guards).size()) * 0.015)
	return clampf(route.base_success_chance + distance_modifier + faction_modifier + prosperity_modifier + guard_modifier, 0.05, 0.95)
