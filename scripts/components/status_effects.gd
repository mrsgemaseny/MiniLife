class_name StatusEffectsComponent
extends Resource

signal effect_applied(effect: String, duration: float)
signal effect_expired(effect: String)
signal effect_damage_tick(damage: float, damage_type: String)

const EFFECT_RULES: Dictionary = {
	"burning": {"duration": 5.0, "tick_interval": 1.0, "damage": 4.0, "damage_type": "fire", "speed_mult": 1.0, "blocks_attack": false},
	"poisoned": {"duration": 10.0, "tick_interval": 2.0, "damage": 3.0, "damage_type": "poison", "speed_mult": 0.9, "blocks_attack": false},
	"frozen": {"duration": 3.0, "tick_interval": 0.0, "damage": 0.0, "damage_type": "cold", "speed_mult": 0.5, "blocks_attack": false},
	"stunned": {"duration": 1.2, "tick_interval": 0.0, "damage": 0.0, "damage_type": "physical", "speed_mult": 0.0, "blocks_attack": true},
	"bleeding": {"duration": 8.0, "tick_interval": 1.5, "damage": 2.5, "damage_type": "true", "speed_mult": 0.92, "blocks_attack": false},
	"infected": {"duration": 20.0, "tick_interval": 4.0, "damage": 2.0, "damage_type": "poison", "speed_mult": 0.85, "blocks_attack": false},
	"well_fed": {"duration": 30.0, "tick_interval": 5.0, "damage": -1.5, "damage_type": "true", "speed_mult": 1.08, "blocks_attack": false},
	"exhausted": {"duration": 15.0, "tick_interval": 0.0, "damage": 0.0, "damage_type": "true", "speed_mult": 0.7, "blocks_attack": false}
}

var _active: Dictionary = {}


func apply(effect: String, duration: float = -1.0, intensity: float = 1.0) -> void:
	if not EFFECT_RULES.has(effect):
		return
	var rule: Dictionary = EFFECT_RULES[effect]
	var dur: float = duration if duration > 0.0 else float(rule["duration"])
	_active[effect] = {
		"remaining": dur,
		"intensity": maxf(intensity, 0.1),
		"tick_accum": 0.0
	}
	effect_applied.emit(effect, dur)


func remove(effect: String) -> void:
	if _active.has(effect):
		_active.erase(effect)
		effect_expired.emit(effect)


func clear_all() -> void:
	var keys: Array = _active.keys()
	for k in keys:
		remove(str(k))


func has_effect(effect: String) -> bool:
	return _active.has(effect)


func tick(delta: float) -> void:
	if _active.is_empty():
		return
	var expired: Array[String] = []
	for effect_key in _active:
		var effect: String = str(effect_key)
		var state: Dictionary = _active[effect]
		var rule: Dictionary = EFFECT_RULES.get(effect, {})
		var remaining: float = float(state.get("remaining", 0.0))
		var step: float = minf(delta, remaining)
		remaining -= delta
		state["remaining"] = remaining
		var interval: float = float(rule.get("tick_interval", 0.0))
		if interval > 0.0:
			var accum: float = float(state.get("tick_accum", 0.0)) + step
			while accum >= interval:
				accum -= interval
				var dmg: float = float(rule.get("damage", 0.0)) * float(state.get("intensity", 1.0))
				var dtype: String = str(rule.get("damage_type", "true"))
				if dmg > 0.0:
					effect_damage_tick.emit(dmg, dtype)
			state["tick_accum"] = accum
		_active[effect] = state
		if remaining <= 0.0:
			expired.append(effect)
	for e in expired:
		remove(e)


func get_speed_multiplier() -> float:
	var mult: float = 1.0
	for effect_key in _active:
		var rule: Dictionary = EFFECT_RULES.get(str(effect_key), {})
		mult *= float(rule.get("speed_mult", 1.0))
	return clampf(mult, 0.0, 1.35)


func is_action_blocked() -> bool:
	for effect_key in _active:
		var rule: Dictionary = EFFECT_RULES.get(str(effect_key), {})
		if bool(rule.get("blocks_attack", false)):
			return true
	return false


func get_active_names() -> Array[String]:
	var names: Array[String] = []
	for k in _active:
		names.append(str(k))
	return names


func to_dict() -> Dictionary:
	return _active.duplicate(true)


func from_dict(data: Dictionary) -> void:
	_active.clear()
	for k in data:
		var entry: Variant = data[k]
		if entry is Dictionary and EFFECT_RULES.has(str(k)):
			_active[str(k)] = {
				"remaining": float(entry.get("remaining", 1.0)),
				"intensity": float(entry.get("intensity", 1.0)),
				"tick_accum": float(entry.get("tick_accum", 0.0))
			}
