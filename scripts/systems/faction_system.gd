class_name FactionSystem
extends Node

var _factions: Dictionary = {}
var _rep: Dictionary = {}
var _player_faction: String = ""
var _pending_rumors: Array[Dictionary] = []


func _ready() -> void:
	_factions = GameManager.load_json_indexed("factions.json")
	_reset_to_starting_rep()
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.npc_spawned.connect(_on_npc_spawned)
	SignalBus.npc_killed.connect(_on_npc_killed)
	SignalBus.faction_rep_change_requested.connect(_on_rep_change_requested)
	SignalBus.faction_join_requested.connect(_on_join_requested)
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func get_rep(faction_id: String) -> int:
	return int(_rep.get(faction_id, 0))


func change_rep(faction_id: String, delta: int, reason: String) -> void:
	if not _factions.has(faction_id) or delta == 0:
		return
	var prev_stance: String = get_stance(faction_id)
	var next_val: int = clampi(get_rep(faction_id) + delta, Config.REP_MIN, Config.REP_MAX)
	_rep[faction_id] = next_val
	SignalBus.faction_rep_changed.emit(faction_id, delta, reason)
	var new_stance: String = get_stance(faction_id)
	if new_stance != prev_stance:
		SignalBus.faction_stance_changed.emit(faction_id, new_stance)
	if _player_faction == faction_id and next_val <= Config.STANCE_HOSTILE:
		_player_faction = ""
	SignalBus.faction_rep_snapshot.emit(_rep.duplicate())


func get_stance(faction_id: String) -> String:
	if _player_faction != "" and _player_faction == faction_id:
		return "allied"
	var r: int = get_rep(faction_id)
	if r <= Config.STANCE_HOSTILE:
		return "hostile"
	elif r <= Config.STANCE_UNFRIENDLY:
		return "unfriendly"
	elif r >= Config.STANCE_ALLIED:
		return "allied"
	elif r >= Config.STANCE_FRIENDLY:
		return "friendly"
	return "neutral"


func is_hostile_to_player(entity: Node) -> bool:
	if entity == null or not entity.has_method("get_faction"):
		return false
	var fid: String = str(entity.call("get_faction"))
	if fid == "" or fid == "player":
		return false
	return get_stance(fid) == "hostile"


func join_faction(faction_id: String) -> bool:
	if _player_faction != "" or not _factions.has(faction_id):
		return false
	if get_rep(faction_id) < Config.JOIN_FACTION_REP_REQUIRED:
		return false
	_player_faction = faction_id
	SignalBus.faction_joined.emit(faction_id)
	SignalBus.faction_stance_changed.emit(faction_id, get_stance(faction_id))
	return true


func get_player_faction() -> String:
	return _player_faction


func _reset_to_starting_rep() -> void:
	_rep.clear()
	_player_faction = ""
	_pending_rumors.clear()
	for fid in _factions:
		var def: Dictionary = _factions[fid]
		_rep[fid] = int(def.get("starting_rep", 0))


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		_reset_to_starting_rep()
	SignalBus.faction_rep_snapshot.emit(_rep.duplicate())
	for fid in _rep:
		SignalBus.faction_stance_changed.emit(str(fid), get_stance(str(fid)))


func _on_npc_spawned(_npc_id: String, faction: String, _pos: Vector2) -> void:
	if _factions.has(faction):
		SignalBus.faction_stance_changed.emit(faction, get_stance(faction))


func _on_npc_killed(_npc_id: String, faction: String, killer: String) -> void:
	if killer != "player" or not _factions.has(faction):
		return
	_pending_rumors.append({
		"faction": faction,
		"delta": Config.KILL_REP_PENALTY,
		"reason": "Killed member of " + faction,
		"hours_left": Config.RUMOR_DELAY_HOURS
	})
	var def: Dictionary = _factions[faction]
	for ally in def.get("allied_factions", []):
		_pending_rumors.append({
			"faction": str(ally),
			"delta": int(Config.KILL_REP_PENALTY / 2),
			"reason": "Killed ally of " + str(ally),
			"hours_left": Config.RUMOR_DELAY_HOURS + 2
		})
	for enemy in def.get("enemy_factions", []):
		_pending_rumors.append({
			"faction": str(enemy),
			"delta": 10,
			"reason": "Eliminated enemy of " + str(enemy),
			"hours_left": Config.RUMOR_DELAY_HOURS + 2
		})


func _on_hour_passed(_hour: int) -> void:
	if _pending_rumors.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for rumor in _pending_rumors:
		var left: int = int(rumor.get("hours_left", 1)) - 1
		if left <= 0:
			change_rep(str(rumor.get("faction", "")), int(rumor.get("delta", 0)), str(rumor.get("reason", "Rumor")))
		else:
			rumor["hours_left"] = left
			remaining.append(rumor)
	_pending_rumors = remaining


func _on_rep_change_requested(faction: String, delta: int, reason: String) -> void:
	change_rep(faction, delta, reason)


func _on_join_requested(faction: String) -> void:
	join_faction(faction)


func _on_save_data_requested(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	w["factions"] = {
		"rep": _rep.duplicate(),
		"player_faction": _player_faction,
		"pending_rumors": _pending_rumors.duplicate(true)
	}
	bundle["world"] = w


func _on_save_data_loaded(bundle: Dictionary) -> void:
	_reset_to_starting_rep()
	var w: Dictionary = bundle.get("world", {})
	var f: Dictionary = w.get("factions", {})
	var loaded_rep: Dictionary = f.get("rep", {})
	for k in loaded_rep:
		_rep[str(k)] = int(loaded_rep[k])
	_player_faction = str(f.get("player_faction", ""))
	_pending_rumors.clear()
	for r in f.get("pending_rumors", []):
		if r is Dictionary:
			_pending_rumors.append(r.duplicate())
