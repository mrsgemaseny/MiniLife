extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := AlifeWorldContext.new()
	world.seed_world(12345, 6.0, TerrainGenerator.GENERATOR_VERSION)
	WorldSeedBuilder.populate(world, TerrainGenerator.GENERATOR_VERSION)
	assert(world.settlements.all().size() == 141)
	var states: Array = WorldData.entities().get("states", [])
	var wildlands: Array = WorldData.entities().get("wildlands", [])
	assert(states.size() == 8 and wildlands.size() == 3)
	var relation_file: FileAccess = FileAccess.open("res://data/authored_political_relations.json", FileAccess.READ)
	assert(relation_file != null)
	var relation_source: Dictionary = JSON.parse_string(relation_file.get_as_text())
	var state_ids: Array = relation_source["state_ids"]
	var relation_rows: Array = relation_source["relations"]
	for row_index: int in range(states.size()):
		var source_faction: AlifeFaction = world.factions.find(str(state_ids[row_index])) as AlifeFaction
		assert(source_faction != null and source_faction.relations.size() == states.size() - 1)
		for column_index: int in range(states.size()):
			if row_index == column_index:
				continue
			assert(source_faction.relations[str(state_ids[column_index])] == relation_rows[row_index][column_index])
	assert(world.factions.find("state.ortenverg").relations["state.reinhard"] == -80)
	assert(world.factions.find("state.reinhard").relations["state.ortenverg"] == -100)
	for entry: Dictionary in states + wildlands:
		var faction: AlifeFaction = world.factions.find(str(entry["id"])) as AlifeFaction
		assert(faction != null, "Missing authored faction: %s" % entry["id"])
		assert(faction.color == Color.html("#" + str(entry["color"])))
		if faction.faction_id.begins_with("wild."):
			assert(faction.leader_id.is_empty() and faction.capital_id.is_empty())
	for settlement: AlifeSettlement in world.settlements.all():
		var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(settlement.tile)
		var owner: String = str(WorldData.cell_at(cell).get("owner", ""))
		assert(settlement.owner_faction == owner, "Settlement owner disagrees with world.json at %s" % cell)
	var authored_armies: Dictionary = world.narrative.get("authored_armies", {})
	assert(authored_armies.size() == 5)
	var active_armies: int = 0
	for entry: Dictionary in WorldData.entities().get("armies", []):
		var army: Dictionary = authored_armies[str(entry["id"])]
		assert(army.status == entry.status and army.route.size() == entry.route.size())
		assert(world.factions.find(str(army.faction_id)) != null)
		for index: int in range(entry.route.size()):
			assert(army.route[index] == [int(entry.route[index].x), int(entry.route[index].y)])
		if entry.get("position") is Dictionary:
			active_armies += 1
			assert(army.position == [int(entry.position.x), int(entry.position.y)])
		else:
			assert(army.position.is_empty())
	assert(active_armies == 4)
	var restored: AlifeWorldContext = AlifeWorldContext.from_dict(world.to_dict())
	assert(restored != null and restored.narrative.get("authored_armies", {}) == authored_armies)
	for state_id: String in state_ids:
		assert(restored.factions.find(state_id).relations == world.factions.find(state_id).relations)
	var legacy := AlifeWorldContext.new()
	legacy.seed_world(12345, 6.0, TerrainGenerator.AUTHORED_ROADS_VERSION)
	WorldSeedBuilder.populate(legacy, TerrainGenerator.AUTHORED_ROADS_VERSION)
	assert(legacy.factions.all().size() == DataRegistry.get_rows("factions").size())
	assert(legacy.settlements.all().size() == 141)
	assert(legacy.factions.find("state.reinhard") == null)
	assert(not legacy.narrative.has("authored_armies"))
	WorldSimulation.set_process(false)
	WorldSimulation._on_save_loaded({"world": {"generator_version": TerrainGenerator.AUTHORED_ROADS_VERSION}})
	WorldSimulation._on_game_started(12345, "legacy_politics_verification", false)
	assert(WorldSimulation.world.factions.find("state.reinhard") == null, "Old save without A-Life was reseeded with new politics")
	assert(WorldSimulation.world.settlements.all().size() == 141)
	print("ALIFE_AUTHORED_POLITICS_PASS settlements=%d states=%d wildlands=%d" % [world.settlements.all().size(), states.size(), wildlands.size()])
	get_tree().quit(0)
