class_name HealthComponent
extends Resource

signal health_changed(current: float, maximum: float)
signal limb_changed(limb: String, current_hp: float, max_hp: float, bleeding: bool, fractured: bool)
signal damage_taken(amount: float, damage_type: String)
signal healed(amount: float)
signal died()

const LIMBS: Array[String] = ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]
const LIMB_MAX_HP: Dictionary = {
	"head": 45.0,
	"torso": 85.0,
	"left_arm": 40.0,
	"right_arm": 40.0,
	"left_leg": 45.0,
	"right_leg": 45.0
}

@export var current: float = 100.0
@export var maximum: float = 100.0
@export var regeneration_per_sec: float = 0.0

var limbs: Dictionary = {}


func _init() -> void:
	reset_limbs()


func reset_limbs() -> void:
	limbs.clear()
	for limb_name in LIMBS:
		var mx: float = float(LIMB_MAX_HP.get(limb_name, 50.0))
		limbs[limb_name] = {
			"current": mx,
			"max": mx,
			"bleeding": false,
			"fractured": false,
			"bandaged": false
		}


func take_damage(amount: float, damage_type: String = "physical", defense: float = 0.0) -> float:
	var final_damage: float = amount
	if damage_type == "physical" and defense > 0.0:
		var reduction: float = defense / (defense + Config.ARMOR_K_CONSTANT)
		final_damage = maxf(amount * (1.0 - reduction), 1.0)
	current = clampf(current - final_damage, 0.0, maximum)
	_apply_random_limb_damage(final_damage, damage_type)
	damage_taken.emit(final_damage, damage_type)
	health_changed.emit(current, maximum)
	if current <= 0.0 or _is_vital_limb_destroyed():
		current = 0.0
		died.emit()
	return final_damage


func heal(amount: float) -> float:
	var prev: float = current
	current = clampf(current + amount, 0.0, maximum)
	for limb_name in limbs:
		var l: Dictionary = limbs[limb_name]
		l["current"] = clampf(float(l.get("current", 0.0)) + amount * 0.5, 0.0, float(l.get("max", 50.0)))
		l["bleeding"] = false
		limbs[limb_name] = l
	var gained: float = current - prev
	if gained > 0.0:
		healed.emit(gained)
		health_changed.emit(current, maximum)
	return gained


func bandage_all_bleeding() -> int:
	var count: int = 0
	for limb_name in limbs:
		var l: Dictionary = limbs[limb_name]
		if bool(l.get("bleeding", false)):
			l["bleeding"] = false
			l["bandaged"] = true
			limbs[limb_name] = l
			count += 1
			limb_changed.emit(str(limb_name), float(l["current"]), float(l["max"]), false, bool(l["fractured"]))
	return count


func get_mobility_multiplier() -> float:
	var mult: float = 1.0
	for leg in ["left_leg", "right_leg"]:
		var l: Dictionary = limbs.get(leg, {})
		var ratio: float = float(l.get("current", 45.0)) / maxf(float(l.get("max", 45.0)), 1.0)
		if ratio < 0.5 or bool(l.get("fractured", false)):
			mult *= 0.72
	return mult


func get_manipulation_multiplier() -> float:
	var mult: float = 1.0
	for arm in ["left_arm", "right_arm"]:
		var l: Dictionary = limbs.get(arm, {})
		var ratio: float = float(l.get("current", 40.0)) / maxf(float(l.get("max", 40.0)), 1.0)
		if ratio < 0.5 or bool(l.get("fractured", false)):
			mult *= 0.75
	return mult


func tick_regen(delta: float) -> void:
	if regeneration_per_sec > 0.0 and current > 0.0 and current < maximum:
		heal(regeneration_per_sec * delta)


func is_alive() -> bool:
	return current > 0.0 and not _is_vital_limb_destroyed()


func set_max(new_max: float) -> void:
	maximum = maxf(new_max, 1.0)
	current = minf(current, maximum)
	health_changed.emit(current, maximum)


func _apply_random_limb_damage(dmg: float, dtype: String) -> void:
	if limbs.is_empty():
		reset_limbs()
	var target_limb: String = LIMBS[randi() % LIMBS.size()]
	var l: Dictionary = limbs[target_limb]
	var cur: float = clampf(float(l.get("current", 40.0)) - dmg * 0.65, 0.0, float(l.get("max", 40.0)))
	l["current"] = cur
	if dtype == "physical" and dmg >= 14.0 and randf() < 0.35:
		l["bleeding"] = true
	if cur <= float(l.get("max", 40.0)) * 0.25 and (target_limb.ends_with("leg") or target_limb.ends_with("arm")):
		l["fractured"] = true
	limbs[target_limb] = l
	limb_changed.emit(target_limb, cur, float(l["max"]), bool(l["bleeding"]), bool(l["fractured"]))


func _is_vital_limb_destroyed() -> bool:
	var head: Dictionary = limbs.get("head", {})
	var torso: Dictionary = limbs.get("torso", {})
	return float(head.get("current", 45.0)) <= 0.0 or float(torso.get("current", 85.0)) <= 0.0


func to_dict() -> Dictionary:
	return {
		"current": current,
		"maximum": maximum,
		"regeneration_per_sec": regeneration_per_sec,
		"limbs": limbs.duplicate(true)
	}


func from_dict(data: Dictionary) -> void:
	maximum = float(data.get("maximum", 100.0))
	current = clampf(float(data.get("current", maximum)), 0.0, maximum)
	regeneration_per_sec = float(data.get("regeneration_per_sec", 0.0))
	reset_limbs()
	var saved_limbs: Dictionary = data.get("limbs", {})
	for k in saved_limbs:
		if limbs.has(str(k)) and saved_limbs[k] is Dictionary:
			limbs[str(k)] = (saved_limbs[k] as Dictionary).duplicate()
