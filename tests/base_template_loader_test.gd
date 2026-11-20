extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: BaseTemplateCatalog = BaseTemplateCatalog.load_default()
	if catalog == null:
		_fail("catalog failed to load")
		return
	for kind: String in BaseTemplateCatalog.POINT_TYPES:
		if catalog.candidates(kind).is_empty():
			_fail("no candidates for %s" % kind)
			return
	var picked: String = catalog.choose("village", 42819, Vector2i(9, 4))
	if picked.is_empty() or picked != catalog.choose("village", 42819, Vector2i(9, 4)):
		_fail("village selection is not deterministic")
		return
	var farm: AuthoredBaseTemplate = AuthoredBaseTemplate.load_from(
		"res://future/bases Minilife/MiniLife_Farmstead_Wheat_Fields_6_Buildings.json")
	if farm == null or farm.block_count != 1607 or farm.block_at(Vector2i(494, 474)) != "pillar":
		_fail("farm blocks were not indexed correctly")
		return
	if farm.block_at(Vector2i(0, 0)) != "" or farm.chunk_blocks(Vector2i(0, 0)).size() != 0:
		_fail("empty chunk returned authored tiles")
		return
	var large: AuthoredBaseTemplate = AuthoredBaseTemplate.load_from(
		"res://future/bases Minilife/MiniLife_DENSE_MEDIEVAL_CITY_RECTANGULAR_WALLS.json")
	if large == null or large.block_count != 279345:
		_fail("largest city did not load")
		return
	print("PASS base_template_loader_test: catalog, farm, largest city")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
