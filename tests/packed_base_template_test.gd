extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: String = "res://future/bases Minilife/MiniLife_Farmstead_Wheat_Fields_6_Buildings.json"
	var packed: PackedBaseTemplate = PackedBaseTemplate.load_from_source(source)
	if packed == null or packed.block_count != 1607 or packed.block_at(Vector2i(494, 474)) != "pillar":
		_fail("farm tile did not load from packed chunk")
		return
	if packed.block_at(Vector2i.ZERO) != "" or packed.chunk_blocks(Vector2i.ZERO).size() != 0:
		_fail("empty chunk returned blocks")
		return
	var city: PackedBaseTemplate = PackedBaseTemplate.load_from_source(
		"res://future/bases Minilife/MiniLife_DENSE_MEDIEVAL_CITY_RECTANGULAR_WALLS.json")
	if city == null or city.block_count != 279345 or city.chunk_blocks(Vector2i(30, 30)).is_empty():
		_fail("large city chunk did not load")
		return
	print("PASS packed_base_template_test: farm and large city chunks")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
