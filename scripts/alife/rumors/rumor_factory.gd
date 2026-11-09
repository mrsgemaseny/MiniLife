class_name RumorFactory
extends RefCounted

const TEMPLATES: Dictionary = {
	"war_declared": "War has broken out near %s.",
	"peace_declared": "A peace agreement has been announced at %s.",
	"treaty_signed": "A new treaty is being discussed in %s.",
	"treaty_broken": "A treaty has been broken near %s.",
	"settlement_captured": "%s has changed hands.",
	"settlement_razed": "%s has been razed.",
	"siege_started": "%s is under siege.",
	"battle_resolved": "A battle has ended near %s.",
	"killing_witnessed": "A witness near %s says the traveler killed a resident.",
	"refugees_departed": "Displaced families are leaving %s.",
	"refugee_arrived": "Displaced travelers have reached %s.",
	"caravan_raided": "A caravan was raided near %s.",
	"caravan_attacked": "Travelers report an attack on caravan supplies near %s.",
	"caravan_arrived": "A trading caravan has reached %s.",
	"leader_died": "News of a ruler's death has reached %s.",
	"faction_collapsed": "The old authorities have fallen near %s.",
	"famine_started": "Food is running short in %s.",
	"famine_ended": "Food supplies have recovered in %s."
}

static func from_event(world: AlifeWorldContext, event: AlifeWorldEvent) -> RumorEntry:
	if not TEMPLATES.has(event.event_type) or world.settlements.all().is_empty():
		return null
	if event.event_type == "killing_witnessed" and event.data.get("witnesses", []).is_empty():
		return null
	var origin: AlifeSettlement = world.settlements.find(str(event.data.get("settlement_id", ""))) as AlifeSettlement
	if origin == null:
		var distance: float = INF
		for settlement: AlifeSettlement in world.settlements.all():
			var candidate: float = Vector2(settlement.tile).distance_squared_to(Vector2(event.location))
			if candidate < distance:
				distance = candidate
				origin = settlement
	var rumor: RumorEntry = RumorEntry.new()
	rumor.rumor_id = event.event_id
	rumor.event_id = event.event_id
	rumor.event_type = event.event_type
	rumor.content = str(TEMPLATES[event.event_type]) % origin.name
	rumor.origin_tile = origin.tile
	rumor.created_hour = event.timestamp
	rumor.known_by = [origin.settlement_id]
	rumor.received_at[origin.settlement_id] = {"hour": world.simulated_hour, "hops": 0, "content": rumor.content, "distortion": 0}
	return rumor
