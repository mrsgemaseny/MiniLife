extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _check_agent_indices() -> void:
	var registry: AgentRegistry = AgentRegistry.new()
	var first: GlobalAgent = GlobalAgent.from_dict({"agent_id": "a", "settlement_id": "home", "tile": [15, 15]})
	var second: GlobalAgent = GlobalAgent.from_dict({"agent_id": "b", "settlement_id": "home", "tile": [16, 16]})
	registry.register(second)
	registry.register(first)
	check(registry.by_settlement("home") == [first, second], "Indexed settlement lookup preserves ID order")
	check(registry.global_within(first.tile, 1) == [first, second], "Spatial query includes diagonal chunk boundary")
	registry.materialized[first.agent_id] = true
	second.alive = false
	check(registry.global_within(first.tile, 1).is_empty(), "Spatial query excludes materialized and dead agents")
	registry.materialized.clear()
	second.alive = true
	first.restore({"settlement_id": "new_home", "tile": [-1, -1]})
	check(registry.by_settlement("home") == [second] and registry.by_settlement("new_home") == [first],
		"Changing residence updates both settlement groups")
	check(registry.global_within(Vector2i.ZERO, 1) == [first] and registry.global_within(second.tile, 1) == [second],
		"Changing tile updates both chunks, including signed coordinates")
	var saved: Array = registry.to_array()
	check(not registry.restore(saved + [saved[0]]) and registry.by_settlement("new_home") == [first],
		"Rejected restore preserves the existing indices")
	check(registry.restore(saved), "Registry restores indexed records")
	var restored: GlobalAgent = registry.find(first.agent_id) as GlobalAgent
	first.restore({"settlement_id": "stale", "tile": [32, 32]})
	check(registry.by_settlement("new_home") == [restored] and registry.global_within(Vector2i.ZERO, 1) == [restored],
		"Old objects cannot overwrite indices of restored records")
	registry.remove(restored.agent_id)
	restored.settlement_id = "stale"
	restored.tile = Vector2i(32, 32)
	check(registry.by_settlement("new_home").is_empty() and registry.by_settlement("stale").is_empty()
		and registry.global_within(Vector2i.ZERO, 1).is_empty() and registry.global_within(restored.tile, 0).is_empty(),
		"Removed objects cannot repopulate the indices")
	registry.clear()
	check(registry.by_settlement("home").is_empty() and registry.global_within(second.tile, 0).is_empty(),
		"Clearing the registry clears both indices")

func _check_local_handoffs_during_tick() -> void:
	var context: AlifeWorldContext = AlifeWorldContext.new()
	context.seed_world(42, 10.0)
	for index: int in range(21):
		var agent: GlobalAgent = GlobalAgent.from_dict({"agent_id": "resident_%02d" % index, "role": "farmer"})
		context.agents.register(agent)
	var old_local: GlobalAgent = context.agents.find("resident_16") as GlobalAgent
	var new_local: GlobalAgent = context.agents.find("resident_17") as GlobalAgent
	var removed: GlobalAgent = context.agents.find("resident_18") as GlobalAgent
	var briefly_local: GlobalAgent = context.agents.find("resident_19") as GlobalAgent
	var last: GlobalAgent = context.agents.find("resident_20") as GlobalAgent
	context.agents.materialized[old_local.agent_id] = true
	var tick: AgentTick = AgentTick.new()
	tick.begin(context, 0.5)
	tick.advance(context, Time.get_ticks_usec())
	context.agents.materialized.erase(old_local.agent_id)
	context.agents.materialized[new_local.agent_id] = true
	tick.mark_local(briefly_local.agent_id)
	context.agents.remove(removed.agent_id)
	var replacement: GlobalAgent = GlobalAgent.from_dict({"agent_id": removed.agent_id, "role": "farmer"})
	context.agents.register(replacement)
	tick.advance(context)
	check(old_local.goal_progress == 0.0 and new_local.goal_progress == 0.0 and briefly_local.goal_progress == 0.0,
		"A resident using local simulation before its slice avoids an abstract update")
	check(removed.goal_progress == 0.0 and replacement.goal_progress == 0.0 and last.goal_progress == 0.0625,
		"An identity replacement waits until the next pass while remaining agents advance")

