class_name AlifeWorldContext
extends RefCounted

const RECENT_EVENT_LIMIT: int = 512

var world_seed: int = 0
var simulated_hour: float = 0.0
var tick_count: int = 0
var next_event_id: int = 1
var factions: FactionRegistry = FactionRegistry.new()
var settlements: SettlementRegistry = SettlementRegistry.new()
var agents: AgentRegistry = AgentRegistry.new()
var routes: AlifeRegistry = AlifeRegistry.new("route_id", CaravanRoute.from_dict)
var conflicts: AlifeRegistry = AlifeRegistry.new("conflict_id", AlifeConflict.from_dict)
var treaties: AlifeRegistry = AlifeRegistry.new("treaty_id", AlifeTreaty.from_dict)
var events: Array = []
var rumors: Array = []
var rumor_cursor: int = 0
var narrative: Dictionary = {}
var reputation: Dictionary = {}
var contracts: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var travel: AlifeTravel = AlifeTravel.new()

func seed_world(seed_value: int, initial_hour: float) -> void:
	world_seed = seed_value
	simulated_hour = initial_hour
	rng.seed = seed_value
	var index: int = 0
	for row: Dictionary in DataRegistry.get_rows("factions"):
		var faction: AlifeFaction = AlifeFaction.new()
		faction.faction_id = str(row["id"])
		faction.name = str(row.get("name", faction.faction_id))
		faction.ideology = str(row.get("ideology", "merchant"))
		faction.treasury = int(row.get("start_treasury", 1500))
		faction.military_strength = float(row.get("military_strength", 0.4))
		faction.last_decision_hour = initial_hour
		faction.color = Color.from_hsv(float(index) * 0.61803398875, 0.55, 0.85)
		for ally: String in row.get("allied_factions", []):
			faction.relations[ally] = 40
		for enemy: String in row.get("enemy_factions", []):
			faction.relations[enemy] = -60
		factions.register(faction)
		index += 1

func record_event(event_type: String, tile: Vector2i, participants: Array, details: Dictionary = {}) -> AlifeWorldEvent:
	var event: AlifeWorldEvent = AlifeWorldEvent.new()
	event.event_id = next_event_id
	next_event_id += 1
	event.event_type = event_type
	event.location = tile
	event.participants = participants.duplicate()
	event.timestamp = simulated_hour
	event.data = details.duplicate(true)
	events.append(event.to_dict())
	return event

func compact_events(published_event_id: int) -> void:
	var cutoff: int = mini(published_event_id, rumor_cursor)
	var removable: int = events.size() - RECENT_EVENT_LIMIT
	var count: int = 0
	while count < removable and int(events[count].get("event_id", 0)) <= cutoff:
		count += 1
	if count > 0:
		events = events.slice(count)

func to_dict() -> Dictionary:
	return {
		"schema_version": 1, "world_seed": world_seed, "simulated_hour": simulated_hour,
		"tick_count": tick_count, "next_event_id": next_event_id,
		"rng_state": str(rng.state), "factions": factions.to_array(),
		"settlements": settlements.to_array(), "agents": agents.to_array(),
		"routes": routes.to_array(), "conflicts": conflicts.to_array(),
		"treaties": treaties.to_array(), "events": events.duplicate(true),
		"rumors": rumors.duplicate(true), "rumor_cursor": rumor_cursor, "narrative": narrative.duplicate(true),
		"reputation": reputation.duplicate(true), "contracts": contracts.duplicate(true),
		"travel_routes": travel.saved_routes()
	}

static func from_dict(data: Dictionary) -> AlifeWorldContext:
	if int(data.get("schema_version", 0)) != 1:
		return null
	for field: String in ["events", "rumors"]:
		if not data.get(field, []) is Array:
			return null
		for row: Variant in data.get(field, []):
			if not row is Dictionary:
				return null
	for field: String in ["narrative", "reputation", "contracts", "travel_routes"]:
		if not data.get(field, {}) is Dictionary:
			return null
	if not AlifeTravel.valid_saved_routes(data.get("travel_routes", {})):
		return null
	var result: AlifeWorldContext = AlifeWorldContext.new()
	var registries: Dictionary = {
		"factions": result.factions, "settlements": result.settlements,
		"agents": result.agents, "routes": result.routes,
		"conflicts": result.conflicts, "treaties": result.treaties
	}
	for key: String in registries:
		if not data.get(key, []) is Array:
			return null
		if not (registries[key] as AlifeRegistry).restore(data.get(key, [])):
			return null
	result.world_seed = int(data.get("world_seed", 0))
	result.simulated_hour = float(data.get("simulated_hour", 0.0))
	result.tick_count = int(data.get("tick_count", 0))
	result.next_event_id = int(data.get("next_event_id", 1))
	result.rng.seed = result.world_seed
	result.rng.state = str(data.get("rng_state", "0")).to_int()
	result.events = (data.get("events", []) as Array).duplicate(true)
	result.rumors = (data.get("rumors", []) as Array).duplicate(true)
	result.rumor_cursor = int(data.get("rumor_cursor", 0))
	result.narrative = (data.get("narrative", {}) as Dictionary).duplicate(true)
	result.reputation = (data.get("reputation", {}) as Dictionary).duplicate(true)
	result.contracts = (data.get("contracts", {}) as Dictionary).duplicate(true)
	result.travel.restore_routes(result.world_seed, data.get("travel_routes", {}) as Dictionary)
	return result
