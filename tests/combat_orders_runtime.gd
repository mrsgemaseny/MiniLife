extends Node2D

func _ready() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var navigation = preload("res://scripts/core/combat_navigation.gd")
	var blocked: Callable = func(tile: Vector2i) -> bool: return tile.x != 1 or tile.y == 2
	var path: Array[Vector2i] = navigation.find_path(Vector2i.ZERO, Vector2i(3, 0), blocked)
	assert(not path.is_empty(), "Cannot route around wall")
	for tile: Vector2i in path:
		assert(blocked.call(tile), "Route crosses blocked tile")
	var sealed: Callable = func(tile: Vector2i) -> bool: return tile == Vector2i.ZERO
	assert(navigation.find_path(Vector2i.ZERO, Vector2i(3, 0), sealed).is_empty())
	DataRegistry.reload_all()
	var player: Player = load("res://scenes/entities/player.tscn").instantiate()
	add_child(player)
	var enemy: EnemyBase = load("res://scenes/entities/enemy_base.tscn").instantiate()
	enemy.enemy_id = "bandit_scout"
	enemy.position = Vector2(120, 0)
	add_child(enemy)
	assert(enemy.move_speed <= 99.1)
	assert(enemy.stats.max_health == 75)
	player._locked_target = enemy
	assert(player._attack_order_movement().length() > 0)
	player.position = Vector2(100, 0)
	var combat := CombatSystem.new()
	add_child(combat)
	GameManager._state = GameManager.State.PLAYING
	GameManager.resume()
	player.inventory.set_slot(0, {"item_id": "hunting_bow", "count": 1, "durability": 85})
	player.sync_weapon_from_active_slot()
	player.inventory.add_item("arrow", 10)
	assert(player._is_holding_ranged())
	var before: float = enemy.stats.health
	player._attack_cooldown = 0
	player.stats.stamina = player.stats.max_stamina
	player._tick_auto_attack(0.1)
	for i in range(30):
		await get_tree().physics_frame
		if not is_instance_valid(enemy) or enemy.stats.health < before:
			break
	assert(not is_instance_valid(enemy) or enemy.stats.health < before)
	assert(not player._is_charging_bow, "Ranged order started bow charging")
	GameManager._state = GameManager.State.PLAYING
	preload("res://scripts/ui/enemy_inspect.gd").show_target(player, player)
	assert(GameManager.is_paused(), "Inspect does not pause combat")
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("enemy_inspect").size() == 1)
	var inspect_window: Node = get_tree().get_nodes_in_group("enemy_inspect")[0]
	inspect_window.queue_free()
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("enemy_inspect").is_empty())
	assert(not GameManager.is_paused(), "Inspect leaves game paused")
	enemy.set_physics_process(false)
	enemy.position = Vector2(300, 0)
	player.position = Vector2(80, 0)
	player.inventory.set_slot(0, {"item_id": "stone_sword", "count": 1, "durability": 70})
	player.sync_weapon_from_active_slot()
	player._attack_cooldown = 0.0
	player._locked_target = enemy
	var approach_health: float = enemy.stats.health
	for frame in range(240):
		await get_tree().physics_frame
		if enemy.stats.health < approach_health:
			break
	assert(player.position.x > 120, "Player did not approach automatically")
	assert(enemy.stats.health < approach_health, "Approach did not end in melee")
	assert(not player._is_charging_bow)
	enemy.is_permanently_dead = true
	assert(not player._has_attack_order(), "Dead target keeps attack order")
	print("COMBAT_ORDERS_PASS")
	get_tree().quit()
