extends Node

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	var first_save: Dictionary = {}
	var capture_initial_save: Callable = func(_slot: String) -> void:
		SignalBus.save_data_requested.emit(first_save)
	SignalBus.save_requested.connect(capture_initial_save)
	GameManager.start_new_game(12345, "endgame_readonly_test")
	SignalBus.save_requested.disconnect(capture_initial_save)
	var world: WorldSystem = main.get_node("World")
	var player: Player = main.get_node("World/Player")
	var victories: Array[bool] = []
	SignalBus.endgame_victory_achieved.connect(func() -> void: victories.append(true))
	var passed: bool = first_save.get("world", {}).get("quests", {}).get("active", {}).has("cull_wolves_01")
	passed = await _check_campaign(world, player, victories) and passed
	print("ENDGAME_WORLD_RESULT: ", "PASS" if passed else "FAIL")
	GameManager._state = GameManager.State.BOOT
	get_tree().quit(0 if passed else 1)

func _check_campaign(world: WorldSystem, player: Player, victories: Array[bool]) -> bool:
	for frame: int in range(50):
		await get_tree().process_frame
	if world._boss_sites.has("dungeon") or not world._boss_sites.has("alpha_wolf_den"):
		return false
	var den: Vector2i = world._boss_sites["alpha_wolf_den"]
	world._load_chunk(Config.tile_to_chunk(den))
	var alpha: EnemyBase = _find_boss("alpha_wolf_boss")
	if alpha == null:
		return false
	alpha.take_damage(99999.0, "physical", player)
	if not world._boss_sites.has("dungeon"):
		return false
	var stronghold: Vector2i = world._boss_sites["dungeon"]
	var chunk: Vector2i = Config.tile_to_chunk(stronghold)
	if not world.get_discovered_pois().has(Config.vec2i_to_key(stronghold)):
		return false
	world._load_chunk(chunk)
	var khan: EnemyBase = _find_boss("warlord_khan_boss")
	if khan == null:
		return false
	khan.take_damage(99999.0, "physical", player)
	await get_tree().process_frame
	world._unload_chunk(chunk)
	world._load_chunk(chunk)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.get_save_data()))
	world.load_save_data(saved)
	await get_tree().process_frame
	world._load_chunk(chunk)
	return victories.size() == 1 and _find_boss("warlord_khan_boss") == null \
		and world._boss_sites.get("dungeon") == stronghold

func _find_boss(id: String) -> EnemyBase:
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase and enemy.enemy_id == id:
			return enemy
	return null
