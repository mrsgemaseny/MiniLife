extends Node


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(42819, "base_overlay_preview")
	main.get_node("UILayer/MainMenu").close_menu()
	var world: WorldSystem = main.get_node("World") as WorldSystem
	var target: Dictionary = {}
	var placement: Dictionary = {}
	for site: Dictionary in WorldGraph.for_seed(42819).settlement_sites:
		if site["token"] not in ["settlement_village", "settlement_village_2"]:
			continue
		var candidate: Dictionary = world._base_overlay.placement_for_cell(site["cell"])
		if not candidate.is_empty() and str((candidate["template"] as PackedBaseTemplate).source_path).contains("Farmstead_Wheat"):
			target = site
			placement = candidate
			break
	if target.is_empty():
		push_error("No farmstead base selected for preview")
		get_tree().quit(1)
		return
	var template: PackedBaseTemplate = placement["template"]
	var center: Vector2i = target["tile"]
	for y: int in range(template.bounds.position.y, template.bounds.end.y):
		for x: int in range(template.bounds.position.x, template.bounds.end.x):
			if template.block_at(Vector2i(x, y)) == "door":
				center = (target["cell"] as Vector2i) * GlobalLandscapeMap.CELL_TILES \
					+ (placement["offset"] as Vector2i) + Vector2i(x, y)
				break
		if center != target["tile"]:
			break
	print("BASE_PREVIEW_SITE ", center, " source=", (placement["template"] as PackedBaseTemplate).source_path,
		" offset=", placement["offset"], " center_token=", world._base_overlay.token_at(center))
	var landing: Vector2i = center
	for radius: int in range(0, 21):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				var candidate: Vector2i = center + Vector2i(x, y)
				if world.is_passable(candidate):
					landing = candidate
					break
			if landing != center:
				break
		if landing != center:
			break
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(landing))
	for frame: int in range(40):
		await get_tree().process_frame
	print("BASE_PREVIEW_RENDER player=", GameManager.get_player_tile(), " world=", world._last_player_tile,
		" token=", world._base_overlay.token_at(GameManager.get_player_tile()), " bounds=", world._visible_tile_bounds())
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var result: Error = get_viewport().get_texture().get_image().save_png("res://output/base_overlay_preview.png")
		if result != OK:
			push_error("Could not save base overlay preview")
			get_tree().quit(1)
			return
	print("PASS base_overlay_preview: %s" % landing)
	get_tree().quit(0)
