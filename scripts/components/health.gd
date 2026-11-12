class_name HealthComponent
extends Resource

signal health_changed(current: float, maximum: float)
signal armor_changed(new_armor: float)
signal damage_taken(amount: float, damage_type: String)
signal healed(amount: float)
signal died()
signal limb_changed(limb: String, current_hp: float, max_hp: float, bleeding: bool, fractured: bool)

const LIMBS: Array[String] = []

@export var current: float = 100.0
@export var maximum: float = 100.0
@export var armor: float = 0.0
@export var regeneration_per_sec: float = 0.0

var limbs: Dictionary = {}


func _init() -> void:
	current = maximum
	_sync_legacy_limbs()


func _sync_legacy_limbs() -> void:
	for limb_name in ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]:
		limbs[limb_name] = {
			"current": current,
			"max": maximum,
			"bleeding": false,
			"fractured": false,
			"bandaged": false
		}


func set_armor(new_armor: float) -> void:
	armor = maxf(0.0, new_armor)
	armor_changed.emit(armor)


func get_armor() -> float:
	return armor


func take_damage(amount: float, damage_type: String = "physical", defense: float = -1.0) -> float:
	var effective_defense: float = defense if defense >= 0.0 else armor
	var final_damage: float = amount

	if damage_type == "physical" and effective_defense > 0.0:
		var k: float = 50.0
		var reduction: float = effective_defense / (effective_defense + k)
		final_damage = maxf(amount * (1.0 - reduction), 1.0)

	current = clampf(current - final_damage, 0.0, maximum)
	_sync_legacy_limbs()
	damage_taken.emit(final_damage, damage_type)
	health_changed.emit(current, maximum)

	if current <= 0.0:
		current = 0.0
		died.emit()

	return final_damage


func apply_direct_damage(amount: float, damage_type: String = "physical") -> float:
	var applied: float = minf(maxf(0.0, amount), current)
	if applied <= 0.0:
		return 0.0
	current -= applied
	_sync_legacy_limbs()
	damage_taken.emit(applied, damage_type)
	health_changed.emit(current, maximum)
	if current <= 0.0:
		died.emit()
	return applied


func heal(amount: float) -> float:
	var prev: float = current
	current = clampf(current + amount, 0.0, maximum)
	_sync_legacy_limbs()
	var gained: float = current - prev
	if gained > 0.0:
		healed.emit(gained)
		health_changed.emit(current, maximum)
	return gained


func bandage_all_bleeding() -> int:
	return 0


func get_mobility_multiplier() -> float:
	if current <= maximum * 0.20:
		return 0.85
	return 1.0


func get_manipulation_multiplier() -> float:
	return 1.0


func tick_regen(delta: float) -> void:
	if regeneration_per_sec > 0.0 and current > 0.0 and current < maximum:
		heal(regeneration_per_sec * delta)


func is_alive() -> bool:
	return current > 0.0


func set_max(new_max: float) -> void:
	maximum = maxf(new_max, 1.0)
	current = minf(current, maximum)
	_sync_legacy_limbs()
	health_changed.emit(current, maximum)


func to_dict() -> Dictionary:
	return {
		"current": current,
		"maximum": maximum,
		"armor": armor,
		"regeneration_per_sec": regeneration_per_sec
	}


func from_dict(data: Dictionary) -> void:
	maximum = float(data.get("maximum", 100.0))
	current = clampf(float(data.get("current", maximum)), 0.0, maximum)
	armor = float(data.get("armor", 0.0))
	regeneration_per_sec = float(data.get("regeneration_per_sec", 0.0))
	_sync_legacy_limbs()

