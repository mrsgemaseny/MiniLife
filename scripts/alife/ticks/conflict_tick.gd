class_name ConflictTick
extends RefCounted

func tick(world: AlifeWorldContext, hours: float) -> void:
	for settlement: AlifeSettlement in world.settlements.all():
		SettlementStatus.tick_recovery(world, settlement, hours)
	for conflict: AlifeConflict in world.conflicts.all():
		if conflict.resolved:
			if not conflict.attacker_agents.is_empty():
				ConflictManager.release_operation(world, conflict)
			continue
		var target: AlifeSettlement = world.settlements.find(conflict.target_settlement) as AlifeSettlement
		if target == null:
			conflict.resolved = true
			continue
		match conflict.phase:
			"planning":
				if not ConflictManager.prepare_operation(world, conflict):
					FactionDiplomacy.propose_peace(world, conflict.attacker_id, conflict.defender_id)
			"marching":
				var forces: Array = AgentLifecycle.living(world, conflict.attacker_agents)
				var arrived: int = 0
				for agent: GlobalAgent in forces:
					if Config.tile_distance(agent.tile, target.tile) <= 8.0:
						arrived += 1
				if not forces.is_empty() and arrived >= int(ceil(float(forces.size()) * 0.75)):
					SettlementSiege.begin_siege(world, conflict)
				elif world.simulated_hour - conflict.phase_started_hour > 72.0 or forces.is_empty():
					ConflictManager.release_operation(world, conflict)
					FactionDiplomacy.propose_peace(world, conflict.attacker_id, conflict.defender_id)
			"siege":
				conflict.siege_progress = clampf(1.0 - (conflict.assault_hour - world.simulated_hour) / 24.0, 0.0, 1.0)
				if world.simulated_hour < conflict.assault_hour:
					continue
				if ConflictManager.has_local_participants(world, conflict):
					var attackers: Array = AgentLifecycle.living(world, conflict.attacker_agents)
					var defenders: Array = AgentLifecycle.living(world, conflict.defender_agents)
					if attackers.is_empty() or defenders.is_empty():
						SettlementSiege.resolve_siege(world, conflict, {"winner": conflict.defender_id if attackers.is_empty() else conflict.attacker_id, "local": true})
				else:
					SettlementSiege.resolve_siege(world, conflict, ConflictResolver.resolve_battle(world, conflict, target))
			"recovering":
				if world.simulated_hour - conflict.phase_started_hour < 24.0:
					continue
				var next: String = ConflictManager.next_target(world, conflict)
				if next.is_empty():
					FactionDiplomacy.propose_peace(world, conflict.attacker_id, conflict.defender_id)
				else:
					conflict.target_settlement = next
					conflict.phase = "planning"
	FactionDiplomacy.reconcile_states(world)
