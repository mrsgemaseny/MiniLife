extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var shots: Array = []
	var melee_hits: Array = []
	SignalBus.projectile_fired.connect(func(origin: Vector2, direction: Vector2, speed: float, damage: float, damage_type: String, shooter: Node, range_px: float) -> void:
		shots.append({"origin": origin, "direction": direction, "speed": speed, "damage": damage, "type": damage_type, "shooter": shooter, "range": range_px}))
	SignalBus.damage_requested.connect(func(_target: Node, _damage: float, _type: String, _source: Node) -> void:
		melee_hits.append(true))
	var target := Node2D.new()
	target.add_to_group("player")
	target.position = Vector2(100, 0)
	add_child(target)
	for id: String in ["bandit_novice_archer", "bandit_ranger", "bandit_crossbow"]:
		var enemy := EnemyBase.new()
		enemy.enemy_id = id
		add_child(enemy)
		enemy.target_entity = target
		enemy.current_state = EnemyBase.State.ATTACK
		enemy._tick_fsm(0.1)
		assert(shots.size() == 1)
		assert(shots[0]["shooter"] == enemy)
		assert(shots[0]["range"] == enemy.attack_range)
		assert(melee_hits.is_empty())
		shots.clear()
		enemy.queue_free()
	print("BANDIT_RANGED_PASS: all three ranged archetypes fire projectiles")
	get_tree().quit()
