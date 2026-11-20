extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var routes: Array[PackedVector2Array] = WorldLayout.army_routes()
	if routes.size() != 5:
		_fail("Expected five authored army routes, got %d" % routes.size())
		return
	for route: PackedVector2Array in routes:
		for index: int in range(route.size()):
			var cell: Vector2 = route[index]
			if not WorldLayout.landscape().is_land(Vector2i(cell)):
				_fail("Road route crosses void at %s" % cell)
				return
			if index > 0:
				var previous: Vector2 = route[index - 1]
				if maxf(absf(cell.x - previous.x), absf(cell.y - previous.y)) > 1.0:
					_fail("Route jumps between %s and %s" % [previous, cell])
					return
	var new_graph: WorldGraph = WorldGraph.for_seed(42819, TerrainGenerator.GENERATOR_VERSION)
	var old_graph: WorldGraph = WorldGraph.for_seed(42819, TerrainGenerator.WORLDSTUDIO_MARKERS_VERSION)
	var west: Vector2i = Vector2i(12999, 2500)
	var east: Vector2i = Vector2i(13000, 2500)
	for tile: Vector2i in [west, east]:
		var point: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
		if not new_graph.is_road_at(point) or old_graph.is_road_at(point):
			_fail("Road does not join across cell border or changed version 6 at %s" % tile)
			return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(42819, "authored_roads_test")
	var world: WorldSystem = main.get_node("World") as WorldSystem
	for tile: Vector2i in [west, east]:
		var state: WorldSystem.TileState = world.get_tile(tile)
		if not state.passable or state.tile_id not in ["dirt", "wood_floor"]:
			_fail("Road is not a passable surface at %s" % tile)
			return
		if world._terrain.get_resource_node_at(tile) != "":
			_fail("Resource blocks the road at %s" % tile)
			return
	var chunk: Vector2i = Config.tile_to_chunk(west)
	var job := ChunkTerrainJob.new()
	job.start(42819, chunk, TerrainGenerator.GENERATOR_VERSION)
	if world._terrain.generate_chunk(chunk) != job.collect():
		_fail("Road chunk differs between worker and main thread")
		return
	print("AUTHORED_ROADS_RUNTIME_PASS: five routes, seamless border, passable tiles, no resources, version 6 preserved")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("AUTHORED_ROADS_RUNTIME_FAIL: " + message)
	get_tree().quit(1)
