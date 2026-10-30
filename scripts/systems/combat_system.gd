class_name CombatSystem
extends Node

const DAMAGE_TYPES: Array[String] = ["physical", "fire", "poison", "cold", "true"]

var _projectile_layer: ProjectileSystem = null


func _ready() -> void:
	_projectile_layer = ProjectileSystem.new()
	add_child(_projectile_layer)
	SignalBus.damage_requested.connect(_on_damage_requested)
	SignalBus.status_apply_requested.connect(_on_status_apply_requested)


func resolve_damage(raw_amount: float, damage_type: String, target: Node) -> float:
	return MeleeResolver.compute_mitigated_damage(raw_amount, damage_type, target)


func apply_knockback(target: Node, source: Node, strength: float = Config.KNOCKBACK_SPEED) -> void:
	if target == null or source == null:
		return
	if not (target is Node2D) or not (source is Node2D):
		return
	if not target.has_method("apply_knockback"):
		return
	var dir: Vector2 = ((target as Node2D).global_position - (source as Node2D).global_position).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	target.call("apply_knockback", dir * strength)


func _on_damage_requested(target: Node, amount: float, damage_type: String, source: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return
	if source != null and damage_type == "physical":
		var hit_chance: float = MeleeResolver.compute_hit_chance(source, target)
		if randf() > hit_chance:
			return
	var valid_type: String = damage_type if DAMAGE_TYPES.has(damage_type) else "physical"
	var final_damage: float = resolve_damage(amount, valid_type, target)
	if target.has_method("take_damage"):
		target.call("take_damage", final_damage, valid_type, source)
	if source != null and valid_type == "physical":
		apply_knockback(target, source)


func _on_status_apply_requested(target: Node, effect: String, duration: float, intensity: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return
	if target.has_method("apply_status"):
		target.call("apply_status", effect, duration, intensity)
		SignalBus.status_effect_applied.emit(target, effect, duration)
