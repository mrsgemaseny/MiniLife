class_name EnemyBase
extends CharacterBody2D

enum State { PATROL, CHASE, ATTACK }

@export var enemy_id: String = "wolf"
@export var faction_id: String = "monsters"
@export var respawns: bool = false
@export var stats: StatsComponent
@export var status_effects: StatusEffectsComponent

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var spawn_uid: String = ""
var _state: State = State.PATROL
var _home_pos: Vector2 = Vector2.ZERO
var _patrol_target: Vector2 = Vector2.ZERO
var _patrol_timer: float = 0.0
var _lod_accum: float = 0.0
var _damage: float = 12.0
var _detection_range: float = 220.0
var _leash_range: float = 420.0
var _attack_cooldown: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _loot_table: Dictionary = {}
var _last_attacker: Node = null
var _alive: bool = true


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("combatant")
	_home_pos = global_position
	_patrol_target = _home_pos
	stats = (stats.duplicate() as StatsComponent) if stats != null else StatsComponent.new()
	status_effects = (status_effects.duplicate() as StatusEffectsComponent) if status_effects != null else StatusEffectsComponent.new()
	_apply_enemy_definition()
	stats.depleted.connect(_on_stat_depleted)
	status_effects.effect_damage_tick.connect(func(dmg: float, dtype: String) -> void:
		SignalBus.damage_requested.emit(self, dmg, dtype, null)
	)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	var interval: float = GameManager.compute_sim_lod_interval(global_position)
	var step_delta: float = delta
	if interval > 0.0:
		_lod_accum += delta
		if _lod_accum < interval:
			return
		step_delta = _lod_accum
		_lod_accum = 0.0

	status_effects.tick(step_delta)
	_attack_cooldown = maxf(_attack_cooldown - step_delta, 0.0)
	_tick_fsm(step_delta, interval == 0.0)


func _draw() -> void:
	if animated_sprite != null and animated_sprite.sprite_frames != null:
		return
	draw_circle(Vector2(0.0, -12.0), 10.0, Color(0.9, 0.25, 0.25))


# ICombatant Contract
func take_damage(amount: float, _type: String, source: Node) -> void:
	if not _alive:
		return
	_last_attacker = source
	stats.modify("health", -amount)
	if _alive and source is Node2D:
		_state = State.CHASE


func apply_status(effect: String, duration: float, intensity: float) -> void:
	if _alive:
		status_effects.apply(effect, duration, intensity)


func apply_knockback(impulse: Vector2) -> void:
	_knockback = impulse


func get_defense() -> float:
	return stats.defense


func is_alive() -> bool:
	return _alive


func get_faction() -> String:
	return faction_id


func on_death() -> void:
	if not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	_drop_loot()
	var killer_id: String = "world"
	if _last_attacker != null and is_instance_valid(_last_attacker):
		killer_id = "player" if _last_attacker.is_in_group("player") else str(_last_attacker.name)
	SignalBus.entity_died.emit(self, killer_id)
	queue_free()


func _apply_enemy_definition() -> void:
	var table: Dictionary = GameManager.load_json_indexed("enemies.json")
	if not table.has(enemy_id):
		return
	var def: Dictionary = table[enemy_id]
	var hp: float = float(def.get("hp", 60.0))
	stats.set_max("health", hp)
	stats.health = hp
	stats.move_speed = float(def.get("speed", 150.0))
	_damage = float(def.get("damage", 12.0))
	respawns = bool(def.get("respawns", false))
	_loot_table = def.get("loot_table", {}).duplicate()


func _tick_fsm(dt: float, is_near: bool) -> void:
	if status_effects.is_action_blocked():
		velocity = Vector2.ZERO
		return
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var dist_to_player: float = global_position.distance_to(player.global_position) if player != null else 99999.0

	match _state:
		State.PATROL:
			if player != null and dist_to_player <= _detection_range:
				_state = State.CHASE
				return
			_patrol_timer -= dt
			if _patrol_timer <= 0.0 or global_position.distance_to(_patrol_target) <= 10.0:
				_patrol_target = _home_pos + Vector2(randf_range(-140.0, 140.0), randf_range(-140.0, 140.0))
				if nav_agent != null:
					nav_agent.target_position = _patrol_target
				_patrol_timer = randf_range(3.0, 6.0)
			_move_toward(_patrol_target, dt, is_near)
		State.CHASE:
			if player == null or dist_to_player > _leash_range:
				_state = State.PATROL
				_patrol_target = _home_pos
				return
			if dist_to_player <= Config.MELEE_RANGE:
				_state = State.ATTACK
				return
			_move_toward(player.global_position, dt, is_near)
		State.ATTACK:
			if player == null or dist_to_player > Config.MELEE_RANGE * 1.25:
				_state = State.CHASE
				return
			velocity = Vector2.ZERO
			if _attack_cooldown <= 0.0:
				_attack_cooldown = 1.1
				SignalBus.damage_requested.emit(player, _damage, "physical", self)


func _move_toward(target: Vector2, dt: float, is_near: bool) -> void:
	var to_target: Vector2 = target - global_position
	var d: float = to_target.length()
	if d <= 6.0:
		velocity = Vector2.ZERO
		return
	var spd: float = stats.move_speed * status_effects.get_speed_multiplier()
	var dir: Vector2 = to_target / d
	if is_near:
		velocity = dir * spd + _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, Config.KNOCKBACK_DECAY * dt)
		move_and_slide()
	else:
		global_position += dir * minf(spd * dt, d)


func _drop_loot() -> void:
	if _last_attacker == null or not is_instance_valid(_last_attacker):
		return
	var inv: InventoryComponent = _last_attacker.get("inventory") as InventoryComponent
	if inv == null:
		return
	var gold_drop: int = int(_loot_table.get("gold", 0))
	if gold_drop > 0:
		inv.add_gold(gold_drop)
	var items_map: Dictionary = _loot_table.get("items", {})
	for item_id in items_map:
		inv.add_item(str(item_id), int(items_map[item_id]))


func _on_stat_depleted(stat: String) -> void:
	if stat == "health":
		on_death()
