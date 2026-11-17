extends Node

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var save_system: Node = main.get_node("Systems/SaveSystem")
	save_system.free()
	SaveSystem.instance = null
	GameManager.start_new_game(Config.DEFAULT_WORLD_SEED, "ground_tile_preview")
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(Vector2i(256, 715)))
	for frame: int in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/ground_tile_preview.png")
	print("GROUND_TILE_PREVIEW: PASS")
	get_tree().quit()
