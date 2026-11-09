extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
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
	WorldSimulation._run_global_tick(0.5, true)
	var bundle: Dictionary = {"world": {"existing_field": 42}}
	WorldSimulation._on_save_requested(bundle)
	check(bundle.world.existing_field == 42, "Save preserves other systems' world data")
	var saved_ticks: int = WorldSimulation.world.tick_count
	WorldSimulation._on_save_loaded(JSON.parse_string(JSON.stringify(bundle)))
	WorldSimulation._on_game_started(12345, "alife_test", false)
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
