class_name EnemyBase
extends CharacterBody2D

enum State { PATROL, CHASE, ATTACK }

@export var enemy_id: String = "wolf"
@export var faction_id: String = "wildlife"
@export var aggro_range: float = 170.0
@export var attack_range: float = 42.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.2
@export var move_speed: float = 115.0
@export var no_respawn: bool = true
@export var stats: StatsComponent

var spawn_uid: String = ""
var display_name: String = "Hostile"
var current_state: State = State.PATROL
var target_entity: Node2D = null
var sim_tier: int = SimulationBubble.Tier.FULL
var is_permanently_dead: bool = false
var _cooldown_timer: float = 0.0
var _sim_timer: float = 0.0
var _wander_dir: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0
var _enemy_def: Dictionary = {}

func _ready() -> void:
	y_sort_enabled = true
	add_to_group("enemy")
	add_to_group("combatant")
	if stats == null:
		stats = StatsComponent.new()
	_apply_enemy_definition()
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	queue_redraw()

func _apply_enemy_definition() -> void:
	_enemy_def = DataRegistry.get_enemy(enemy_id)
	if _enemy_def.is_empty():
		return
	display_name = str(_enemy_def.get("name", enemy_id))
	faction_id = str(_enemy_def.get("faction", _enemy_def.get("faction_id", faction_id)))
	var max_hp: float = float(_enemy_def.get("health", _enemy_def.get("max_health", 60.0)))
	stats.set_max("health", max_hp)
	stats.health = max_hp
	stats.defense = float(_enemy_def.get("defense", 0.0))
	move_speed = float(_enemy_def.get("speed", _enemy_def.get("move_speed", move_speed)))
	aggro_range = float(_enemy_def.get("aggro_range", aggro_range))
	attack_range = float(_enemy_def.get("attack_range", attack_range))
	attack_damage = float(_enemy_def.get("damage", _enemy_def.get("attack_damage", attack_damage)))
	attack_cooldown = float(_enemy_def.get("attack_cooldown", attack_cooldown))

func _physics_process(delta: float) -> void:
	if is_permanently_dead or GameManager.is_paused():
		return

	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)

	if sim_tier == SimulationBubble.Tier.FULL:
		_tick_fsm(delta)
	else:
		_sim_timer += delta
		var interval: float = SimulationBubble.get_tick_interval(sim_tier)
		if _sim_timer >= interval:
			_tick_fsm(_sim_timer)
			_sim_timer = 0.0

func _tick_fsm(delta: float) -> void:
	if target_entity == null or not is_instance_valid(target_entity):
		target_entity = get_tree().get_first_node_in_group("player") as Node2D

	match current_state:
		State.PATROL:
			_wander_timer -= delta
			if _wander_timer <= 0.0:
				var angle: float = randf() * TAU
				_wander_dir = Vector2(cos(angle), sin(angle) * 0.5).normalized()
				_wander_timer = randf_range(2.0, 4.5)
			velocity = _wander_dir * (move_speed * 0.35)
			if sim_tier == SimulationBubble.Tier.FULL:
				move_and_slide()
			if target_entity != null and global_position.distance_to(target_entity.global_position) <= aggro_range:
				current_state = State.CHASE
		State.CHASE:
			if target_entity == null:
				current_state = State.PATROL
				return
			var dist: float = global_position.distance_to(target_entity.global_position)
			if dist > aggro_range * 1.6:
				current_state = State.PATROL
			elif dist <= attack_range:
				current_state = State.ATTACK
			else:
				velocity = (target_entity.global_position - global_position).normalized() * move_speed
				if sim_tier == SimulationBubble.Tier.FULL:
					move_and_slide()
				else:
					global_position += velocity * delta
		State.ATTACK:
			velocity = Vector2.ZERO
			if target_entity == null:
				current_state = State.PATROL
				return
			var dist: float = global_position.distance_to(target_entity.global_position)
			if dist > attack_range * 1.25:
				current_state = State.CHASE
			elif _cooldown_timer <= 0.0:
				_cooldown_timer = attack_cooldown
				SignalBus.damage_requested.emit(target_entity, attack_damage, "physical", self)

func is_alive() -> bool:
	return not is_permanently_dead and stats.health > 0.0

func apply_knockback(vel: Vector2) -> void:
	velocity = vel
	move_and_slide()

func apply_status(_effect: String, _duration: float, _intensity: float) -> void:
	pass

func take_damage(amount: float, _damage_type: String = "physical", source: Node = null) -> void:
	if is_permanently_dead:
		return
	stats.modify("health", -amount)
	if source is Node2D:
		target_entity = source as Node2D
		current_state = State.CHASE
	queue_redraw()
	if stats.health <= 0.0:
		_handle_death(source)

func _handle_death(killer: Node) -> void:
	is_permanently_dead = true
	_spawn_loot_drop()
	var killer_id: String = "player" if (killer != null and killer.is_in_group("player")) else "world"
	SignalBus.npc_killed.emit(enemy_id, faction_id, killer_id)
	SignalBus.entity_died.emit(self, killer_id)
	if bool(_enemy_def.get("is_boss", false)) or enemy_id.ends_with("_boss"):
		SignalBus.boss_defeated.emit(enemy_id, global_position)
	queue_free()

func _spawn_loot_drop() -> void:
	var drops: Array[Dictionary] = LootTableRoller.roll_enemy_loot(_enemy_def)
	if drops.is_empty():
		return
	var bag: LootBag = LootBag.new()
	bag.items = drops
	bag.gold = randi_range(3, 12) if faction_id == "raiders" else 0
	bag.global_position = global_position
	if get_parent() != null:
		get_parent().add_child(bag)

func _on_player_tile_changed(player_tile: Vector2i) -> void:
	var my_tile: Vector2i = Config.iso_to_world(global_position)
	sim_tier = SimulationBubble.compute_lod_tier(player_tile, my_tile)

func _draw() -> void:
	draw_circle(Vector2(0, 3), 9.0, Color(0.0, 0.0, 0.0, 0.35))
	var is_beast: bool = (faction_id == "wildlife")
	if is_beast:
		var fur_col: Color = Color(0.48, 0.44, 0.40) if enemy_id.find("wolf") != -1 else Color(0.42, 0.28, 0.18)
		draw_rect(Rect2(-10, -12, 20, 10), fur_col, true)
		draw_circle(Vector2(9, -10), 5.5, fur_col.lightened(0.1))
		draw_circle(Vector2(11, -11), 1.5, Color(0.95, 0.22, 0.18))
	else:
		draw_rect(Rect2(-5, -7, 4, 8), Color(0.22, 0.18, 0.16), true)
		draw_rect(Rect2(1, -7, 4, 8), Color(0.22, 0.18, 0.16), true)
		draw_rect(Rect2(-7, -20, 14, 13), Color(0.72, 0.22, 0.20), true)
		draw_circle(Vector2(0, -25), 5.5, Color(0.86, 0.72, 0.58))

	if stats != null:
		var ratio: float = clampf(stats.health / maxf(1.0, stats.max_health), 0.0, 1.0)
		draw_rect(Rect2(-14, -36, 28, 4), Color(0.12, 0.12, 0.12, 0.85), true)
		draw_rect(Rect2(-14, -36, 28.0 * ratio, 4), Color(0.88, 0.22, 0.20, 0.95), true)
