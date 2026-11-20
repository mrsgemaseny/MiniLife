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
	var legacy := AlifeWorldContext.new()
	legacy.seed_world(12345, 6.0, TerrainGenerator.AUTHORED_ROADS_VERSION)
	WorldSeedBuilder.populate(legacy, TerrainGenerator.AUTHORED_ROADS_VERSION)
	assert(legacy.factions.all().size() == DataRegistry.get_rows("factions").size())
	assert(legacy.settlements.all().size() == 141)
	assert(legacy.factions.find("state.reinhard") == null)
	WorldSimulation.set_process(false)
	WorldSimulation._on_save_loaded({"world": {"generator_version": TerrainGenerator.AUTHORED_ROADS_VERSION}})
	WorldSimulation._on_game_started(12345, "legacy_politics_verification", false)
	assert(WorldSimulation.world.factions.find("state.reinhard") == null, "Old save without A-Life was reseeded with new politics")
	assert(WorldSimulation.world.settlements.all().size() == 141)
	print("ALIFE_AUTHORED_POLITICS_PASS settlements=%d states=%d wildlands=%d" % [world.settlements.all().size(), states.size(), wildlands.size()])
	get_tree().quit(0)
