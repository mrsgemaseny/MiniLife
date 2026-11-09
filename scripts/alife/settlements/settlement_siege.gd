class_name SettlementSiege
extends RefCounted

static func begin_siege(world: AlifeWorldContext, conflict: AlifeConflict) -> void:
	var settlement: AlifeSettlement = world.settlements.find(conflict.target_settlement) as AlifeSettlement
	if settlement == null:
		return
	conflict.phase = "siege"
	conflict.phase_started_hour = world.simulated_hour
	conflict.assault_hour = world.simulated_hour + 24.0
	conflict.siege_progress = 0.0
	for agent: GlobalAgent in AgentLifecycle.living(world, conflict.attacker_agents):
		agent.current_goal = "assault_settlement"
	world.record_event("siege_started", settlement.tile, [conflict.attacker_id, conflict.defender_id], {"settlement_id": settlement.settlement_id, "deadline_hour": conflict.assault_hour})

static func resolve_siege(world: AlifeWorldContext, conflict: AlifeConflict, outcome: Dictionary) -> void:
	var settlement: AlifeSettlement = world.settlements.find(conflict.target_settlement) as AlifeSettlement
	if settlement == null:
		return
	conflict.battles_fought += 1
	conflict.last_winner = str(outcome["winner"])
	conflict.siege_progress = 1.0
	world.record_event("battle_resolved", settlement.tile, [conflict.attacker_id, conflict.defender_id], outcome.merged({"settlement_id": settlement.settlement_id}))
	if conflict.last_winner == conflict.attacker_id:
		var attacker: AlifeFaction = world.factions.find(conflict.attacker_id) as AlifeFaction
		var defender: AlifeFaction = world.factions.find(conflict.defender_id) as AlifeFaction
		if attacker == null or defender == null:
			return
		if attacker.faction_id == "bandits":
			attacker.treasury += settlement.treasury
			SettlementStatus.transition(world, settlement, AlifeSettlement.Status.RAZED)
			world.record_event("settlement_razed", settlement.tile, [attacker.faction_id], {"settlement_id": settlement.settlement_id})
		else:
			settlement.owner_faction = attacker.faction_id
			settlement.prosperity *= 0.8
			settlement.fort_level = maxi(0, settlement.fort_level - 1)
			for agent: GlobalAgent in world.agents.by_settlement(settlement.settlement_id):
				if agent.alive and agent.role in ["guard", "soldier"]:
					agent.morale = 0.15
					agent.current_goal = "retreat_to_safety"
				elif agent.alive:
					agent.faction_id = attacker.faction_id
			settlement.garrison = 0
			world.record_event("settlement_captured", settlement.tile, [attacker.faction_id, defender.faction_id], {"settlement_id": settlement.settlement_id})
			if defender.capital_id == settlement.settlement_id:
				# Capturing the capital transfers remaining holdings and ends the war.
				for holding: AlifeSettlement in world.settlements.matching("owner_faction", defender.faction_id):
					holding.owner_faction = attacker.faction_id
					for resident: GlobalAgent in world.agents.by_settlement(holding.settlement_id):
						if resident.alive:
							resident.faction_id = attacker.faction_id
				defender.state = AlifeFaction.State.COLLAPSED
				world.record_event("faction_collapsed", settlement.tile, [defender.faction_id], {"absorbed_by": attacker.faction_id})
				conflict.resolved = true
	ConflictManager.release_operation(world, conflict)
	if not conflict.resolved:
		conflict.phase = "recovering"
		conflict.phase_started_hour = world.simulated_hour
