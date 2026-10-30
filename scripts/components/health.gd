class_name HealthComponent
extends Resource

signal health_changed(current: float, maximum: float)
signal damage_taken(amount: float, damage_type: String)
signal healed(amount: float)
signal died()

@export var current: float = 100.0
@export var maximum: float = 100.0
@export var regeneration_per_sec: float = 0.0


func take_damage(amount: float, damage_type: String = "physical", defense: float = 0.0) -> float:
	var final_damage: float = amount
	if damage_type == "physical" and defense > 0.0:
		var reduction: float = defense / (defense + Config.ARMOR_K_CONSTANT)
		final_damage = maxf(amount * (1.0 - reduction), 1.0)
	current = clampf(current - final_damage, 0.0, maximum)
	damage_taken.emit(final_damage, damage_type)
	health_changed.emit(current, maximum)
	if current <= 0.0:
		died.emit()
	return final_damage


func heal(amount: float) -> float:
	var prev: float = current
	current = clampf(current + amount, 0.0, maximum)
	var gained: float = current - prev
	if gained > 0.0:
		healed.emit(gained)
		health_changed.emit(current, maximum)
	return gained


func tick_regen(delta: float) -> void:
	if regeneration_per_sec > 0.0 and current > 0.0 and current < maximum:
		heal(regeneration_per_sec * delta)


func is_alive() -> bool:
	return current > 0.0


func set_max(new_max: float) -> void:
	maximum = maxf(new_max, 1.0)
	current = minf(current, maximum)
	health_changed.emit(current, maximum)


func to_dict() -> Dictionary:
	return {
		"current": current,
		"maximum": maximum,
		"regeneration_per_sec": regeneration_per_sec
	}


func from_dict(data: Dictionary) -> void:
	maximum = float(data.get("maximum", 100.0))
	current = clampf(float(data.get("current", maximum)), 0.0, maximum)
	regeneration_per_sec = float(data.get("regeneration_per_sec", 0.0))
