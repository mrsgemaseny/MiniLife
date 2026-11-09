class_name FactionSuccession
extends RefCounted

static func leader_died(world: AlifeWorldContext, faction_id: String, agent_id: String) -> bool:
	var faction: AlifeFaction = world.factions.find(faction_id) as AlifeFaction
	if faction == null or faction.state == AlifeFaction.State.COLLAPSED or faction.leader_id != agent_id:
		return false
	faction.leader_id = ""
	faction.state = AlifeFaction.State.SUCCESSION_CRISIS
	faction.succession_started_tick = world.tick_count
	var agent: GlobalAgent = world.agents.find(agent_id) as GlobalAgent
	world.record_event("leader_died", agent.tile if agent != null else Vector2i.ZERO, [faction_id, agent_id])
	return true

static func tick(world: AlifeWorldContext, faction: AlifeFaction) -> void:
	if faction.state != AlifeFaction.State.SUCCESSION_CRISIS or world.tick_count - faction.succession_started_tick < 3:
		return
	var heirs: Array = []
	for id: String in faction.succession_list:
		var heir: GlobalAgent = world.agents.find(id) as GlobalAgent
		if heir != null and heir.alive and heir.faction_id == faction.faction_id and not heirs.has(id):
			heirs.append(id)
	if heirs.is_empty():
		collapse(world, faction)
		return
	var recognized: String = faction.recognized_heir_id
	if heirs.has(recognized) or heirs.size() == 1:
		faction.leader_id = recognized if heirs.has(recognized) else str(heirs[0])
		faction.succession_list.erase(faction.leader_id)
		faction.recognized_heir_id = ""
		faction.authority_modifier = 0.85
		faction.military_strength *= 0.85
		faction.state = AlifeFaction.State.STABLE
		world.record_event("leader_succeeded", _capital_tile(world, faction), [faction.faction_id, faction.leader_id])
	else:
		_split(world, faction, str(heirs[0]), str(heirs[1]))
	FactionDiplomacy.reconcile_states(world)

static func collapse(world: AlifeWorldContext, faction: AlifeFaction) -> void:
	if faction.state == AlifeFaction.State.COLLAPSED:
		return
	faction.state = AlifeFaction.State.COLLAPSED
	faction.leader_id = ""
	for holding: AlifeSettlement in world.settlements.matching("owner_faction", faction.faction_id):
		if holding.status == AlifeSettlement.Status.RUINS:
			continue
		var council: GlobalAgent = null
		for agent: GlobalAgent in world.agents.by_settlement(holding.settlement_id):
			if agent.alive and agent.named and agent.role in ["elder", "noble", "innkeeper", "trader"]:
				council = agent
				break
		if council == null:
			SettlementStatus.transition(world, holding, AlifeSettlement.Status.UNGOVERNED)
			for agent: GlobalAgent in world.agents.by_settlement(holding.settlement_id):
				if agent.alive:
					agent.faction_id = ""
					if agent.role in ["guard", "soldier"]:
						agent.role = "deserter"
		else:
			var independent: AlifeFaction = AlifeFaction.new()
			independent.faction_id = "independent/" + holding.settlement_id
			independent.name = holding.name + " Council"
			independent.ideology = faction.ideology
			independent.capital_id = holding.settlement_id
			independent.leader_id = council.agent_id
			independent.treasury = holding.treasury
			independent.color = faction.color.lightened(0.15)
			independent.last_decision_hour = world.simulated_hour
			world.factions.register(independent)
			holding.owner_faction = independent.faction_id
			for agent: GlobalAgent in world.agents.by_settlement(holding.settlement_id):
				if agent.alive:
					agent.faction_id = independent.faction_id
			world.record_event("settlement_independent", holding.tile, [independent.faction_id], {"settlement_id": holding.settlement_id})
	world.record_event("faction_collapsed", _capital_tile(world, faction), [faction.faction_id])
	FactionDiplomacy.reconcile_states(world)

static func _split(world: AlifeWorldContext, faction: AlifeFaction, heir_id: String, rebel_id: String) -> void:
	faction.leader_id = heir_id
	faction.state = AlifeFaction.State.STABLE
	faction.authority_modifier = 0.85
	faction.succession_list.erase(heir_id)
	faction.succession_list.erase(rebel_id)
	var holdings: Array = world.settlements.matching("owner_faction", faction.faction_id)
	var rebel: AlifeFaction = AlifeFaction.new()
	rebel.faction_id = "%s/rebel/%d" % [faction.faction_id, world.next_event_id]
	rebel.name = faction.name + " Secessionists"
	rebel.ideology = faction.ideology
	rebel.leader_id = rebel_id
	rebel.color = faction.color.darkened(0.25)
	rebel.treasury = maxi(0, faction.treasury / 2)
	faction.treasury -= rebel.treasury
	rebel.last_decision_hour = world.simulated_hour
	var count: int = 0
	var heir_agent: GlobalAgent = world.agents.find(heir_id) as GlobalAgent
	var rebel_agent: GlobalAgent = world.agents.find(rebel_id) as GlobalAgent
	for holding: AlifeSettlement in holdings:
		if holding.settlement_id == faction.capital_id or (heir_agent != null and holding.settlement_id == heir_agent.settlement_id):
			continue
		if (rebel_agent == null or holding.settlement_id != rebel_agent.settlement_id) and count % 2 != 0:
			count += 1
			continue
		count += 1
		holding.owner_faction = rebel.faction_id
		if rebel.capital_id.is_empty():
			rebel.capital_id = holding.settlement_id
		for agent: GlobalAgent in world.agents.by_settlement(holding.settlement_id):
			if agent.alive:
				agent.faction_id = rebel.faction_id
	if rebel.capital_id.is_empty():
		# A one-settlement faction cannot split territory; its rival loses the contest.
		faction.treasury += rebel.treasury
		world.record_event("succession_contested", _capital_tile(world, faction), [faction.faction_id, heir_id, rebel_id])
		return
	world.factions.register(rebel)
	if rebel_agent != null:
		rebel_agent.faction_id = rebel.faction_id
	faction.relations[rebel.faction_id] = -100
	rebel.relations[faction.faction_id] = -100
	faction.casus_belli[rebel.faction_id] = "secession"
	world.record_event("faction_split", _capital_tile(world, faction), [faction.faction_id, rebel.faction_id])
	FactionDiplomacy.declare_war(world, faction.faction_id, rebel.faction_id)

static func _capital_tile(world: AlifeWorldContext, faction: AlifeFaction) -> Vector2i:
	var capital: AlifeSettlement = world.settlements.find(faction.capital_id) as AlifeSettlement
	return capital.tile if capital != null else Vector2i.ZERO
