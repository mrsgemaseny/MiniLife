extends Node

# Verifies the authored 21x15 map loads exactly as drawn and WorldLayout geometry is consistent.

func _ready() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("GLOBAL_LANDSCAPE_MAP_FAIL: " + message)
	get_tree().quit(1)


func _run() -> void:
	var map: GlobalLandscapeMap = GlobalLandscapeMap.load_from(WorldLayout.LANDSCAPE_PATH)
	if map == null:
		_fail("load returned null")
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
		_fail("stone_wall cell 14,9 is not mountains")
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
