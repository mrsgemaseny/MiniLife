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
	if not _check_trade_routes(WorldData.snapshot()):
		_fail("trade routes failed validation or did not preserve their direction")
		return
	if not _check_river_schema(WorldData.snapshot()):
		_fail("river data failed to validate")
		return
	if not _check_army_schema(WorldData.snapshot()):
		_fail("army data lost its state or authored route")
		return
	if not _check_political_schema(WorldData.snapshot()):
		_fail("settlement ownership or directional relations lost their authored values")
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


func _check_political_schema(world: Dictionary) -> bool:
	var states: Dictionary[String, Dictionary] = WorldData.political_states()
	var settlements: Dictionary[Vector2i, Dictionary] = WorldData.political_settlements()
	var relations: Dictionary[String, Dictionary] = WorldData.political_relations()
	if states.size() != 8 or WorldData.political_wildlands().size() != 3 or settlements.size() != 141 \
			or states["state.valden"]["name"] != "Вальден" or states["state.valden"]["kind"] != "county" \
			or states["state.valden"]["color"] != Color.html("CCCC1E") \
			or settlements.get(Vector2i(7, 14)) != {"id": "obj.village_48", "type": "village", "owner": "state.valden"} \
			or relations["state.ortenverg"].get("state.rosenwald") != 40 \
			or relations["state.rosenwald"].get("state.ortenverg") != 55 or relations["state.valden"].has("state.valden"):
		return false
	var matrix: Array = world["relations"]["matrix"]
	matrix[0][0] = 0
	if not _rejects(world, "Invalid relations score"):
		return false
	matrix[0][0] = null
	matrix[0][1] = -101
	if not _rejects(world, "Invalid relations score"):
		return false
	matrix[0][1] = null
	var incomplete: WorldDataLoader.ReadResult = WorldDataLoader.parse(JSON.stringify(world))
	if not incomplete.error.is_empty() or incomplete.relations["state.reinhard"].has("state.ortenverg"):
		return false
	world["relations"]["order"][1] = "state.missing"
	if not _rejects(world, "Relations order"):
		return false
	world["relations"]["order"][1] = "state.ortenverg"
	var objects: Array = world["objects"]
	var site: Dictionary = objects.filter(func(row: Dictionary) -> bool: return row["id"] == "obj.village_48")[0]
	site["owner"] = "state.missing"
	if not _rejects(world, "Unknown owner for settlement"):
		return false
	site["owner"] = "state.valden"
	var duplicate: Dictionary = site.duplicate(true)
	duplicate["id"] = "obj.village_duplicate"
	objects.append(duplicate)
	return _rejects(world, "Invalid or duplicate settlement")


func _check_army_schema(world: Dictionary) -> bool:
	var armies: Dictionary[String, Dictionary] = WorldData.imperial_armies()
	var west: Dictionary = armies.get("army.west_1", {})
	var destroyed: Dictionary = armies.get("army.girdenburg", {})
	if armies.size() != 5 or west.get("status") != "roaming" or west.get("origin") != Vector2i(13, 2) \
			or west.get("position") != Vector2i(4, 6) or west.get("route", []).size() != 12 \
			or west["route"].front() != Vector2i(12, 2) or west["route"].back() != Vector2i(4, 5) \
			or destroyed.get("status") != "destroyed" or destroyed.get("position") != Vector2i(-1, -1):
		return false
	var rows: Array = world["entities"]["armies"]
	rows.append(rows[0].duplicate(true))
	if not _rejects(world, "duplicate army id"):
		return false
	rows.pop_back()
	rows[0]["route"].append({"x": 21, "y": 0})
	if not _rejects(world, "invalid army route cell"):
		return false
	rows[0]["route"].pop_back()
	rows[0]["status"] = "missing"
	if not _rejects(world, "unknown army status"):
		return false
	world["entities"].erase("armies")
	var legacy: WorldDataLoader.ReadResult = WorldDataLoader.parse(JSON.stringify(world))
	return legacy.error.is_empty() and legacy.armies.is_empty()


func _check_trade_routes(world: Dictionary) -> bool:
	var village: String = WorldLayout.settlement_id_for_cell(Vector2i(7, 14))
	var castle: String = WorldLayout.settlement_id_for_cell(Vector2i(7, 13))
	if WorldData.trade_corridor(village, castle) != [Vector2i(7, 14), Vector2i(7, 13)] \
			or WorldData.trade_corridor(castle, village) != [Vector2i(7, 13), Vector2i(7, 14)]:
		return false
	var context: AlifeWorldContext = AlifeWorldContext.new()
	for id: String in [village, castle]:
		var settlement: AlifeSettlement = AlifeSettlement.new()
		settlement.settlement_id = id
		context.settlements.register(settlement)
	CaravanRouteManager.register_authored_routes(context)
	CaravanRouteManager.register_authored_routes(context)
	if context.routes.all().size() != 2 or context.routes.find(village + "->" + castle) == null \
			or context.routes.find(castle + "->" + village) == null:
		return false
	var routes: Array = world["trade_routes"]
	var defined: Dictionary = routes[0].duplicate(true)
	routes[0]["from"] = "obj.army_mark_1"
	if not _rejects(world, "endpoints must be settlements"):
		return false
	routes[0] = defined.duplicate(true)
	routes[0]["cells"].insert(1, {"x": 8, "y": 13})
	if not _rejects(world, "share a side"):
		return false
	routes[0] = defined.duplicate(true)
	routes[0]["cells"].insert(1, {"x": 0, "y": 0})
	if not _rejects(world, "unique land cells"):
		return false
	routes[0] = defined
	routes.append(defined.duplicate(true))
	if not _rejects(world, "duplicate road"):
		return false
	world["trade_routes"] = []
	var empty: WorldDataLoader.ReadResult = WorldDataLoader.parse(JSON.stringify(world))
	if not empty.error.is_empty() or not empty.document.has("trade_routes") or not empty.trade_corridors.is_empty():
		return false
	world.erase("trade_routes")
	var prior: WorldDataLoader.ReadResult = WorldDataLoader.parse(JSON.stringify(world))
	return prior.error.is_empty() and prior.trade_corridors.is_empty()


func _check_river_schema(world: Dictionary) -> bool:
	var rows: Array = world["rivers"]
	var sample: Dictionary = rows[0].duplicate(true)
	rows[0]["width"] = 0
	if not _rejects(world, "width"):
		return false
	rows[0] = sample.duplicate(true)
	rows[0]["lake_radius"] = 101
	if not _rejects(world, "lake_radius"):
		return false
	rows[0] = sample.duplicate(true)
	rows[0]["points"][0]["x"] = 21000
	if not _rejects(world, "world tile coordinates"):
		return false
	rows[0] = sample.duplicate(true)
	rows[0]["points"][1] = rows[0]["points"][0]
	if not _rejects(world, "distinct"):
		return false
	# Two known land cells on opposite sides of the void east of the start.
	rows[0] = {"width": 7, "points": [{"x": 9500, "y": 14500}, {"x": 12500, "y": 12500}]}
	if not _rejects(world, "land"):
		return false
	world.erase("rivers")
	var prior: WorldDataLoader.ReadResult = WorldDataLoader.parse(JSON.stringify(world))
	return prior.error.is_empty() and prior.rivers.is_empty()
