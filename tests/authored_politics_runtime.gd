extends Node

const VALDEN: String = "state.valden"
const ORTENVERG: String = "state.ortenverg"
const ROSENWALD: String = "state.rosenwald"
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var factions: FactionSystem = scene.get_node("Systems/FactionSystem")
	var slot: String = "__authored_politics_" + Crypto.new().generate_random_bytes(16).hex_encode()
	GameManager.start_new_game(12345, slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	var world: AlifeWorldContext = WorldSimulation.world
	var map: Dictionary[Vector2i, Dictionary] = WorldData.political_settlements()
	var states: Dictionary[String, Dictionary] = WorldData.political_states()
	var matrix: Dictionary[String, Dictionary] = WorldData.political_relations()
	var graph: WorldGraph = WorldGraph.for_seed(world.world_seed, world.generator_version)
	_check(world.generator_version == TerrainGenerator.GENERATOR_VERSION, "New slot used the wrong generator version")
	_check(world.settlements.all().size() == map.size() and graph.settlement_sites.size() == map.size(),
		"The game did not seed every WorldStudio settlement")
	for cell: Vector2i in map:
		var authored: Dictionary = map[cell]
		var site: Dictionary = graph.site_for_cell(cell)
		var id: String = WorldLayout.settlement_id_for_cell(cell)
		var settlement: AlifeSettlement = world.settlements.find(id) as AlifeSettlement
		var expected_type: String = "city" if authored["type"] == "city" else ("fortress" if authored["type"] in ["castle", "fortress"] else "village")
		var owner: String = authored["owner"] if states.has(authored["owner"]) else ""
		var resident: GlobalAgent = world.agents.find(id + "/resident/0000") as GlobalAgent
		_check(settlement != null and settlement.owner_faction == owner and settlement.settlement_type == expected_type
			and site.get("tile") == settlement.tile and site.get("object_id") == authored["id"]
			and resident != null and resident.faction_id == owner, "Incorrect settlement or resident ownership at %s" % cell)
	for id: String in states:
		var state: AlifeFaction = world.factions.find(id) as AlifeFaction
		_check(state != null and state.name == states[id]["name"] and state.color == states[id]["color"]
			and state.relations == matrix[id] and not state.capital_id.is_empty()
			and factions.get_all_factions().get(id, {}).get("name") == states[id]["name"], "Missing or incorrect state " + id)
	for id: String in WorldData.political_wildlands():
		_check(world.factions.find(id) == null, "A wildland group was registered as a state")
	var valden: AlifeFaction = world.factions.find(VALDEN) as AlifeFaction
	_check(valden != null and valden.capital_id == "settlement_07_13", "Valden's castle is not its seat")
	var ortenverg: AlifeFaction = world.factions.find(ORTENVERG) as AlifeFaction
	var rosenwald: AlifeFaction = world.factions.find(ROSENWALD) as AlifeFaction
	_check(ortenverg != null and rosenwald != null and FactionRelations.get_stance(ortenverg, rosenwald) == "neutral"
		and FactionRelations.get_stance(rosenwald, ortenverg) == "allied", "Diplomacy lost the direction of the authored scores")
	var changed: bool = FactionRelations.apply_relation_delta(world, ORTENVERG, ROSENWALD, -5)
	_check(changed and ortenverg.relations[ROSENWALD] == 35 and rosenwald.relations[ORTENVERG] == 50
		and matrix[ORTENVERG][ROSENWALD] == 40 and matrix[ROSENWALD][ORTENVERG] == 55, "A runtime diplomatic change edited the author data")
	factions.change_reputation(VALDEN, 60, "authored_politics_test")
	_check(factions.join_faction(VALDEN), "The player could not join an authored state")
	if _check(save_system.save_slot(slot) and save_system.load_slot(slot) and WorldSimulation.last_load_error.is_empty(),
		"Authored politics did not survive a real save/load"):
		world = WorldSimulation.world
		ortenverg = world.factions.find(ORTENVERG) as AlifeFaction
		_check(ortenverg != null and ortenverg.relations[ROSENWALD] == 35 and world.settlements.all().size() == map.size()
			and factions.get_reputation(VALDEN) == 60 and factions.get_joined_faction() == VALDEN,
			"Save lost the changed diplomacy, settlements or allegiance")
	save_system.delete_slot(slot)
	if failures == 0:
		print("AUTHORED_POLITICS_RUNTIME_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error(message)
	return condition
