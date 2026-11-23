class_name ReputationSystem
extends Node

const RESPECTED_THRESHOLD: int = 40
const NOTABLE_THRESHOLD: int = 40

var _local: Dictionary = {}
var _world: int = 0
var _honor: int = 0
var _chain_completed: bool = false
var _vassal_faction: String = ""
var _champion: bool = false
var _commander: bool = false
var _status: String = "Nobody"

func _ready() -> void:
	add_to_group("reputation_system")
	SignalBus.local_rep_change_requested.connect(change_local)
	SignalBus.world_rep_change_requested.connect(change_world)
	SignalBus.honor_change_requested.connect(change_honor)
	SignalBus.quest_chain_completed.connect(_on_quest_chain_completed)
	SignalBus.vassal_pledge_confirmed.connect(_on_vassal_pledge_confirmed)
	SignalBus.significant_combat_won.connect(_on_significant_combat_won)
	SignalBus.commander_encounter_completed.connect(_on_commander_encounter_completed)
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)

func get_local(settlement_id: String) -> int:
	return int(_local.get(settlement_id, 0))

func get_world_reputation() -> int:
	return _world

func get_honor() -> int:
	return _honor

func get_status() -> String:
	return _status

func get_vassal_faction() -> String:
	return _vassal_faction

func get_faction_reputation(faction_id: String) -> int:
	var factions: FactionSystem = get_tree().get_first_node_in_group("faction_system") as FactionSystem
	return factions.get_reputation(faction_id) if factions != null else 0

func change_local(settlement_id: String, delta: int, reason: String = "action") -> void:
	if settlement_id.is_empty() or delta == 0:
		return
	var old: int = get_local(settlement_id)
	var updated: int = clampi(old + delta, Config.REP_MIN, Config.REP_MAX)
	if old == updated:
		return
	_local[settlement_id] = updated
	SignalBus.local_rep_changed.emit(settlement_id, updated, reason)
	_refresh_status()

func change_world(delta: int, _reason: String = "action") -> void:
	if delta == 0:
		return
	var updated: int = clampi(_world + delta, Config.REP_MIN, Config.REP_MAX)
	if updated == _world:
		return
	_world = updated
	SignalBus.player_world_rep_changed.emit(float(_world))
	_refresh_status()

func change_honor(delta: int, reason: String = "decision") -> void:
	if delta == 0:
		return
	var updated: int = clampi(_honor + delta, Config.REP_MIN, Config.REP_MAX)
	if updated == _honor:
		return
	_honor = updated
	SignalBus.player_honor_changed.emit(_honor, reason)

func _on_quest_chain_completed(_quest_id: String) -> void:
	_chain_completed = true
	_refresh_status()

func _on_vassal_pledge_confirmed(faction_id: String) -> void:
	if faction_id.is_empty() or not _vassal_faction.is_empty():
		return
	_vassal_faction = faction_id
	_refresh_status()

func _on_significant_combat_won() -> void:
	_champion = true
	_refresh_status()

func _on_commander_encounter_completed() -> void:
	_commander = true
	_refresh_status()

func _refresh_status() -> void:
	var next: String = "Nobody"
	if _chain_completed:
		next = "Known"
	for value: Variant in _local.values():
		if int(value) >= RESPECTED_THRESHOLD:
			next = "Respected"
			break
	if _world >= NOTABLE_THRESHOLD:
		next = "Notable"
	if not _vassal_faction.is_empty():
		next = "Vassal"
	if _champion:
		next = "Champion"
	if _commander:
		next = "Commander"
	if next != _status:
		_status = next
		SignalBus.player_status_changed.emit(_status)

func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if not is_new:
		return
	_local.clear()
	_world = 0
	_honor = 0
	_chain_completed = false
	_vassal_faction = ""
	_champion = false
	_commander = false
	_status = "Nobody"
	SignalBus.player_status_changed.emit(_status)
	SignalBus.player_world_rep_changed.emit(0.0)

func _on_save_data_requested(bundle: Dictionary) -> void:
	var data: Dictionary = bundle.get("world", {})
	data["player_reputation"] = {
		"local": _local.duplicate(), "world": _world, "honor": _honor,
		"chain_completed": _chain_completed, "vassal_faction": _vassal_faction,
		"champion": _champion, "commander": _commander
	}
	bundle["world"] = data

func _on_save_data_loaded(bundle: Dictionary) -> void:
	var data: Dictionary = (bundle.get("world", {}) as Dictionary).get("player_reputation", {})
	_local.clear()
	for settlement_id: String in (data.get("local", {}) as Dictionary):
		_local[settlement_id] = clampi(int(data["local"][settlement_id]), Config.REP_MIN, Config.REP_MAX)
	_world = clampi(int(data.get("world", 0)), Config.REP_MIN, Config.REP_MAX)
	_honor = clampi(int(data.get("honor", 0)), Config.REP_MIN, Config.REP_MAX)
	_chain_completed = bool(data.get("chain_completed", false))
	_vassal_faction = str(data.get("vassal_faction", ""))
	_champion = bool(data.get("champion", false))
	_commander = bool(data.get("commander", false))
	_status = ""
	_refresh_status()
	SignalBus.player_world_rep_changed.emit(float(_world))