func _ready() -> void:
	_check_agent_indices()
	_check_local_handoffs_during_tick()
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(12345, 10.0)
	check(world.factions.all().size() == DataRegistry.get_rows("factions").size(), "Faction seed count")
	var settlement: AlifeSettlement = AlifeSettlement.new()
	settlement.settlement_id = "test_village"
	settlement.tile = Vector2i(12, 17)
	settlement.population = 100
	settlement.owner_faction = "village_folk"
	check(world.settlements.register(settlement), "Register settlement")
	check(not world.settlements.register(settlement), "Reject duplicate ID")
	var agent: GlobalAgent = GlobalAgent.new()
	agent.agent_id = "test_guard"
	agent.role = "guard"
	agent.settlement_id = settlement.settlement_id
	agent.faction_id = settlement.owner_faction
	agent.grudges = [{"reason": "commander_killed"}]
	world.agents.register(agent)
	world.record_event("test", settlement.tile, [agent.agent_id])
	world.rng.randf()
	var json: String = JSON.stringify(world.to_dict())
	var restored: AlifeWorldContext = AlifeWorldContext.from_dict(JSON.parse_string(json))
	check(restored != null, "JSON round trip")
	if restored != null:
		check((restored.settlements.find("test_village") as AlifeSettlement).tile == settlement.tile, "Vector2i round trip")
		check((restored.agents.find("test_guard") as GlobalAgent).grudges == agent.grudges, "Permanent memory round trip")
		check(restored.rng.randi() == world.rng.randi(), "RNG continuation after JSON round trip")
		var restored_faction: AlifeFaction = restored.factions.find("merchants") as AlifeFaction
		var original_faction: AlifeFaction = world.factions.find("merchants") as AlifeFaction
		check(restored_faction.treasury == original_faction.treasury and restored_faction.color.to_html() == original_faction.color.to_html(), "Faction state round trip")
		check(int(restored_faction.relations.get("bandits", 0)) == -60, "Diplomatic relation round trip")
	var before: float = settlement.food
	EconomyTick.new().tick(world, 1.0)
	check(settlement.food > before, "Agricultural production exceeds consumption")
	check(AgentGoalEvaluator.evaluate(agent, world) == "patrol_settlement", "Guard ambient goal")
	agent.health = 20.0
	check(AgentGoalEvaluator.evaluate(agent, world) == "retreat_to_safety", "Survival overrides duty")
	var damaged: Dictionary = world.to_dict()
	damaged["agents"].append(damaged["agents"][0])
	check(AlifeWorldContext.from_dict(damaged) == null, "Reject duplicate save IDs transactionally")
	var inventory: InventoryComponent = InventoryComponent.new()
	inventory.gold = 3
	inventory.silver = 40
	check(CurrencyPolicy.exchange(inventory, true, 2), "Silver to gold exchange")
	check(inventory.gold == 5 and inventory.silver == 0 and inventory.count_of("gold_coin") == 0, "No double currency payout")
	check(CurrencyPolicy.exchange(inventory, false, 2), "Gold to silver exchange")
	check(inventory.gold == 3 and inventory.silver == 40, "Round trip cannot create currency")
	check(not CurrencyPolicy.exchange(inventory, true, 3), "Insufficient funds rejected")
	check(inventory.gold == 3 and inventory.silver == 40, "Rejected exchange leaves balance intact")
	WorldSimulation._on_game_started(12345, "alife_test", true)
	WorldSimulation.world.settlements.register(settlement)
	var ticks_before: int = WorldSimulation.world.tick_count
	var completed: Array[int] = []
	var on_completed: Callable = func() -> void: completed.append(WorldSimulation.world.tick_count)
	SignalBus.world_tick_completed.connect(on_completed)
	WorldSimulation._begin_global_tick(0.5)
	check(WorldSimulation.agent_tick.has_pending() and WorldSimulation.world.tick_count == ticks_before,
		"Strategic step can pause before finishing the abstract agents")
	WorldSimulation.agent_tick.advance(WorldSimulation.world, Time.get_ticks_usec())
	check(WorldSimulation.agent_tick.has_pending(), "Agent batch yields with work still queued")
	var bundle: Dictionary = {"world": {
		"existing_field": 42,
		"generator_version": GameManager.get_world_generator_version(),
	}}
	WorldSimulation._on_save_requested(bundle)
	check(not WorldSimulation.agent_tick.has_pending() and WorldSimulation.world.tick_count == ticks_before + 1,
		"Saving completes the pending strategic step exactly once")
	check(completed == [ticks_before + 1], "The staged tick publishes only after completion")
	SignalBus.world_tick_completed.disconnect(on_completed)
	check(bundle.world.existing_field == 42, "Save preserves other systems' world data")
	var saved_ticks: int = WorldSimulation.world.tick_count
	WorldSimulation._on_save_loaded(JSON.parse_string(JSON.stringify(bundle)))
	WorldSimulation._on_game_started(12345, "alife_test", false)
	check(WorldSimulation._initialized and WorldSimulation.last_load_error.is_empty(), "A supported snapshot restores the simulation")
	check(WorldSimulation.world.tick_count == saved_ticks, "Loaded start preserves restored simulation")
	check(WorldSimulation.world.settlements.find("test_village") != null, "Loaded start preserves settlements")
	WorldSimulation._on_save_loaded({"world": {}})
	WorldSimulation._on_game_started(54321, "legacy_test", false)
	check(WorldSimulation.world.world_seed == 54321 and WorldSimulation.world.tick_count == 0, "Legacy save initializes clean world")
	WorldSimulation._on_save_loaded({"world": {"alife": {"schema_version": 999, "future_state": "keep"}}})
	WorldSimulation._on_game_started(54321, "future_test", false)
	check(not WorldSimulation._initialized and not WorldSimulation.last_load_error.is_empty(), "Unsupported save does not silently seed a different world")
	var future_bundle: Dictionary = {"world": {}}
	WorldSimulation._on_save_requested(future_bundle)
	check(future_bundle.world.alife.future_state == "keep", "Unsupported payload survives subsequent save")
	var bad_bundle: Dictionary = JSON.parse_string(JSON.stringify(bundle))
	var cities: Array = bad_bundle.world.alife.settlements
	var start_id: String = cities[0]["settlement_id"]
	var destination_id: String = cities[1]["settlement_id"]
	bad_bundle.world.alife.routes.append({
		"route_id": "broken_caravan", "from_id": start_id, "to_id": destination_id,
		"at_id": start_id, "destination_id": destination_id, "active": true,
		"merchant_id": "missing_merchant",
	})
	WorldSimulation._on_save_loaded(bad_bundle)
	check(not WorldSimulation._initialized and WorldSimulation.last_load_error.contains("broken_caravan"),
		"Save rejects an active caravan referencing a missing merchant")
	var preserved: Dictionary = {"world": {}}
	WorldSimulation._on_save_requested(preserved)
	check(preserved.world.alife == bad_bundle.world.alife, "Invalid references preserve the original payload for recovery")
	print("ALIFE TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
