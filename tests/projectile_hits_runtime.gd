extends Node

class Target extends Node2D:
	var stats := StatsComponent.new()
	var skills := SkillsComponent.new()
	var hit_count: int = 0
	func is_alive() -> bool:
		return true
	func take_damage(amount: float, _type: String, _source: Node) -> void:
		assert(amount > 0.0)
		hit_count += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var combat := CombatSystem.new()
	add_child(combat)
	var shooter: Player = load("res://scenes/entities/player.tscn").instantiate()
	add_child(shooter)
	shooter.set_physics_process(false)
	var target := Target.new()
	target.position = Vector2(100, 0)
	target.skills.set_level("dodge", 100)
	add_child(target)
	target.add_to_group("combatant")
	for type: String in ["arrow", "javelins"]:
		for shot: int in range(64):
			var projectile := ProjectileEntity.new()
			projectile.item_id = type
			projectile.shooter = shooter
			projectile.position = Vector2(0, -12)
			projectile.direction = Vector2.RIGHT
			projectile.speed = 1000
			projectile.max_range = 500
			add_child(projectile)
			projectile.set_process(false)
			var before: int = target.hit_count
			projectile._process(0.2)
			assert(target.hit_count == before + 1, "A physical projectile hit must not roll a second miss")
	var before_miss: int = target.hit_count
	var off_target := ProjectileEntity.new()
	off_target.shooter = shooter
	off_target.position = Vector2(0, 150)
	off_target.direction = Vector2.RIGHT
	off_target.speed = 1000
	add_child(off_target)
	off_target.set_process(false)
	off_target._process(0.2)
	assert(target.hit_count == before_miss, "An actual trajectory miss must not damage the target")
	shooter.inventory.set_slot(0, {"item_id": "javelins", "count": 1, "durability": -1})
	shooter.active_hotbar_index = 0
	shooter.sync_weapon_from_active_slot()
	var base_damage: float = float(shooter.equipment.get_weapon_stats().get("damage", 0.0))
	var expected: float = base_damage * (1.0 + shooter.skills.get_level("ranged") * Config.SKILL_DAMAGE_BONUS_PER_LEVEL)
	var shots: Array[float] = []
	SignalBus.projectile_fired.connect(func(_p: Vector2, _d: Vector2, _s: float, damage: float, _t: String, _o: Node, _r: float): shots.append(damage))
	shooter._is_charging_bow = true
	shooter._bow_charge_time = shooter.MAX_BOW_CHARGE_TIME
	shooter._release_bow_shot()
	assert(shots.size() == 1 and is_equal_approx(shots[0], expected), "The last javelin retains the thrown weapon's damage")
	print("PROJECTILE_HITS_PASS: 128 physical hits, no random re-roll; real miss preserved; final javelin stats retained")
	get_tree().quit()
