class_name FactionDiplomacy
extends RefCounted

static func at_war(world: AlifeWorldContext, a_id: String, b_id: String) -> bool:
	for conflict: AlifeConflict in world.conflicts.all():
		if not conflict.resolved and ((conflict.attacker_id == a_id and conflict.defender_id == b_id) or (conflict.attacker_id == b_id and conflict.defender_id == a_id)):
			return true
	return false

static func has_treaty(world: AlifeWorldContext, a_id: String, b_id: String, treaty_type: String = "") -> bool:
	for treaty: AlifeTreaty in world.treaties.all():
		if treaty.expiry_day * 24.0 <= world.simulated_hour:
			continue
		if treaty.factions.has(a_id) and treaty.factions.has(b_id) and (treaty_type.is_empty() or treaty.treaty_type == treaty_type):
			return true
	return false

static func declare_war(world: AlifeWorldContext, a_id: String, b_id: String) -> bool:
	var a: AlifeFaction = world.factions.find(a_id) as AlifeFaction
	var b: AlifeFaction = world.factions.find(b_id) as AlifeFaction
	if a == null or b == null or a == b or a.state == AlifeFaction.State.COLLAPSED or b.state == AlifeFaction.State.COLLAPSED:
		return false
	if at_war(world, a_id, b_id) or has_treaty(world, a_id, b_id):
		return false
	var cause: String = FactionRelations.check_casus_belli(world, a, b)
	if cause.is_empty():
		return false
	var target: AlifeSettlement = null
	for settlement: AlifeSettlement in world.settlements.matching("owner_faction", a_id):
		for candidate: AlifeSettlement in world.settlements.get_connected(settlement.settlement_id):
			if candidate.owner_faction == b_id and candidate.status == AlifeSettlement.Status.NORMAL:
				if target == null or candidate.garrison < target.garrison:
					target = candidate
	if target == null:
		return false
	var conflict: AlifeConflict = AlifeConflict.new()
	conflict.conflict_id = "war_%d_%s_%s" % [world.next_event_id, a_id, b_id]
	conflict.attacker_id = a_id
	conflict.defender_id = b_id
	conflict.casus_belli = cause
	conflict.target_settlement = target.settlement_id
	conflict.started_hour = world.simulated_hour
	world.conflicts.register(conflict)
	a.state = AlifeFaction.State.AT_WAR
	b.state = AlifeFaction.State.AT_WAR
	FactionRelations.apply_relation_delta(world, a_id, b_id, -20)
	world.record_event("war_declared", target.tile, [a_id, b_id], {"casus_belli": cause, "settlement_id": target.settlement_id})
	return true

static func sign_treaty(world: AlifeWorldContext, a_id: String, b_id: String, treaty_type: String, duration_days: int) -> bool:
	if not treaty_type in ["peace", "trade", "alliance", "non_aggression"]:
		return false
	if a_id == b_id or world.factions.find(a_id) == null or world.factions.find(b_id) == null or duration_days <= 0:
		return false
	if has_treaty(world, a_id, b_id, treaty_type):
		return false
	var treaty: AlifeTreaty = AlifeTreaty.new()
	treaty.treaty_id = "treaty_%d_%s_%s" % [world.next_event_id, a_id, b_id]
	treaty.factions = [a_id, b_id]
	treaty.treaty_type = treaty_type
	treaty.expiry_day = int(floor(world.simulated_hour / 24.0)) + duration_days + 1
	world.treaties.register(treaty)
	world.record_event("treaty_signed", Vector2i.ZERO, [a_id, b_id], {"treaty_id": treaty.treaty_id, "type": treaty_type})
	return true

static func propose_peace(world: AlifeWorldContext, a_id: String, b_id: String) -> bool:
	if not at_war(world, a_id, b_id):
		return false
	for conflict: AlifeConflict in world.conflicts.all():
		if (conflict.attacker_id == a_id and conflict.defender_id == b_id) or (conflict.attacker_id == b_id and conflict.defender_id == a_id):
			conflict.resolved = true
	for id: String in [a_id, b_id]:
		var faction: AlifeFaction = world.factions.find(id) as AlifeFaction
		if faction != null and faction.state == AlifeFaction.State.AT_WAR:
			var other_war: bool = false
			for conflict: AlifeConflict in world.conflicts.all():
				if not conflict.resolved and id in [conflict.attacker_id, conflict.defender_id]:
					other_war = true
			if not other_war:
				faction.state = AlifeFaction.State.STABLE
	FactionRelations.apply_relation_delta(world, a_id, b_id, 15)
	sign_treaty(world, a_id, b_id, "peace", 3)
	world.record_event("peace_declared", Vector2i.ZERO, [a_id, b_id])
	return true

static func break_treaty(world: AlifeWorldContext, treaty_id: String, violator_id: String) -> bool:
	var treaty: AlifeTreaty = world.treaties.find(treaty_id) as AlifeTreaty
	if treaty == null or not treaty.factions.has(violator_id):
		return false
	for faction_id: String in treaty.factions:
		if faction_id != violator_id:
			FactionRelations.apply_relation_delta(world, violator_id, faction_id, -30)
			var faction: AlifeFaction = world.factions.find(faction_id) as AlifeFaction
			faction.casus_belli[violator_id] = "broken_treaty"
	world.treaties.remove(treaty_id)
	world.record_event("treaty_broken", Vector2i.ZERO, treaty.factions, {"violator": violator_id})
	return true

static func reconcile_states(world: AlifeWorldContext) -> void:
	for conflict: AlifeConflict in world.conflicts.all():
		var a: AlifeFaction = world.factions.find(conflict.attacker_id) as AlifeFaction
		var b: AlifeFaction = world.factions.find(conflict.defender_id) as AlifeFaction
		if a == null or b == null or a.state == AlifeFaction.State.COLLAPSED or b.state == AlifeFaction.State.COLLAPSED:
			conflict.resolved = true
			ConflictManager.release_operation(world, conflict)
	for faction: AlifeFaction in world.factions.all():
		if faction.state in [AlifeFaction.State.STABLE, AlifeFaction.State.AT_WAR]:
			faction.state = AlifeFaction.State.AT_WAR if not ConflictManager.get_for_faction(world, faction.faction_id).is_empty() else AlifeFaction.State.STABLE
