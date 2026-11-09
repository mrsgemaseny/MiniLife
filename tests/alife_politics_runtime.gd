extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func fixture() -> AlifeWorldContext:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(12345, 10.0)
	var a: AlifeSettlement = AlifeSettlement.new()
	a.settlement_id = "a"
	a.owner_faction = "merchants"
	a.tile = Vector2i(20, 20)
	a.garrison = 40
	a.population = 100
	a.connections = ["b", "c"]
	world.settlements.register(a)
	var b: AlifeSettlement = AlifeSettlement.new()
	b.settlement_id = "b"
	b.owner_faction = "bandits"
	b.tile = Vector2i(40, 20)
	b.garrison = 10
	b.population = 40
	b.connections = ["a"]
	world.settlements.register(b)
	var c: AlifeSettlement = AlifeSettlement.new()
	c.settlement_id = "c"
	c.owner_faction = "guards"
	c.tile = Vector2i(20, 40)
	c.garrison = 10
	c.population = 40
	c.connections = ["a"]
	world.settlements.register(c)
	return world

func _ready() -> void:
	var world: AlifeWorldContext = fixture()
	check(not FactionDiplomacy.declare_war(world, "merchants", "guards"), "No war without a cause")
	check(not FactionDiplomacy.declare_war(world, "merchants", "merchants"), "No self war")
	check(not FactionDiplomacy.declare_war(world, "missing", "bandits"), "Unknown faction rejected")
	check(FactionRelations.are_neighbors(world, "merchants", "bandits"), "Graph determines border neighbors")
	check(FactionDiplomacy.sign_treaty(world, "merchants", "bandits", "non_aggression", 2), "Sign valid treaty")
	check(not FactionDiplomacy.declare_war(world, "merchants", "bandits"), "Treaty blocks opportunistic war")
	check(not FactionDiplomacy.sign_treaty(world, "merchants", "bandits", "non_aggression", 2), "Treaty is not duplicated")
	var treaty: AlifeTreaty = world.treaties.all()[0] as AlifeTreaty
	check(FactionDiplomacy.break_treaty(world, treaty.treaty_id, "merchants"), "Break treaty")
	var bandits: AlifeFaction = world.factions.find("bandits") as AlifeFaction
	check(str(bandits.casus_belli.get("merchants", "")) == "broken_treaty", "Victim gets casus belli")
	check(FactionDiplomacy.declare_war(world, "merchants", "bandits"), "Hostile border causes war")
	check(not FactionDiplomacy.declare_war(world, "bandits", "merchants"), "Same pair cannot create duplicate war")
	var merchants: AlifeFaction = world.factions.find("merchants") as AlifeFaction
	var guards: AlifeFaction = world.factions.find("guards") as AlifeFaction
	merchants.casus_belli["guards"] = "raided_caravan"
	check(FactionDiplomacy.declare_war(world, "merchants", "guards"), "Independent second war")
	check(FactionDiplomacy.propose_peace(world, "merchants", "bandits"), "Resolve one war")
	check(merchants.state == AlifeFaction.State.AT_WAR and bandits.state == AlifeFaction.State.STABLE, "Peace preserves other active wars")
	check(FactionDiplomacy.propose_peace(world, "merchants", "guards"), "Resolve remaining war")
	check(merchants.state == AlifeFaction.State.STABLE and guards.state == AlifeFaction.State.STABLE, "Last peace restores stability")
	check(not FactionDiplomacy.declare_war(world, "merchants", "bandits"), "Peace cooldown prevents immediate redeclaration")
	var restored: AlifeWorldContext = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(restored != null and FactionDiplomacy.has_treaty(restored, "merchants", "bandits", "peace"), "Treaties survive JSON save")
	world = fixture()
	FactionTick.new().tick(world, 0.5)
	check(world.conflicts.all().is_empty(), "New world has decision cooldown")
	world.simulated_hour += 6.0
	FactionTick.new().tick(world, 0.5)
	check(FactionDiplomacy.at_war(world, "merchants", "bandits"), "Faction AI declares a justified favorable war")
	var treasury: int = (world.factions.find("merchants") as AlifeFaction).treasury
	var continued: AlifeWorldContext = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	for step: int in range(3):
		FactionTick.new().tick(world, 0.3333333333)
		FactionTick.new().tick(continued, 0.3333333333)
	check((world.factions.find("merchants") as AlifeFaction).treasury == (continued.factions.find("merchants") as AlifeFaction).treasury, "Fractional tax balance survives save and continuation")
	check(treasury > 0, "Fixture has operating treasury")
	print("ALIFE POLITICS TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
