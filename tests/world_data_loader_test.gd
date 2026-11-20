extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader: Node = root.get_node("WorldData")
	if loader.land_cell_count() != 184:
		_fail("expected 184 WorldStudio cells")
		return
	var legacy: GlobalLandscapeMap = GlobalLandscapeMap.load_from("res://data/nature.json")
	if legacy == null:
		_fail("legacy nature map did not load")
		return
	var kind_names: Dictionary = {"sands": "desert"}
	for cell: Vector2i in legacy.land_cells():
		var data: Dictionary = loader.cell_at(cell)
		var kind: String = str(data.get("landscape", ""))
		if kind_names.get(kind, kind) != legacy.kind_at(cell):
			_fail("landscape mismatch at %s" % cell)
			return
	if loader.cell_at(Vector2i(-1, -1)) != {}:
		_fail("out of bounds cell is not empty")
		return
	if loader.objects().size() != 145:
		_fail("expected 145 WorldStudio objects")
		return
	if not loader.entities().has("armies"):
		_fail("army route data missing")
		return
	print("PASS world_data_loader_test: 184 cells match nature map, 145 objects, army routes")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
