class_name SettlementStatus
extends RefCounted

static func transition(world: AlifeWorldContext, settlement: AlifeSettlement, status: int) -> bool:
	if status < AlifeSettlement.Status.NORMAL or status > AlifeSettlement.Status.UNGOVERNED or settlement.status == status:
		return false
	if settlement.status == AlifeSettlement.Status.RUINS and status != AlifeSettlement.Status.RUINS:
		return false # Rebuilding ruins requires a dedicated reconstruction project.
	settlement.status = status
	settlement.status_changed_hour = world.simulated_hour
	if status == AlifeSettlement.Status.RAZED:
		settlement.prosperity = maxf(0.0, settlement.prosperity * 0.3)
		settlement.food *= 0.25
		settlement.treasury = 0
		var pending: Dictionary = world.narrative.get("refugee_departures", {})
		pending[settlement.settlement_id] = true
		world.narrative["refugee_departures"] = pending
	elif status == AlifeSettlement.Status.UNGOVERNED:
		settlement.owner_faction = ""
		settlement.garrison = 0
	elif status == AlifeSettlement.Status.RUINS:
		settlement.owner_faction = ""
		settlement.food = 0.0
		settlement.prosperity = 0.0
		settlement.garrison = 0
		settlement.treasury = 0
		for agent: GlobalAgent in world.agents.by_settlement(settlement.settlement_id):
			if agent.alive:
				if world.narrative.get("refugee_travelers", {}).has(agent.agent_id):
					agent.settlement_id = ""
					continue
				AgentLifecycle.mark_dead(world, agent, "settlement_destroyed")
		settlement.population = 0
	world.record_event("settlement_status_changed", settlement.tile, [settlement.owner_faction], {"settlement_id": settlement.settlement_id, "status": status})
	return true

static func tick_recovery(world: AlifeWorldContext, settlement: AlifeSettlement, hours: float) -> void:
	if settlement.status != AlifeSettlement.Status.RAZED or settlement.population <= 0:
		return
	settlement.prosperity = minf(30.0, settlement.prosperity + hours * 0.1)
	if world.simulated_hour - settlement.status_changed_hour >= 72.0 and settlement.food > 0.0:
		transition(world, settlement, AlifeSettlement.Status.NORMAL)
