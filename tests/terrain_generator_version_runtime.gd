extends Node

const SEED: int = 42819
const SEAM_TILE: Vector2i = Vector2i(16000, 4995)
# Biomes and resources from the version 2 generator at commit b8dcb05.
const LEGACY_CHUNK_HASH: String = "591e757861433a9669d164f4d11b72f7e641588f0d8bbc950c58ed478d8478df"

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var world: WorldSystem = scene.get_node("World")
	var current_slot: String = "__terrain_current_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var legacy_slot: String = "__terrain_legacy_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var version: int = TerrainGenerator.SETTLEMENT_BASE_GENERATOR_VERSION if "--v4" in OS.get_cmdline_user_args() \
		else TerrainGenerator.LEGACY_GENERATOR_VERSION
	_check(_test_slot_switch(scene, save_system, world, current_slot, legacy_slot, version), "Legacy slot did not load")
	save_system.delete_slot(current_slot)
	save_system.delete_slot(legacy_slot)
	if failures == 0:
		print("TERRAIN_GENERATOR_VERSION_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _test_slot_switch(scene: Node, save_system: SaveSystem, world: WorldSystem, current_slot: String, legacy_slot: String, version: int) -> bool:
	var chunk: Vector2i = Config.tile_to_chunk(SEAM_TILE)
	var current_path: String = SaveSystem._slot_dir(current_slot)
	var legacy_path: String = SaveSystem._slot_dir(legacy_slot)
	GameManager.start_new_game(SEED, current_slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	var current_chunk: Dictionary = world.get_terrain().generate_chunk(chunk)
	_check(JSON.stringify(current_chunk).sha256_text() != LEGACY_CHUNK_HASH, "New games still use version 2 terrain")
	_check(not FileAccess.file_exists(SaveSystem._chunk_file_path(current_slot, chunk)), "An untouched chunk was written")

	var meta: Dictionary = SaveSystem._read_json(current_path + "meta.json")
	var player: Dictionary = SaveSystem._read_json(current_path + "player.json")
	var save_data: Dictionary = SaveSystem._read_json(current_path + "world.json")
	_check(int(save_data.get("generator_version", 0)) == TerrainGenerator.GENERATOR_VERSION, "New slot stored the wrong version")
	save_data["generator_version"] = version
	var legacy_context: AlifeWorldContext = AlifeWorldContext.new(version)
	legacy_context.seed_world(SEED, Config.START_HOUR)
	WorldSeedBuilder.populate(legacy_context)
	var codec: AlifeAgentSaveDelta = AlifeAgentSaveDelta.new()
	codec.capture(legacy_context, version)
	save_data["alife"] = codec.encode(legacy_context)
	if version == TerrainGenerator.SETTLEMENT_BASE_GENERATOR_VERSION:
		_check(codec._fingerprint == "37bdb4bcf55c13061a8732616b6418d2d97f1856d86a579ec4a870894ce10c1b",
			"Version 4 A-Life population changed compared with the released generator")
	var expected_hash: String = LEGACY_CHUNK_HASH
	if version != TerrainGenerator.LEGACY_GENERATOR_VERSION:
		var legacy_terrain: TerrainGenerator = TerrainGenerator.new(SEED, version)
		expected_hash = JSON.stringify(legacy_terrain.generate_chunk(chunk)).sha256_text()
		_check(legacy_terrain.get_graph().river_sample(Vector2(18000.5, 5379.5)).w == 0.0,
			"Version 4 terrain loaded the authored river")
	var position: Vector2 = Config.world_to_iso(SEAM_TILE)
	player["position"] = [position.x, position.y]
	DirAccess.make_dir_recursive_absolute(legacy_path)
	if not SaveSystem._write_json(legacy_path + "meta.json", meta) \
			or not SaveSystem._write_json(legacy_path + "player.json", player) \
			or not SaveSystem._write_json(legacy_path + "world.json", save_data):
		return false
	var delta: Dictionary = {"structures": {Config.vec2i_to_key(SEAM_TILE): "wood_wall"}, "map_projection": Config.MAP_PROJECTION}
	DirAccess.make_dir_recursive_absolute(legacy_path + "chunks")
	if not SaveSystem._write_json(SaveSystem._chunk_file_path(legacy_slot, chunk), delta) or not save_system.load_slot(legacy_slot):
		return false
	_check(world.get_terrain().get_version() == version, "World used the wrong terrain version")
	_check(JSON.stringify(world.get_terrain().generate_chunk(chunk)).sha256_text() == expected_hash,
		"Legacy terrain differs after loading, or reused the current world's quota cache")
	_check(world.get_tile(SEAM_TILE).structure_id == "wood_wall", "Legacy chunk delta did not apply")
	_check(WorldSimulation.last_load_error.is_empty(), "Legacy A-Life state failed to load")

	var map: WorldMapUI = scene.get_node("UILayer/WorldMapUI")
	map.open_panel()
	_check(map._map_terrain.get_version() == version, "Local map used the wrong version")
	map.close_panel()
	var job := ChunkTerrainJob.new()
	job.start(SEED, chunk, world.get_terrain().get_version())
	_check(JSON.stringify(job.collect()).sha256_text() == expected_hash, "Chunk worker used the wrong version")
	_check(save_system.save_slot(legacy_slot)
		and int(SaveSystem._read_json(legacy_path + "world.json").get("generator_version", 0)) == version,
		"Saving an old slot changed its generation version")

	_check(save_system.load_slot(current_slot), "Could not reload the current version slot")
	_check(world.get_terrain().generate_chunk(chunk) == current_chunk, "Switching to version 2 changed version 3 terrain")
	return true


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("TERRAIN_VERSION_FAILURE: " + message)
