class_name FactionAI
extends RefCounted

static func evaluate(world: AlifeWorldContext, faction: AlifeFaction) -> void:
	if faction.state in [AlifeFaction.State.COLLAPSED, AlifeFaction.State.SUCCESSION_CRISIS]:
		return
	if world.simulated_hour - faction.last_decision_hour < 6.0:
		return
	faction.last_decision_hour = world.simulated_hour
	for conflict: AlifeConflict in world.conflicts.all():
		if conflict.resolved or not faction.faction_id in [conflict.attacker_id, conflict.defender_id]:
			continue
		if world.simulated_hour - conflict.started_hour < 6.0 or conflict.battles_fought == 0:
			return
		var enemy_id: String = conflict.defender_id if conflict.attacker_id == faction.faction_id else conflict.attacker_id
		var enemy: AlifeFaction = world.factions.find(enemy_id) as AlifeFaction
		if enemy != null and (faction.military_strength < enemy.military_strength * 0.55 or faction.treasury < 0):
			FactionDiplomacy.propose_peace(world, faction.faction_id, enemy_id)
		return
	if faction.treasury <= 0:
		return
	if _annex_unguverned(world, faction):
		return
	var candidate: AlifeFaction = null
	for other: AlifeFaction in world.factions.all():
		if other == faction or other.state == AlifeFaction.State.COLLAPSED:
			continue
		if not FactionRelations.check_casus_belli(world, faction, other).is_empty() and not FactionDiplomacy.has_treaty(world, faction.faction_id, other.faction_id):
			if faction.military_strength > other.military_strength * 1.15 or _has_local_advantage(world, faction, other):
				if candidate == null or other.military_strength < candidate.military_strength:
					candidate = other
	if candidate != null:
		FactionDiplomacy.declare_war(world, faction.faction_id, candidate.faction_id)

static func _has_local_advantage(world: AlifeWorldContext, faction: AlifeFaction, enemy: AlifeFaction) -> bool:
	var available: int = 0
	var holdings: Array = world.settlements.matching("owner_faction", faction.faction_id)
	for holding: AlifeSettlement in holdings:
		available += holding.garrison / 2
	var expedition_strength: float = float(mini(48, available)) * 2.0
	for holding: AlifeSettlement in holdings:
		for target: AlifeSettlement in world.settlements.get_connected(holding.settlement_id):
			if target.owner_faction == enemy.faction_id and target.status == AlifeSettlement.Status.NORMAL:
				var defense: float = float(target.garrison) * 2.0 * (1.0 + float(target.fort_level) * 0.3)
				if expedition_strength > maxf(1.0, defense) * 1.25:
					return true
	return false

static func _annex_unguverned(world: AlifeWorldContext, faction: AlifeFaction) -> bool:
	if faction.treasury < 100:
		return false
	for home: AlifeSettlement in world.settlements.matching("owner_faction", faction.faction_id):
		for target: AlifeSettlement in world.settlements.get_connected(home.settlement_id):
			if target.status != AlifeSettlement.Status.UNGOVERNED or not target.owner_faction.is_empty():
				continue
			if faction.military_strength <= maxf(1.0, float(target.garrison) * 2.0):
				continue
			faction.treasury -= 100
			target.owner_faction = faction.faction_id
			SettlementStatus.transition(world, target, AlifeSettlement.Status.NORMAL)
			for agent: GlobalAgent in world.agents.by_settlement(target.settlement_id):
				if agent.alive:
					agent.faction_id = faction.faction_id
			world.record_event("settlement_captured", target.tile, [faction.faction_id], {"settlement_id": target.settlement_id, "reason": "protectorate"})
			return true
	return false
