extends Node

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("STREAMING_FAILURE: " + message)

func _ready() -> void:
	call_deferred("run")

func settle(world: WorldSystem) -> void:
	for frame in range(900):
		await get_tree().process_frame
		if world._pending_chunks.is_empty() and world._terrain_jobs.is_empty():
			return
	check(false, "Chunk queue did not drain")

func run() -> void:
	GameManager.resume()
	var actor: Node2D = Node2D.new()
	actor.add_to_group("player")
	add_child(actor)
	var world: WorldSystem = load("res://scenes/world/world.tscn").instantiate() as WorldSystem
	add_child(world)
	world._terrain.setup(Config.DEFAULT_WORLD_SEED)
	var peak_chunks: int = 0
	var max_request_ms: float = 0.0
	for tile in [Vector2i(500,500), Vector2i(530,500), Vector2i(570,530), Vector2i(640,520), Vector2i(450,500), Vector2i(500,500)]:
		actor.position = Config.world_to_iso(tile)
		var started: int = Time.get_ticks_usec()
		SignalBus.player_tile_changed.emit(tile)
		max_request_ms = maxf(max_request_ms, (Time.get_ticks_usec() - started) / 1000.0)
		await settle(world)
		peak_chunks = maxi(peak_chunks, world._loaded_chunks.size())
		check(world._loaded_chunks.size() <= 25, "Resident chunks grew beyond streaming radius")
		check(world._terrain_jobs.is_empty() and world._pending_chunks.is_empty(), "Terrain jobs retained completed work")
		for chunk in world._spawned_entities_by_chunk:
			for raw in world._spawned_entities_by_chunk[chunk]:
				check(is_instance_valid(raw), "Freed entity retained by loaded chunk")
	var tile: Vector2i = Vector2i(500,500)
	check(world.place_structure(tile, "wood_wall"), "Could not record center structure")
	SignalBus.loot_bag_spawned.emit(actor.position, [{"item_id": "iron_sword", "count": 1, "durability": 12}], 0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.get_save_data())) as Dictionary
	world.load_save_data(saved)
	await settle(world)
	check(world.get_tile(tile).structure_id == "wood_wall", "Structure delta lost on reload")
	check(world._ground_loot.snapshot().size() == 1, "Dropped item lost or duplicated on reload")
	check(int(world._ground_loot.snapshot()[0]["items"][0]["durability"]) == 12, "Reload changed item durability")
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("WORLD_STREAMING_RESULT: %d failures; peak_chunks=%d; max_request_ms=%.1f" % [failures, peak_chunks, max_request_ms])
	get_tree().quit(1 if failures > 0 else 0)
