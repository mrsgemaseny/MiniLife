extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func fixture() -> AlifeWorldContext:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(42, 10.0)
	world.tick_count = 10
	var index: int = 0
	for id: String in ["a", "b", "c"]:
		var settlement: AlifeSettlement = AlifeSettlement.new()
		settlement.settlement_id = id
		settlement.name = id
		settlement.tile = Vector2i(20 + index * 16, 20)
		settlement.owner_faction = "merchants"
		settlement.connections = ["b"] if id == "a" else (["a", "c"] if id == "b" else ["b"])
		settlement.population = 2
		settlement.garrison = 1
		world.settlements.register(settlement)
		for role: String in ["elder", "guard"]:
			var agent: GlobalAgent = GlobalAgent.new()
			agent.agent_id = id + "_" + role
			agent.settlement_id = id
			agent.faction_id = "merchants"
			agent.role = role
			agent.named = role == "elder"
			agent.tile = settlement.tile
			world.agents.register(agent)
		index += 1
	var faction: AlifeFaction = world.factions.find("merchants") as AlifeFaction
	faction.capital_id = "a"
	faction.leader_id = "a_elder"
	faction.succession_list = ["b_elder", "c_elder"]
	faction.recognized_heir_id = "b_elder"
	faction.military_strength = 100.0
	return world

func _ready() -> void:
	var world: AlifeWorldContext = fixture()
	var leader: GlobalAgent = world.agents.find("a_elder") as GlobalAgent
	check(AgentLifecycle.mark_dead(world, leader, "test"), "Leader death recorded")
	check(not AgentLifecycle.mark_dead(world, leader, "duplicate"), "Duplicate death ignored")
	var faction: AlifeFaction = world.factions.find("merchants") as AlifeFaction
	check(faction.state == AlifeFaction.State.SUCCESSION_CRISIS and faction.leader_id.is_empty(), "Leader death starts crisis")
	for step: int in range(3):
		world.tick_count = 10 + step
		FactionSuccession.tick(world, faction)
		check(faction.state == AlifeFaction.State.SUCCESSION_CRISIS, "Succession waits several global ticks")
	world = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	faction = world.factions.find("merchants") as AlifeFaction
	world.tick_count = 13
	FactionSuccession.tick(world, faction)
	check(faction.leader_id == "b_elder" and faction.state == AlifeFaction.State.STABLE, "Recognized heir succeeds after loading mid-crisis")
	check(is_equal_approx(faction.military_strength, 85.0), "Stable succession costs fifteen percent military strength")
	var events: int = world.events.size()
	FactionSuccession.tick(world, faction)
	check(world.events.size() == events, "Succession outcome is not repeated")

	world = fixture()
	faction = world.factions.find("merchants") as AlifeFaction
	faction.recognized_heir_id = ""
	AgentLifecycle.mark_dead(world, world.agents.find("a_elder") as GlobalAgent, "test")
	world.tick_count = 13
	FactionSuccession.tick(world, faction)
	var rebels: Array = world.factions.all().filter(func(f: AlifeFaction) -> bool: return f.faction_id.contains("/rebel/"))
	check(rebels.size() == 1, "Contested succession creates one rebel faction")
	if not rebels.is_empty():
		var rebel: AlifeFaction = rebels[0] as AlifeFaction
		check(rebel.leader_id == "c_elder" and (world.agents.find("c_elder") as GlobalAgent).faction_id == rebel.faction_id, "Pretender leads his own faction")
		check((world.settlements.find("b") as AlifeSettlement).owner_faction == faction.faction_id, "Recognized side retains its heir's settlement")
		check((world.settlements.find("c") as AlifeSettlement).owner_faction == rebel.faction_id, "Rebel territory changes owner")
		check(FactionDiplomacy.at_war(world, faction.faction_id, rebel.faction_id), "Secession starts civil war with an explicit cause")

	world = fixture()
	faction = world.factions.find("merchants") as AlifeFaction
	faction.succession_list.clear()
	AgentLifecycle.mark_dead(world, world.agents.find("a_elder") as GlobalAgent, "test")
	world.tick_count = 13
	FactionSuccession.tick(world, faction)
	check(faction.state == AlifeFaction.State.COLLAPSED, "No eligible heir collapses faction")
	check((world.settlements.find("a") as AlifeSettlement).status == AlifeSettlement.Status.UNGOVERNED, "Leaderless capital becomes ungoverned")
	check((world.agents.find("a_guard") as GlobalAgent).role == "deserter", "Abandoned guards become deserters")
	check(world.factions.find("independent/b") != null and world.factions.find("independent/c") != null, "Remaining councils form independent city states")
	check((world.agents.find("b_elder") as GlobalAgent).faction_id == "independent/b", "Residents adopt independent faction")
	var population: int = 0
	for settlement: AlifeSettlement in world.settlements.all():
		population += settlement.population
	check(population == world.agents.matching("alive", true).size(), "Political breakup does not duplicate or lose population")
	var neighbor: AlifeFaction = world.factions.find("independent/b") as AlifeFaction
	neighbor.military_strength = 20.0
	neighbor.treasury = 200
	world.simulated_hour += 6.0
	FactionAI.evaluate(world, neighbor)
	check((world.settlements.find("a") as AlifeSettlement).owner_faction == neighbor.faction_id, "Strong neighbor can take responsibility for adjacent ungoverned settlement")
	check((world.settlements.find("a") as AlifeSettlement).status == AlifeSettlement.Status.NORMAL, "Protectorate restores normal political status")
	print("ALIFE SUCCESSION TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
