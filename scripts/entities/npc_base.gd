class_name NPCBase
extends CharacterBody2D

enum State { IDLE, PATROL, TRADE, FLEE, ATTACK, GIVE_QUEST }

@export var npc_id: String = "merchant_common"
@export var faction_id: String = "merchants"
@export var role: String = "trader"
@export var dialogue_tree_id: String = "merchant_default"
@export var stats: StatsComponent
@export var inventory: InventoryComponent
@export var status_effects: StatusEffectsComponent

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var spawn_uid: String = ""
var _state: State = State.IDLE
var _state_timer: float = 2.0
var _lod_accum: float = 0.0
var _home_pos: Vector2 = Vector2.ZERO
var _patrol_target: Vector2 = Vector2.ZERO
var _threat: Node2D = null
var _last_attacker_id: String = "world"
var _attack_cooldown: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _stance_to_player: String = "neutral"
var _alive: bool = true
var _npc_def: Dictionary = {}


func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")
	add_to_group("combatant")
	_home_pos = global_position
	_patrol_target = _home_pos
	stats = (stats.duplicate() as StatsComponent) if stats != null else StatsComponent.new()
	inventory = (inventory.duplicate() as InventoryComponent) if inventory != null else InventoryComponent.new()
	status_effects = (status_effects.duplicate() as StatusEffectsComponent) if status_effects != null else StatusEffectsComponent.new()

	var table: Dictionary = GameManager.load_json_indexed("npcs.json")
	_npc_def = table.get(npc_id, {})
	if not _npc_def.is_empty():
		faction_id = str(_npc_def.get("faction", faction_id))
		role = str(_npc_def.get("role", role))
		dialogue_tree_id = str(_npc_def.get("dialogue_tree_id", dialogue_tree_id))
		_restock_inventory()

	stats.depleted.connect(_on_stat_depleted)
	status_effects.effect_damage_tick.connect(func(dmg: float, dtype: String) -> void:
		SignalBus.damage_requested.emit(self, dmg, dtype, null)
	)
	SignalBus.day_passed.connect(_on_day_passed)
	SignalBus.faction_stance_changed.connect(_on_faction_stance_changed)
	SignalBus.npc_kill_requested.connect(_on_npc_kill_requested)
	SignalBus.npc_spawned.emit(npc_id, faction_id, global_position)


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
	_state_timer -= step_delta
	_tick_fsm(step_delta, interval == 0.0)


func _draw() -> void:
	if animated_sprite != null and animated_sprite.sprite_frames != null:
		return
	draw_circle(Vector2(0.0, -12.0), 9.0, Color(0.25, 0.85, 0.45))


func interact(actor: Node) -> void:
	if not _alive or _stance_to_player == "hostile":
		return
	SignalBus.npc_interacted.emit(npc_id)
	if role == "trader":
		_state = State.TRADE
		_state_timer = 15.0
	elif role == "quest_giver":
		_state = State.GIVE_QUEST
		_state_timer = 15.0
	if dialogue_tree_id != "" and actor != null:
		SignalBus.dialogue_started.emit(npc_id, dialogue_tree_id)


# ICombatant Contract
func take_damage(amount: float, _type: String, source: Node) -> void:
	if not _alive:
		return
	if source != null:
		_last_attacker_id = "player" if source.is_in_group("player") else str(source.name)
		if source.is_in_group("player"):
			SignalBus.faction_rep_change_requested.emit(faction_id, Config.ASSAULT_REP_PENALTY, "Attacked " + npc_id)
		if source is Node2D:
			_threat = source as Node2D
	stats.modify("health", -amount)
	if not _alive:
		return
	if role == "guard" or _stance_to_player == "hostile":
		_state = State.ATTACK
	elif stats.health < stats.max_health * 0.35 or role == "trader":
		_state = State.FLEE
		_state_timer = 6.0


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
	SignalBus.entity_died.emit(self, _last_attacker_id)
	SignalBus.npc_killed.emit(npc_id, faction_id, _last_attacker_id)
	queue_free()


