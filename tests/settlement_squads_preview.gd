extends Node

# Screenshots of the static settlements: one view per squad anchor kind and settlement type.
const SHOTS: Array[String] = ["tavern", "market", "center", "gate", "barracks", "manor", "workshops", "fields", "forest_edge"]

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(1440, 900)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(Config.DEFAULT_WORLD_SEED, "settlement_squads_preview")
	GameManager.set_day_and_hour(1, 12.0)
	main.get_node("UILayer/MainMenu").close_menu()
	var player: Player = main.get_node("World/Player") as Player
	player.set_physics_process(false)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * 1.25
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/settlement_squads"))
	var done: Dictionary = {}
	for settlement: AlifeSettlement in WorldSimulation.world.settlements.all():
		for squad: SettlementSquad in WorldSimulation.squads_of(settlement.settlement_id):
			var kind: String = str(DataRegistry.get_entry("squads", squad.template_id).get("anchor", ""))
			var key: String = "%s_%s" % [settlement.settlement_type, squad.template_id]
			if done.has(key) or not SHOTS.has(kind):
				continue
			done[key] = true
			SignalBus.player_teleport_requested.emit(Config.world_to_iso(squad.anchor_tile + Vector2i(0, 2)))
			camera.reset_smoothing()
			await _frames(45)
			await _post_draw()
			_save("settlement_squads/%s.png" % key)
	print("SQUAD_PREVIEW_SHOTS: ", done.size())
	get_tree().quit()

func _frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().process_frame

func _can_render() -> bool:
	return DisplayServer.get_name() != "headless"

func _post_draw() -> void:
	if _can_render():
		await RenderingServer.frame_post_draw
	else:
		await get_tree().process_frame

func _save(filename: String) -> void:
	if not _can_render():
		return
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://output/" + filename))
