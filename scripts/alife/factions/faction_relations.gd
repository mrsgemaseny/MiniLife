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
