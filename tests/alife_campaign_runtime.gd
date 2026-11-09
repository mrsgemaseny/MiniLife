extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures <= 10:
			push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(12345, 8.0)
	WorldSeedBuilder.populate(world)
	var codec: AlifeAgentSaveDelta = AlifeAgentSaveDelta.new()
	codec.capture(world, Config.TERRAIN_GEOGRAPHY_SIZE)
	var agents: AgentTick = AgentTick.new()
	var economy: EconomyTick = EconomyTick.new()
	var factions: FactionTick = FactionTick.new()
	var conflicts: ConflictTick = ConflictTick.new()
	var rumors: RumorTick = RumorTick.new()
	var caravans: CaravanTick = CaravanTick.new()
	var started: int = Time.get_ticks_msec()
	var previous_dead: int = 0
	var reference: AlifeWorldContext = null
	var reference_agents: AgentTick = AgentTick.new()
	for step: int in range(36):
		world.simulated_hour += 2.0
		economy.tick(world, 2.0)
		factions.tick(world, 2.0)
		agents.tick(world, 2.0)
		conflicts.tick(world, 2.0)
		caravans.tick(world)
		rumors.tick(world)
		world.tick_count += 1
		if reference != null:
			reference.simulated_hour += 2.0
			economy.tick(reference, 2.0)
			factions.tick(reference, 2.0)
			reference_agents.tick(reference, 2.0)
			conflicts.tick(reference, 2.0)
			caravans.tick(reference)
			rumors.tick(reference)
			reference.tick_count += 1
		var dead: int = world.agents.matching("alive", false).size()
		check(dead >= previous_dead, "Dead agents never resurrect during campaign")
		previous_dead = dead
		var population: int = 0
		for settlement: AlifeSettlement in world.settlements.all():
			population += settlement.population
			var expected: int = 0
			for agent: GlobalAgent in world.agents.by_settlement(settlement.settlement_id):
				if agent.alive and agent.role in ["guard", "soldier"] and agent.faction_id == settlement.owner_faction:
					expected += 1
			check(settlement.garrison == expected, "Garrison agrees with living guard identities")
		var displaced: int = 0
		for id: String in world.narrative.get("refugee_travelers", {}):
			var refugee: GlobalAgent = world.agents.find(id) as GlobalAgent
			if refugee != null and refugee.alive and refugee.settlement_id.is_empty():
				displaced += 1
		check(population + displaced == world.agents.matching("alive", true).size(), "Settled and displaced populations agree with agents after each tick")
		if step == 17:
			reference = world
			reference_agents._elapsed = agents._elapsed
			var loaded: AlifeWorldContext = codec.decode(JSON.parse_string(JSON.stringify(codec.encode(world))), Config.TERRAIN_GEOGRAPHY_SIZE)
			check(loaded != null, "Campaign can load mid-war")
			if loaded == null:
				get_tree().quit(1)
				return
			world = loaded
	var battles: int = 0
	for faction: AlifeFaction in world.factions.all():
		var neighbors: Array = []
		for other: AlifeFaction in world.factions.all():
			if other != faction and FactionRelations.are_neighbors(world, faction.faction_id, other.faction_id):
				neighbors.append(other.faction_id)
		print("CAMPAIGN FACTION ", faction.faction_id, " treasury=", faction.treasury, " strength=", faction.military_strength, " neighbors=", neighbors)
	for conflict: AlifeConflict in world.conflicts.all():
		battles += conflict.battles_fought
	check(world.conflicts.all().size() > 0, "Autonomous politics produces conflicts")
	check(battles > 0, "Autonomous armies reach targets and resolve battles")
	var arrivals: int = 0
	for event: Dictionary in world.events:
		if str(event.get("event_type", "")) == "caravan_arrived":
			arrivals += 1
	check(arrivals > 0, "Autonomous economy dispatches real caravans and delivers cargo")
	var differences: int = 0
	for agent: GlobalAgent in world.agents.all():
		var original: GlobalAgent = reference.agents.find(agent.agent_id) as GlobalAgent
		if original != null and agent.to_dict() != original.to_dict():
			if differences < 3:
				for field: String in agent._fields():
					if agent.to_dict()[field] != original.to_dict()[field]:
						print("CAMPAIGN DIFF ", agent.agent_id, " ", field, " loaded=", agent.to_dict()[field], " uninterrupted=", original.to_dict()[field])
			differences += 1
	check(world.agents.to_array() == reference.agents.to_array(), "Campaign with mid-war save has identical agent outcomes to uninterrupted campaign")
	for faction: AlifeFaction in world.factions.all():
		var uninterrupted: AlifeFaction = reference.factions.find(faction.faction_id) as AlifeFaction
		check(uninterrupted != null and faction.treasury == uninterrupted.treasury and faction.state == uninterrupted.state, "Campaign save preserves political and financial outcomes")
	print("ALIFE CAMPAIGN TESTS: ", "PASS" if failures == 0 else "FAIL", " conflicts=", world.conflicts.all().size(), " battles=", battles, " caravan_arrivals=", arrivals, " deaths=", previous_dead, " elapsed_ms=", Time.get_ticks_msec() - started, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
