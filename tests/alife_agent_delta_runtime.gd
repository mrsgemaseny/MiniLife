extends Node

func _ready() -> void:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(12345, 6.0)
	WorldSeedBuilder.populate(world)
	var codec: AlifeAgentSaveDelta = AlifeAgentSaveDelta.new()
	codec.capture(world, Config.TERRAIN_GEOGRAPHY_SIZE)
	var initial: Dictionary = codec.encode(world)
	var baseline_count: int = world.agents.all().size()
	var passed: bool = initial.agent_delta.changed.is_empty() and initial.agent_delta.added.is_empty()
	var agent: GlobalAgent = world.agents.all()[0]
	agent.health = 18.25
	agent.alive = false
	agent.world_position = [67.0, 98.0]
	agent.inventory = {"bread": 2}
	world.agents.remove((world.agents.all()[1] as GlobalAgent).agent_id)
	var new_agent: GlobalAgent = GlobalAgent.new()
	new_agent.agent_id = "delta_test_new_resident"
	world.agents.register(new_agent)
	var full_json: String = JSON.stringify(world.to_dict(), "", true, true)
	var delta_json: String = JSON.stringify(codec.encode(world), "", true, true)
	var payload: Dictionary = JSON.parse_string(delta_json)
	var loader: AlifeAgentSaveDelta = AlifeAgentSaveDelta.new()
	var loaded: AlifeWorldContext = loader.decode(payload, Config.TERRAIN_GEOGRAPHY_SIZE)
	var expected: Dictionary = JSON.parse_string(full_json)
	var actual: Dictionary = JSON.parse_string(JSON.stringify(loaded.to_dict(), "", true, true)) if loaded != null else {}
	for key: String in expected:
		if expected[key] != actual.get(key):
			print("Agent delta round trip mismatch: ", key)
	passed = passed and expected == actual
	passed = passed and delta_json.length() * 2 < full_json.length()
	if loaded != null:
		var reencoded: Dictionary = JSON.parse_string(JSON.stringify(loader.encode(loaded), "", true, true))
		for key: String in payload:
			if payload[key] != reencoded.get(key):
				print("Agent delta re-encode mismatch: ", key)
		passed = passed and reencoded == payload
	payload.agent_delta.changed[agent.agent_id]["agent_id"] = "bad_id"
	passed = passed and loader.decode(payload, Config.TERRAIN_GEOGRAPHY_SIZE) == null
	var legacy: AlifeWorldContext = loader.decode(JSON.parse_string(full_json), Config.TERRAIN_GEOGRAPHY_SIZE)
	var migrated: Dictionary = JSON.parse_string(JSON.stringify(loader.encode(legacy), "", true, true)) if legacy != null else {}
	payload.agent_delta.changed[agent.agent_id].erase("agent_id")
	passed = passed and migrated == payload
	payload["travel_routes"] = {"invalid": {"route": [[-1, 0]], "destination": [0, 0], "position": [0, 0]}}
	passed = passed and loader.decode(payload, Config.TERRAIN_GEOGRAPHY_SIZE) == null
	for index: int in range(600):
		world.record_event("test_event", Vector2i.ZERO, [])
	world.rumor_cursor = 50
	world.compact_events(20)
	passed = passed and world.events.size() == 580 and int(world.events[0].event_id) == 21
	world.rumor_cursor = 600
	world.compact_events(600)
	passed = passed and world.events.size() == AlifeWorldContext.RECENT_EVENT_LIMIT
	passed = passed and int(world.events.back().event_id) == 600 and world.next_event_id == 601
	print("ALIFE_AGENT_DELTA_RESULT: ", "PASS" if passed else "FAIL",
		" agents=", baseline_count, " full_bytes=", full_json.length(), " delta_bytes=", delta_json.length())
	get_tree().quit(0 if passed else 1)
