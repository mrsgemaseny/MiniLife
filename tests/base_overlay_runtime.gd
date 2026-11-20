extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(42819, "base_overlay_verification")
	var world: WorldSystem = main.get_node("World") as WorldSystem
	if world == null or world.get_generator_version() != TerrainGenerator.GENERATOR_VERSION:
		_fail("new world did not use base generation")
		return
	var target: Dictionary = {}
	for site: Dictionary in WorldGraph.for_seed(42819).settlement_sites:
		if site["token"] == "settlement_village":
			target = site
			break
	if target.is_empty():
		_fail("no village site")
		return
	var cell: Vector2i = target["cell"]
	var placement: Dictionary = world._base_overlay.placement_for_cell(cell)
	if placement.is_empty():
		_fail("village has no authored base")
		return
	var template: PackedBaseTemplate = placement["template"]
	var wall: Vector2i = Vector2i(-1, -1)
	for y: int in range(template.bounds.position.y, template.bounds.end.y):
		for x: int in range(template.bounds.position.x, template.bounds.end.x):
			var local := Vector2i(x, y)
			if template.block_at(local) in ["stone_wall", "wood_wall", "brick", "pillar"]:
				wall = local
				break
		if wall.x >= 0:
			break
	if wall.x < 0:
		_fail("village base has no wall")
		return
	var tile: Vector2i = cell * GlobalLandscapeMap.CELL_TILES + (placement["offset"] as Vector2i) + wall
	var state: WorldSystem.TileState = world.get_tile(tile)
	if state.structure_id != "wall" or state.passable or state.tile_id != template.block_at(wall):
		_fail("authored wall is not rendered as a blocking world tile")
		return
	var placed_count: int = 0
	for site: Dictionary in WorldGraph.for_seed(42819).settlement_sites:
		var assigned: Dictionary = world._base_overlay.placement_for_cell(site["cell"])
		if assigned.is_empty():
			_fail("settlement has no authored base at %s" % str(site["cell"]))
			return
		var authored: PackedBaseTemplate = assigned["template"]
		var offset: Vector2i = assigned["offset"]
		if (authored.bounds.position + offset).x < 0 or (authored.bounds.position + offset).y < 0 \
				or (authored.bounds.end + offset).x > 1000 or (authored.bounds.end + offset).y > 1000:
			_fail("authored base crossed cell edge at %s" % str(site["cell"]))
			return
		placed_count += 1
	var saved: Dictionary = world.get_save_data()
	if int(saved.get("generator_version", 0)) != TerrainGenerator.GENERATOR_VERSION \
			or saved.get("chunk_deltas", {}).has(Config.vec2i_to_key(Config.tile_to_chunk(tile))):
		_fail("authored wall was written as a chunk delta")
		return
	var legacy := WorldBaseOverlay.new()
	legacy.setup(42819, TerrainGenerator.PRE_BASE_GENERATOR_VERSION)
	if legacy.token_at(tile) != "":
		_fail("version 3 world unexpectedly acquired an authored base")
		return
	var previous := WorldBaseOverlay.new()
	previous.setup(42819, TerrainGenerator.PRE_WORLDSTUDIO_SETTLEMENT_VERSION)
	if not previous.placement_for_cell(Vector2i(16, 10)).is_empty() \
			or previous.placement_for_cell(cell).is_empty():
		_fail("version 4 world did not preserve its original base sites")
		return
	print("PASS base_overlay_runtime: %d current settlements assigned; wall blocks movement; base excluded from deltas; version 3 unchanged" % placed_count)
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
