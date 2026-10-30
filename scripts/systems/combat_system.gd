class_name CombatSystem
extends Node

const DAMAGE_TYPES: Array[String] = ["physical", "fire", "poison", "cold", "true"]


func _ready() -> void:
	SignalBus.damage_requested.connect(_on_damage_requested)
	SignalBus.status_apply_requested.connect(_on_status_apply_requested)


func resolve_damage(raw_amount: float, damage_type: String, target: Node) -> float:
	var amount: float = maxf(raw_amount, 0.0)
	if amount <= 0.0 or target == null:
		return 0.0
	if damage_type == "true":
		return amount
	var defense: float = 0.0
	if target.has_method("get_defense"):
		defense = maxf(float(target.call("get_defense")), 0.0)
	if damage_type == "physical" and defense > 0.0:
		var reduction: float = defense / (defense + Config.ARMOR_K_CONSTANT)
		return maxf(amount * (1.0 - reduction), 1.0)
	return amount


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
