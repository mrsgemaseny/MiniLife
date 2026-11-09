extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(42, 0.0)
	for index: int in range(5):
		var settlement: AlifeSettlement = AlifeSettlement.new()
		settlement.settlement_id = str(index)
		settlement.name = "Town " + str(index)
		settlement.tile = Vector2i(index * 16, 0)
		if index > 0:
			settlement.connections.append(str(index - 1))
		if index < 4:
			settlement.connections.append(str(index + 1))
		world.settlements.register(settlement)
	world.record_event("war_declared", Vector2i.ZERO, ["merchants", "bandits"], {"settlement_id": "0"})
	var tick: RumorTick = RumorTick.new()
	tick.tick(world)
	check(world.rumors.size() == 1, "Public event creates one rumor")
	check(BulletinBoard.get_rumors_at(world, "0").size() == 1, "Origin knows event")
	check(BulletinBoard.get_rumors_at(world, "1").is_empty(), "Rumor does not travel instantly")
	var original: String = str(world.rumors[0]["content"])
	world.simulated_hour = 2.0
	tick.tick(world)
	check(BulletinBoard.get_rumors_at(world, "1").size() == 1, "First neighbor receives rumor")
	check(BulletinBoard.get_rumors_at(world, "2").is_empty(), "Same tick cannot traverse two edges")
	world.simulated_hour = 4.0
	tick.tick(world)
	check(BulletinBoard.get_rumors_at(world, "2").size() == 1, "Forward from current carriers, not only origin")
	check(BulletinBoard.get_rumors_at(world, "3").is_empty(), "Second hop retains delay")
	var restored: AlifeWorldContext = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(restored != null, "Rumor state is serializable")
	world = restored
	tick.tick(world)
	check(world.rumors.size() == 1, "Load does not recreate processed rumors")
	world.simulated_hour = 6.0
	tick.tick(world)
	world.simulated_hour = 8.0
	tick.tick(world)
	var far: Array[Dictionary] = BulletinBoard.get_rumors_at(world, "4")
	check(far.size() == 1 and int(far[0]["distortion"]) == 3, "Distortion capped after fourth hop")
	check(str(world.rumors[0]["content"]) == original, "Remote distortion does not corrupt original report")
	check(str(BulletinBoard.get_rumors_at(world, "0")[0]["content"]) == original, "Origin keeps accurate local version")
	check(int(BulletinBoard.get_rumors_at(world, "1")[0]["distortion"]) == 1, "Each settlement retains its own version")
	world.record_event("agent_died", Vector2i.ZERO, ["anonymous_agent"])
	tick.tick(world)
	check(world.rumors.size() == 1, "Unwitnessed death does not create omniscient gossip")
	check(BulletinBoard.get_rumors_at(world, "missing").is_empty(), "Unknown settlement has no rumors")
	check(BulletinBoard.get_rumors_at(world, "0", 0).is_empty(), "Zero limit respected")
	world.simulated_hour = 24.0 * 15.0
	tick.tick(world)
	check(world.rumors.is_empty(), "Old rumors expire")
	tick.tick(world)
	check(world.rumors.is_empty(), "Expired rumor is not regenerated from history")
	world.record_event("killing_witnessed", Vector2i.ZERO, ["player"], {"settlement_id": "0", "witnesses": []})
	tick.tick(world)
	check(world.rumors.is_empty(), "A killing report requires at least one direct witness")
	world.record_event("killing_witnessed", Vector2i.ZERO, ["player"], {"settlement_id": "0", "witnesses": ["resident"]})
	tick.tick(world)
	check(BulletinBoard.get_rumors_at(world, "0").size() == 1 and BulletinBoard.get_rumors_at(world, "1").is_empty(),
		"Witness testimony starts locally")
	world.simulated_hour += 2.0
	tick.tick(world)
	check(BulletinBoard.get_rumors_at(world, "1").size() == 1, "Witness testimony travels through the rumor network")
	var validator = preload("res://scripts/alife/save_reference_validator.gd")
	check(validator.validate(world).is_empty(), "Valid witness history can load")
	var original_events: Array = world.events.duplicate(true)
	world.events.clear()
	check(validator.validate(world).is_empty(), "Rumors may retain sources outside compacted history")
	world.events = original_events
	world.events.append(world.events.back().duplicate(true))
	check(validator.validate(world).contains("duplicate event"), "Duplicate chronicle IDs are rejected")
	world.events.pop_back()
	world.rumors[0]["received_at"].erase("1")
	check(validator.validate(world).contains("inconsistent carriers"), "Rumor with missing reception is rejected")
	print("ALIFE RUMOR TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
