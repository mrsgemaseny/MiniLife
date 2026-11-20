extends Node


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(42819, "combat_log_hud_preview")
	main.get_node("UILayer/MainMenu").close_menu()
	for frame: int in range(30):
		await get_tree().process_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	var foe := Node.new()
	add_child(foe)
	SignalBus.combat_log_entry.emit("armor_glancing", "Удар скользит по броне.", player, foe)
	SignalBus.combat_log_entry.emit("shield_block", "Щит принимает удар.", foe, player)
	var hud: HUD = main.get_node("UILayer/HUD") as HUD
	assert(hud._combat_log_panel.visible and hud._combat_log_entries.size() == 2)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var saved: Error = get_viewport().get_texture().get_image().save_png("res://output/combat_log_hud_preview.png")
		assert(saved == OK)
	print("COMBAT_LOG_HUD_PREVIEW_PASS")
	get_tree().quit(0)
