extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _fire_input(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	for i: int in range(30):
		await get_tree().physics_frame
	press.pressed = false
	Input.parse_input_event(press)
	for i: int in range(5):
		await get_tree().physics_frame

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(12345, "ranged_input_readonly")
	main.get_node("UILayer/MainMenu").close_menu()
	SignalBus.ui_close_all_requested.emit()
	GameManager.resume()
	var player: Player = main.get_node("World/Player") as Player
	var shots: Array[Dictionary] = []
	SignalBus.projectile_fired.connect(func(_origin: Vector2, _direction: Vector2, _speed: float, _damage: float, _type: String, _shooter: Node, _range: float) -> void:
		if _shooter == player:
			shots.append({"id": player.get_last_fired_projectile_id()})
	)
	for i: int in range(10):
		await get_tree().process_frame
	var screen_point: Vector2 = player.get_global_transform_with_canvas().origin + Vector2(200, -80)
	player.inventory.set_slot(0, {"item_id": "hunting_bow", "count": 1, "durability": 85})
	player.inventory.set_slot(8, {"item_id": "arrow", "count": 10, "durability": -1})
	player.active_hotbar_index = 0
	player.sync_weapon_from_active_slot()
	_check(player._is_holding_bow(), "Bow is not equipped")
	await _fire_input(screen_point)
	_check(shots.size() == 1 and shots[0].id == "arrow", "Holding and releasing LMB does not fire bow")
	_check(player.inventory.count_of("arrow") == 9, "Bow does not spend exactly one arrow")
	var enemy: EnemyBase = load("res://scenes/entities/enemy_base.tscn").instantiate() as EnemyBase
	enemy.enemy_id = "bandit_scout"
	enemy.global_position = player.global_position + Vector2(160, 0)
	main.get_node("World").add_child(enemy)
	enemy.set_physics_process(false)
	var enemy_screen: Vector2 = enemy.get_global_transform_with_canvas().origin
	_check(player._get_enemy_under_cursor() == null, "Cursor remained over enemy before aiming")
	var motion := InputEventMouseMotion.new()
	motion.position = enemy_screen
	motion.global_position = enemy_screen
	Input.parse_input_event(motion)
	await get_tree().process_frame
	_check(InteractionPicker.pick(get_tree(), enemy.global_position, player) == enemy, "Enemy cannot be selected at its world position")
	player._attack_cooldown = 0.0
	await _fire_input(enemy_screen)
	_check(shots.size() == 2 and shots[1].id == "arrow", "Clicking an enemy does not fire bow")
	_check(player.inventory.count_of("arrow") == 8, "Bow target click does not spend one arrow")
	player._attack_cooldown = 0.0
	player.inventory.set_slot(0, {"item_id": "javelins", "count": 2, "durability": -1})
	player.sync_weapon_from_active_slot()
	_check(player._is_holding_javelin(), "Javelins are not equipped")
	await _fire_input(screen_point)
	_check(shots.size() == 3 and shots[2].id == "javelins", "Holding and releasing LMB does not throw a javelin")
	_check(int(player.inventory.get_slot(0).get("count", 0)) == 1, "Throwing does not spend exactly one javelin")
	player._attack_cooldown = 0.0
	await _fire_input(enemy_screen)
	_check(shots.size() == 4 and shots[3].id == "javelins", "Clicking an enemy does not throw a javelin")
	_check(player.inventory.get_slot(0).is_empty(), "Final javelin was not consumed")
	player.inventory.set_slot(0, {"item_id": "javelins", "count": 1, "durability": -1})
	player.sync_weapon_from_active_slot()
	player._attack_cooldown = 0.0
	player._locked_target = enemy
	player.perform_attack()
	_check(shots.size() == 5 and shots[4].id == "javelins", "Ordered javelin attack did not throw a javelin")
	_check(player.inventory.get_slot(0).is_empty(), "Ordered javelin attack did not consume the stack")
	print("PLAYER_RANGED_INPUT: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
