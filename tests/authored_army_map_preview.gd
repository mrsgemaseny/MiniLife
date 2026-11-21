extends Node


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(42819, "authored_army_map_preview")
	main.get_node("UILayer/MainMenu").close_menu()
	var global_map: GlobalMapUI = main.get_node("UILayer/GlobalMapUI") as GlobalMapUI
	global_map.open_panel()
	for frame: int in range(3):
		await get_tree().process_frame
	assert(global_map.visible)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var saved: Error = get_viewport().get_texture().get_image().save_png("res://output/authored_army_map_preview.png")
		assert(saved == OK)
	print("AUTHORED_ARMY_MAP_PREVIEW_PASS")
	get_tree().quit(0)
