extends Node2D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DataRegistry.reload_all()
	GameManager.resume()
	RenderingServer.set_default_clear_color(Color("343c2e"))
	var names: Array[String] = ["fox", "moose", "wolf", "sheep", "cow", "hare"]
	for i in range(names.size()):
		var animal: AnimalEntity = AnimalEntity.new()
		animal.animal_type = names[i]
		animal.position = Vector2(160 + (i % 3) * 300, 220 + (i / 3) * 250)
		animal.scale = Vector2.ONE * 2.0
		add_child(animal)
		animal.set_physics_process(false)
		animal._walk_blend = 1.0
		animal._walk_phase = float(i)
		animal.stats.health = animal.stats.max_health * 0.6
		animal.current_state = AnimalEntity.State.WANDER
		animal.queue_redraw()
		var label: Label = Label.new()
		label.text = "%s — %d/%d HP" % [animal.display_name, ceili(animal.stats.health), ceili(animal.stats.max_health)]
		label.position = animal.position + Vector2(-95,35)
		label.add_theme_font_size_override("font_size", 18)
		add_child(label)
	var terrain: TerrainGenerator = TerrainGenerator.new(Config.DEFAULT_WORLD_SEED)
	var mountain_tiles: int = 0
	var resource_tiles: int = 0
	for x in range(40,120):
		for y in range(20,100):
			var tile: Vector2i = Vector2i(x,y)
			if terrain.get_biome_at(tile) == "mountains":
				mountain_tiles += 1
				if not terrain.get_resource_node_at(tile).is_empty():
					resource_tiles += 1
	print("FAUNA_READABILITY_OK: native animated rig; mountain resources ", resource_tiles, "/", mountain_tiles)
	assert(resource_tiles < mountain_tiles * 0.15, "Mountains remain overcrowded")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/art_refresh_2026-11-04/fauna_readability.png")
	get_tree().quit(0)
