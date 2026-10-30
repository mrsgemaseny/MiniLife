class_name EventSystem
extends Node

var _events: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hours_since_roll: int = 0
var _structure_tiles: Dictionary = {}
var _player_biome: String = "plains"
var _exploration_percent: float = 0.0
var _last_triggered_day: Dictionary = {}


func _ready() -> void:
	_events = GameManager.load_json_indexed("events.json")
	_rng.randomize()
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.structure_built.connect(_on_structure_built)
	SignalBus.structure_restored.connect(_on_structure_built)
	SignalBus.structure_destroyed.connect(_on_structure_destroyed)
	SignalBus.player_biome_changed.connect(_on_player_biome_changed)
	SignalBus.exploration_progress_changed.connect(_on_exploration_progress_changed)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func get_eligible_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for eid in _events:
		var def: Dictionary = _events[eid]
		if is_event_eligible(def):
			out.append(def)
	return out


func is_event_eligible(def: Dictionary) -> bool:
	var eid: String = str(def.get("id", ""))
	if eid == "":
		return false
	var cur_day: int = GameManager.get_day()
	var cooldown_days: int = int(def.get("cooldown_days", 2))
	if _last_triggered_day.has(eid):
		if bool(def.get("once", false)):
			return false
		if cur_day - int(_last_triggered_day[eid]) < cooldown_days:
			return false

	var cond: Dictionary = def.get("conditions", {})
	if cur_day < int(cond.get("min_day", 1)):
		return false
	if bool(cond.get("requires_structures", false)) and _structure_tiles.is_empty():
		return false
	var req_biome: Variant = cond.get("biome", "")
	if req_biome is String and str(req_biome) != "" and str(req_biome) != _player_biome:
		return false
	elif req_biome is Array and not (req_biome as Array).is_empty() and not (req_biome as Array).has(_player_biome):
		return false
	var min_exp: float = float(cond.get("min_exploration_percent", 0.0))
	if _exploration_percent < min_exp:
		return false
	return true


func trigger_event(event_id: String) -> bool:
	if not _events.has(event_id):
		return false
	var def: Dictionary = _events[event_id]
	_last_triggered_day[event_id] = GameManager.get_day()
	SignalBus.game_event_triggered.emit(event_id)
	var effect: Variant = def.get("effect", {})
	if effect is Dictionary and not (effect as Dictionary).is_empty():
		SignalBus.event_effect_requested.emit(effect)
	elif effect is Array:
		for eff in effect:
			if eff is Dictionary:
				SignalBus.event_effect_requested.emit(eff)
	var msg: String = str(def.get("message", "Event: " + event_id))
	SignalBus.notification_posted.emit(msg)
	return true


func _on_game_started(world_seed: int, _slot: String, is_new: bool) -> void:
	_rng.seed = world_seed ^ 0x5A17E
	if is_new:
		_hours_since_roll = 0
		_structure_tiles.clear()
		_last_triggered_day.clear()


func _on_hour_passed(_hour: int) -> void:
	_hours_since_roll += 1
	if _hours_since_roll < Config.EVENT_ROLL_INTERVAL_HOURS:
		return
	_hours_since_roll = 0
	if _rng.randf() > Config.EVENT_TRIGGER_CHANCE:
		return
	var candidates: Array[Dictionary] = get_eligible_events()
	if candidates.is_empty():
		return
	var total_weight: float = 0.0
	for c in candidates:
		total_weight += maxf(float(c.get("weight", 1.0)), 0.01)
	var pick: float = _rng.randf() * total_weight
	var accum: float = 0.0
	for c in candidates:
		accum += maxf(float(c.get("weight", 1.0)), 0.01)
		if pick <= accum:
			trigger_event(str(c.get("id", "")))
			return


func _on_structure_built(_structure_id: String, tile_pos: Vector2i) -> void:
	_structure_tiles[Config.vec2i_to_key(tile_pos)] = true


func _on_structure_destroyed(_structure_id: String, tile_pos: Vector2i) -> void:
	_structure_tiles.erase(Config.vec2i_to_key(tile_pos))


func _on_player_biome_changed(biome_id: String) -> void:
	_player_biome = biome_id


func _on_exploration_progress_changed(percent: float) -> void:
	_exploration_percent = percent


func _on_save_data_requested(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	w["events"] = {
		"hours_since_roll": _hours_since_roll,
		"last_triggered_day": _last_triggered_day.duplicate()
	}
	bundle["world"] = w


func _on_save_data_loaded(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	var ev: Dictionary = w.get("events", {})
	_hours_since_roll = int(ev.get("hours_since_roll", 0))
	_last_triggered_day = ev.get("last_triggered_day", {}).duplicate()
