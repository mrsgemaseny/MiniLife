extends Node2D

var labels: Array[Dictionary] = []

func _ready() -> void:
	WorldSimulation.set_process(false)
	GameManager.set_process(false)
	RenderingServer.set_default_clear_color(Color("7b8050"))
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(640, 360)
	camera.zoom = Vector2(2.5, 2.5)
	add_child(camera)
	camera.make_current()
	var row: int = 0
	for helmet: String in ["", "steel_helmet", "iron_great_helm"]:
		var outfit: String = "Starter" if helmet.is_empty() else ("Armet" if helmet == "steel_helmet" else "Pot helm")
		for col: int in range(4):
			var player: Player = load("res://scenes/entities/player.tscn").instantiate()
			add_child(player)
			player.get_node("Camera2D").enabled = false
			player.set_physics_process(false)
			player.set_process(false)
			player.position = Vector2(490 + col * 100, 285 + row * 95)
			player.facing_direction = [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT][col]
			if not helmet.is_empty():
				for pair: Array in [["head", helmet], ["chest", "steel_plate_armor"], ["clothing", "arming_doublet"], ["legs", "steel_greaves"], ["feet", "steel_boots"]]:
					player.equipment.equip(str(pair[1]), -1, str(pair[0]))
			player.queue_redraw()
			labels.append({"position": player.position + Vector2(-35, 14), "text": outfit + " / " + ["front", "right", "back", "left"][col]})
		row += 1
	camera.make_current()
	queue_redraw()
	call_deferred("capture")

func _draw() -> void:
	var tile_size: Vector2 = Vector2(Config.TILE_SIZE)
	for x: int in range(5, 22):
		for y: int in range(2, 13):
			var corner: Vector2 = Config.world_to_iso(Vector2i(x, y)) - tile_size * 0.5
			draw_rect(Rect2(corner, tile_size), Color("666e42"), false, 0.6)
	for label: Dictionary in labels:
		draw_string(ThemeDB.fallback_font, label["position"], label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

func capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/player_sketch_preview.png")
	print("WEARABLE PLAYER PREVIEW: PASS")
	get_tree().quit()
