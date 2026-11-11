extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	var seed_value: int = Config.DEFAULT_WORLD_SEED
	GameManager.start_new_game(seed_value, "bandit_preview_readonly")
	GameManager.set_day_and_hour(1, 12.0)
	var plan: Dictionary = PoiGenerator._build_bandit_plan(seed_value)
	var picked_chunk: Vector2i = Vector2i(-1, -1)
	var picked: Dictionary = {}
	for chunk: Vector2i in plan:
		var info: Dictionary = plan[chunk]
		if str(info["poi_id"]) == "bandit_chief_camp":
			picked_chunk = chunk
			picked = info
			break
	assert(not picked.is_empty())
	var world: WorldSystem = main.get_node("World") as WorldSystem
	world._pending_chunks.erase(picked_chunk)
	world._load_chunk(picked_chunk)
	var bandits: int = 0
	for entity: Node in world._spawned_entities_by_chunk.get(picked_chunk, []):
		if entity is EnemyBase and entity.faction_id == "bandits":
			entity.set_physics_process(false)
			print("CAMP_BANDIT: ", entity.enemy_id, " tile=", Config.iso_to_world(entity.global_position), " texture=", entity._bandit_texture != null)
			bandits += 1
	assert(bandits >= 5)
	var player: Player = main.get_node("World/Player") as Player
	player.set_physics_process(false)
	var focus: Vector2i = picked["tile_pos"] + Vector2i(3, 6)
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(focus))
	world._last_player_tile = focus
	world.update_visibility(Config.world_to_iso(focus))
	SignalBus.ui_close_all_requested.emit()
	main.get_node("UILayer/MainMenu").hide()
	GameManager.resume()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * 1.55
	camera.offset = Vector2(0.0, -160.0)
	camera.reset_smoothing()
	for frame: int in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for entity: Node in world._spawned_entities_by_chunk.get(picked_chunk, []):
		if entity is EnemyBase and entity.faction_id == "bandits":
			print("CAMP_VISIBLE: ", entity.enemy_id, " visible=", entity.visible, " fog=", world.get_fog_state(Config.iso_to_world(entity.global_position)))
	var screenshot: String = "res://output/bandit_chief_camp_preview.png"
	var saved: Error = get_viewport().get_texture().get_image().save_png(screenshot)
	print("BANDIT_CAMP_PREVIEW: chunk=", picked_chunk, " anchor=", picked["tile_pos"], " bandits=", bandits, " screenshot=", screenshot, " result=", saved)
	get_tree().quit(0 if saved == OK else 1)
