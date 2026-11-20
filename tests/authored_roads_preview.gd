extends Node


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(42819, "authored_roads_preview")
	main.get_node("UILayer/MainMenu").close_menu()
	var tile := Vector2i(12999, 2500)
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(tile))
	for frame: int in range(50):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var result: Error = get_viewport().get_texture().get_image().save_png("res://output/authored_roads_preview.png")
		if result != OK:
			push_error("Could not save road preview")
			get_tree().quit(1)
			return
	print("AUTHORED_ROADS_PREVIEW_PASS player=", GameManager.get_player_tile())
	get_tree().quit(0)
