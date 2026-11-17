extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var first := PoiDecoration.new()
	add_child(first)
	var info := {"poi_id": "merchant_outpost", "tile_pos": Vector2i(12, 12)}
	first.populate(123, info, func(_t: Vector2i): return true, func(_t: Vector2i): return 0)
	assert(first.get_child_count() > 0)
	# Full local view (e2afa1a): the local map is not hidden by fog, so props are visible
	# even on unexplored tiles and fog updates neither hide nor darken them.
	for prop: Sprite2D in first.get_children():
		assert(prop.visible and prop.texture != null)
		assert(prop.texture.get_width() * prop.scale.x <= 38.1)
	var tile: Vector2i = first._props.keys()[0]
	SignalBus.fog_updated.emit(tile, 0)
	SignalBus.fog_batch_updated.emit([{"pos": tile, "state": 1}])
	assert(first._props[tile].visible and first._props[tile].modulate == Color.WHITE)
	var second := PoiDecoration.new()
	add_child(second)
	second.populate(123, info, func(_t: Vector2i): return true, func(_t: Vector2i): return 2)
	assert(first._props.keys() == second._props.keys())
	for t: Vector2i in first._props:
		assert(first._props[t].get_meta("decoration_id") == second._props[t].get_meta("decoration_id"))
	var blocked := PoiDecoration.new()
	add_child(blocked)
	blocked.populate(123, info, func(_t: Vector2i): return false, func(_t: Vector2i): return 2)
	assert(blocked.get_child_count() == 0)
	var world: Node2D = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	var decoration: Node = null
	var chosen := Vector2i.ZERO
	var rect: Rect2i = WorldLayout.cell_chunk_rect(WorldLayout.START_CELL)
	for x: int in range(rect.position.x + 1, rect.end.x - 1):
		for y: int in range(rect.position.y + 1, rect.end.y - 1):
			var cpos := Vector2i(x, y)
			var biome: String = world.get_biome_cached(Config.chunk_origin(cpos) + Vector2i(8, 8))
			var candidate: Dictionary = PoiGenerator.get_chunk_poi(Config.DEFAULT_WORLD_SEED, cpos, biome)
			if candidate.is_empty() or not world.is_passable(candidate["tile_pos"]):
				continue
			world._load_chunk(cpos)
			var chunk: Node = world._loaded_chunks[cpos]
			var art: Node = chunk.get_node_or_null("PoiDecorations")
			if art != null and art.get_child_count() > 0:
				decoration = art
				chosen = cpos
				break
		if decoration != null:
			break
	assert(decoration != null and decoration.get_child_count() > 0)
	if OS.get_cmdline_user_args().has("--preview-poi-art"):
		var focus: Vector2i = decoration._props.keys()[0]
		world._last_player_tile = focus
		world.update_visibility(Config.world_to_iso(focus))
		var camera := Camera2D.new()
		camera.position = Config.world_to_iso(focus)
		camera.zoom = Vector2(1.6, 1.6)
		add_child(camera)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/poi_art_ingame.png")
	var weak: WeakRef = weakref(decoration)
	world._unload_chunk(chosen)
	await get_tree().process_frame
	assert(weak.get_ref() == null)
	print("POI_ART_PASS: live world spawn/unload, deterministic layout, full local view, blocked terrain, aspect ratio")
	get_tree().quit()