func _tick_fsm(dt: float, is_near: bool) -> void:
	if status_effects.is_action_blocked():
		velocity = Vector2.ZERO
		return
	match _state:
		State.IDLE:
			velocity = Vector2.ZERO
			if _stance_to_player == "hostile" and is_near:
				var p: Node2D = get_tree().get_first_node_in_group("player") as Node2D
				if p != null and global_position.distance_to(p.global_position) <= 180.0:
					_threat = p
					_state = State.ATTACK
					return
			if _state_timer <= 0.0:
				var offset: Vector2 = Vector2(randf_range(-160.0, 160.0), randf_range(-160.0, 160.0))
				_patrol_target = _home_pos + offset
				if nav_agent != null:
					nav_agent.target_position = _patrol_target
				_state = State.PATROL
				_state_timer = 6.0
		State.PATROL:
			if _move_toward_point(_patrol_target, dt, is_near) or _state_timer <= 0.0:
				_state = State.IDLE
				_state_timer = randf_range(2.0, 5.0)
		State.TRADE, State.GIVE_QUEST:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_state = State.IDLE
				_state_timer = 3.0
		State.FLEE:
			if _threat == null or not is_instance_valid(_threat) or _state_timer <= 0.0:
				_state = State.IDLE
				_state_timer = 3.0
				return
			var away: Vector2 = global_position + (global_position - _threat.global_position).normalized() * 220.0
			_move_toward_point(away, dt, is_near)
		State.ATTACK:
			if _threat == null or not is_instance_valid(_threat):
				_state = State.IDLE
				_state_timer = 2.0
				return
			var dist: float = global_position.distance_to(_threat.global_position)
			if dist > 280.0:
				_threat = null
				_state = State.PATROL
				_patrol_target = _home_pos
				return
			if dist <= Config.MELEE_RANGE:
				velocity = Vector2.ZERO
				if _attack_cooldown <= 0.0:
					_attack_cooldown = 1.0
					SignalBus.damage_requested.emit(_threat, 10.0, "physical", self)
			else:
				_move_toward_point(_threat.global_position, dt, is_near)


func _move_toward_point(target: Vector2, dt: float, is_near: bool) -> bool:
	var to_target: Vector2 = target - global_position
	var dist: float = to_target.length()
	if dist <= 8.0:
		velocity = Vector2.ZERO
		return true
	var spd: float = stats.move_speed * status_effects.get_speed_multiplier()
	var dir: Vector2 = to_target / dist
	if is_near:
		velocity = dir * spd + _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, Config.KNOCKBACK_DECAY * dt)
		move_and_slide()
	else:
		var step: float = minf(spd * dt, dist)
		global_position += dir * step
	return global_position.distance_to(target) <= 8.0


func _restock_inventory() -> void:
	inventory.slots.clear()
	var pool: Array = _npc_def.get("inventory_pool", [])
	for entry in pool:
		if entry is Dictionary:
			var item_id: String = str(entry.get("item_id", ""))
			var min_c: int = int(entry.get("min", 1))
			var max_c: int = int(entry.get("max", 3))
			var count: int = randi_range(min_c, maxi(min_c, max_c))
			inventory.add_item(item_id, count)
		elif entry is String:
			inventory.add_item(str(entry), 2)
	inventory.gold = 200


func _on_day_passed(_day_number: int) -> void:
	if role == "trader":
		_restock_inventory()


func _on_faction_stance_changed(faction: String, stance: String) -> void:
	if faction == faction_id:
		_stance_to_player = stance


func _on_npc_kill_requested(npc_uid: String, _reason: String) -> void:
	if npc_uid == npc_id or (spawn_uid != "" and npc_uid == spawn_uid):
		on_death()


func _on_stat_depleted(stat: String) -> void:
	if stat == "health":
		on_death()
