extends Node

# Verifies the bundled WorldStudio document and its runtime landscape.

func _ready() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("GLOBAL_LANDSCAPE_MAP_FAIL: " + message)
	get_tree().quit(1)


func _run() -> void:
	var world: Dictionary = WorldData.snapshot()
	if world.is_empty() or not _check_world_data(world):
		_fail("bundled world.json failed its schema checks")
		return
	var map: GlobalLandscapeMap = WorldLayout.landscape()
	if map == null:
		_fail("world data returned no landscape")
		return
	if map.width != 21 or map.height != 15:
		_fail("size %dx%d" % [map.width, map.height])
		return
	if map.land_cell_count() != 184:
		_fail("land cells %d" % map.land_cell_count())
		return
	var counts: Dictionary = {}
	for cell: Vector2i in map.land_cells():
		var kind: String = map.kind_at(cell)
		counts[kind] = int(counts.get(kind, 0)) + 1
	if counts.get("plains", 0) != 96 or counts.get("forest", 0) != 37 \
			or counts.get("desert", 0) != 34 or counts.get("mountains", 0) != 17:
		_fail("kind counts %s" % str(counts))
		return
	if map.kind_at(Vector2i(14, 9)) != "mountains":
		_fail("authored cell 14,9 is not mountains")
		return
	# Void is void: top-left corner and the cell east of the start are not land.
	if map.is_land(Vector2i(0, 0)) or map.is_land(Vector2i(10, 14)):
		_fail("void cell reported as land")
		return
	if WorldLayout.size_tiles() != Vector2i(21000, 15000):
		_fail("size_tiles %s" % str(WorldLayout.size_tiles()))
		return
	var start: Vector2i = WorldLayout.start_tile()
	if start != Vector2i(9500, 14500) or not WorldLayout.contains_tile(start):
		_fail("start tile %s" % str(start))
		return
	if WorldLayout.contains_tile(Vector2i(-1, 0)) or WorldLayout.contains_tile(Vector2i(10500, 14500)):
		_fail("tile outside land accepted")
		return
	if not WorldLayout.contains_chunk(Config.tile_to_chunk(start)):
		_fail("start chunk rejected")
		return
	print("GLOBAL_LANDSCAPE_MAP_OK: 21x15, 184 land cells, kinds, void cells, start tile, tile and chunk containment")
	get_tree().quit(0)


func _check_world_data(world: Dictionary) -> bool:
	if world["schema_version"] != 1 or world["entities"]["states"].size() != 8 \
			or world["entities"]["states"][0]["name"] != "Рейнгард" \
			or world["entities"]["armies"].size() != 5 or world["objects"].size() != 145 \
			or world["relations"]["matrix"].size() != 8:
		return false
	for version: Variant in [0, 2, 1.5, "1", null, true]:
		world["schema_version"] = version
		if not _rejects(world, "schema_version"):
			return false
	world.erase("schema_version")
	if not _rejects(world, "schema_version"):
		return false
	world["schema_version"] = 1
	world["grid"]["chunk_tiles"] = 32
	if not _rejects(world, "grid"):
		return false
	world["grid"]["chunk_tiles"] = 16
	var cells: Array = world["cells"]
	cells.append(cells[0].duplicate())
	if not _rejects(world, "duplicate cell"):
		return false
	cells.pop_back()
	var first: Dictionary = cells[0]
	var original_x: Variant = first["x"]
	for x: Variant in [-1, 21, 0.5, "9"]:
		first["x"] = x
		if not _rejects(world, "integer coordinates"):
			return false
	first["x"] = original_x
	first["landscape"] = "unknown"
	if not _rejects(world, "unsupported landscape"):
		return false
	first["landscape"] = null
	var pos := Vector2i(int(first["x"]), int(first["y"]))
	var changed: WorldDataLoader.ReadResult = WorldDataLoader.parse(JSON.stringify(world))
	return changed.error.is_empty() and not changed.landscape.is_land(pos) \
		and WorldLayout.landscape().is_land(pos) \
		and WorldDataLoader.parse("{").error.begins_with("Invalid JSON") \
		and WorldDataLoader.read_from("res://data/nonexistent_world.json").error.begins_with("Cannot open")


func _rejects(world: Dictionary, reason: String) -> bool:
	var rejected: WorldDataLoader.ReadResult = WorldDataLoader.parse(JSON.stringify(world))
	return rejected.landscape == null and rejected.error.contains(reason)
