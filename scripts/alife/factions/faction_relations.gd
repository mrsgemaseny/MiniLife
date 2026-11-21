class_name FactionRelations
extends RefCounted

static func get_stance(a: AlifeFaction, b: AlifeFaction) -> String:
	var value: int = int(a.relations.get(b.faction_id, 0))
	if value <= -50:
		return "hostile"
	if value >= 50:
		return "allied"
	return "neutral"

static func apply_relation_delta(world: AlifeWorldContext, a_id: String, b_id: String, delta: int) -> bool:
	var a: AlifeFaction = world.factions.find(a_id) as AlifeFaction
	var b: AlifeFaction = world.factions.find(b_id) as AlifeFaction
	if a == null or b == null or a == b:
		return false
	a.relations[b_id] = clampi(int(a.relations.get(b_id, 0)) + delta, -100, 100)
	b.relations[a_id] = clampi(int(b.relations.get(a_id, 0)) + delta, -100, 100)
	return true

static func apply_event(world: AlifeWorldContext, event_type: String, participants: Array, details: Dictionary) -> bool:
	var source_id: String = ""
	var target_id: String = ""
	var delta: int = 0
	match event_type:
		"caravan_arrived":
			var home: AlifeSettlement = world.settlements.find(str(details.get("home_id", ""))) as AlifeSettlement
			var destination: AlifeSettlement = world.settlements.find(str(details.get("settlement_id", ""))) as AlifeSettlement
			if home == null or destination == null:
				return false
			source_id = home.owner_faction
			target_id = destination.owner_faction
			delta = 3
		"caravan_raided":
			if str(details.get("reason", "")) != "bandits":
				return false
			source_id = "bandits"
			if participants.is_empty():
				return false
			target_id = str(participants[0])
			delta = -12
		"agent_died":
			if participants.is_empty():
				return false
			var victim: GlobalAgent = world.agents.find(str(participants[0])) as GlobalAgent
			var killer: GlobalAgent = world.agents.find(str(details.get("killer", ""))) as GlobalAgent
			if victim == null or killer == null:
				return false
			var victim_faction: AlifeFaction = world.factions.find(victim.faction_id) as AlifeFaction
			if victim_faction == null or victim_faction.leader_id != victim.agent_id:
				return false
			source_id = killer.faction_id
			target_id = victim.faction_id
			delta = -30
		_:
			return false
	if source_id.is_empty() or target_id.is_empty() or source_id == target_id:
		return false
	if not apply_relation_delta(world, source_id, target_id, delta):
		return false
	var source: AlifeFaction = world.factions.find(source_id) as AlifeFaction
	var target: AlifeFaction = world.factions.find(target_id) as AlifeFaction
	SignalBus.political_relations_changed.emit(source_id, target_id, int(source.relations[target_id]), int(target.relations[source_id]), event_type)
	return true

static func are_neighbors(world: AlifeWorldContext, a_id: String, b_id: String) -> bool:
	for settlement: AlifeSettlement in world.settlements.matching("owner_faction", a_id):
		for connected: AlifeSettlement in world.settlements.get_connected(settlement.settlement_id):
			if connected.owner_faction == b_id:
				return true
	return false

static func check_casus_belli(world: AlifeWorldContext, a: AlifeFaction, b: AlifeFaction) -> String:
	if a.casus_belli.has(b.faction_id):
		return str(a.casus_belli[b.faction_id])
	if get_stance(a, b) == "hostile" and are_neighbors(world, a.faction_id, b.faction_id):
		return "border_dispute"
	return ""
