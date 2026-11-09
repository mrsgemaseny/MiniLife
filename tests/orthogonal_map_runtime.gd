extends Node

const Migration = preload("res://scripts/core/map_projection_migration.gd")
var failures: int = 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	check(Config.world_to_iso(Vector2i.RIGHT) == Vector2(48,0), "Tile X points right")
	check(Config.world_to_iso(Vector2i.DOWN) == Vector2(0,48), "Tile Y points down")
	for tile: Vector2i in [Vector2i(-3,-2),Vector2i.ZERO,Vector2i(500,500),Vector2i(999,999)]:
		for offset: Vector2 in [Vector2.ZERO,Vector2(-23,-23),Vector2(23,23)]:
			check(Config.iso_to_world(Config.world_to_iso(tile)+offset) == tile, "Square tile click inverse")
	var bundle: Dictionary = {"meta": {}, "player": {"position": [64,64]}, "world": {"ground_loot": [{"x":64,"y":64}], "alife": {"agents": [{"world_position":[64,64],"tile":[3,1]}], "travel_routes":{"a":{"position":[3,1]}}}, "chunk_deltas":{"0_0":{"animals":{"a":{"position":[64,64]}}}}}}
	Migration.migrate_bundle(bundle)
	check(bundle.player.position == [144.0,48.0], "Legacy player keeps original tile")
	check(bundle.world.ground_loot[0].x == 144.0 and bundle.world.ground_loot[0].y == 48.0, "Legacy loot keeps location")
	check(bundle.world.alife.agents[0].world_position == [144.0,48.0] and bundle.world.alife.travel_routes.a.position == [3,1], "Agent screen positions migrate while route tile coordinates stay intact")
	var migrated: String = JSON.stringify(bundle)
	Migration.migrate_bundle(bundle)
	check(JSON.stringify(bundle) == migrated, "Migration does not run twice")
	var chunk: Dictionary = Migration.migrate_chunk({"enemies":{"a":{"position":[64,64]}}})
	check(chunk.enemies.a.position == [144.0,48.0], "Separate legacy chunk migrates independently of slot metadata")
	check(Migration.migrate_chunk(chunk).enemies.a.position == [144.0,48.0], "Tagged chunk is not migrated twice")
	var tileset: TileSet = ProceduralTileset.build_isometric_tileset()
	check(tileset.tile_shape == TileSet.TILE_SHAPE_SQUARE and tileset.tile_size == Vector2i(48,48), "Runtime tileset is square")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(12345,"orthogonal_readonly_test")
	var player: Player = main.get_node("World/Player") as Player
	player.set_physics_process(false)
	for pair: Array in [["move_up",Vector2.UP],["move_right",Vector2.RIGHT],["move_down",Vector2.DOWN],["move_left",Vector2.LEFT]]:
		Input.action_press(str(pair[0]))
		check(player._read_movement_input().is_equal_approx(pair[1]), "WASD follows screen axes")
		Input.action_release(str(pair[0]))
	for frame: int in range(50):
		await get_tree().process_frame
	check(Config.iso_to_world(player.global_position) == player.current_tile, "Spawn and grid position agree")
	var building: BuildingSystem = BuildingSystem.instance
	GameManager.debug_god_mode = true
	var placed: bool = false
	for offset: Vector2i in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var tile: Vector2i = player.current_tile + offset
		if building.can_place_block("torch",tile):
			building._on_build_requested("torch",tile,player)
			var structure: StructureEntity = building._placed_structures.get(Config.vec2i_to_key(tile)) as StructureEntity
			placed = structure != null and structure.global_position == Config.world_to_iso(tile)
			break
	check(placed, "Building snaps to square grid through real placement pipeline")
	GameManager.debug_god_mode = false
	SignalBus.ui_close_all_requested.emit()
	main.get_node("UILayer/MainMenu").hide()
	GameManager.resume()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/orthogonal_map_ingame.png")
	var atlas: WorldMapUI = main.get_node("UILayer/WorldMapUI") as WorldMapUI
	atlas.open_panel()
	for frame: int in range(300):
		atlas._process(0.016)
		if atlas._map_row == atlas.MAP_SAMPLES:
			break
	check(atlas._map_image.get_size() == Vector2i(512,512) and atlas._map_row == atlas.MAP_SAMPLES, "World atlas completes as a square")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = atlas._pan_offset + Vector2(40,60) * (2.0*atlas.MAP_TILE_SCALE*atlas._zoom)
	atlas._on_canvas_gui_input(motion)
	check(atlas._hovered_tile == Vector2i(40,60), "Atlas pointer matches unrotated tile coordinates")
	atlas.center_on_player()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/orthogonal_atlas.png")
	atlas.close_panel()
	GameManager._state = GameManager.State.BOOT
	print("ORTHOGONAL MAP TESTS: failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
