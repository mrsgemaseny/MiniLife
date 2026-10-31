class_name FactionSystem
extends Node

var _factions_defs: Dictionary = {}
var _reputation: Dictionary = {} # faction_id -> int (-100..100)
var _joined_faction: String = ""
var _rumor_network: RumorNetwork = RumorNetwork.new()
var _caravan_director: CaravanDirector = CaravanDirector.new()
var _territory_control: TerritoryControl = TerritoryControl.new()

func _ready() -> void:
	add_to_group("faction_system")
	_load_definitions()
	_connect_signals()
	SignalBus.faction_rep_snapshot.emit(_reputation.duplicate())

func _process(delta: float) -> void:
	if GameManager.is_paused():
		return
	var rumors: Array[Dictionary] = _rumor_network.tick(delta, _factions_defs)
	for r in rumors:
		var source: String = str(r.get("source", ""))
		var target: String = str(r.get("target", ""))
		var rep_delta: int = int(r.get("delta", 0))
		if _reputation.has(target) and rep_delta != 0:
			_apply_rep_internal(target, rep_delta, "rumor_from_" + source)
			SignalBus.rumor_spread.emit(target, "Rumor spread from " + source, rep_delta)

func _load_definitions() -> void:
	_factions_defs = DataRegistry.get_table("factions")
	for fid in _factions_defs.keys():
		var d: Dictionary = _factions_defs[fid]
		_reputation[str(fid)] = int(d.get("starting_rep", d.get("default_reputation", 0)))

func _connect_signals() -> void:
	SignalBus.faction_rep_change_requested.connect(change_reputation)
	SignalBus.faction_join_requested.connect(join_faction)
	SignalBus.npc_killed.connect(_on_npc_killed)
	SignalBus.day_passed.connect(_on_day_passed)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)

func get_reputation(faction_id: String) -> int:
	return int(_reputation.get(faction_id, 0))

func get_all_factions() -> Dictionary:
	return _factions_defs

func get_stance(faction_id: String) -> String:
	var rep: int = get_reputation(faction_id)
	if rep <= Config.STANCE_HOSTILE:
		return "hostile"
	if rep <= Config.STANCE_UNFRIENDLY:
		return "unfriendly"
	if rep < Config.STANCE_FRIENDLY:
		return "neutral"
	if rep < Config.STANCE_ALLIED:
		return "friendly"
	return "allied"

func change_reputation(faction_id: String, delta: int, reason: String = "action") -> void:
	if not _reputation.has(faction_id):
		_reputation[faction_id] = 0
	_apply_rep_internal(faction_id, delta, reason)
	_rumor_network.enqueue_rumor(faction_id, delta, 6.0)

func _apply_rep_internal(faction_id: String, delta: int, reason: String) -> void:
	var old_stance: String = get_stance(faction_id)
	var current: int = int(_reputation.get(faction_id, 0))
	var updated: int = clampi(current + delta, Config.REP_MIN, Config.REP_MAX)
	_reputation[faction_id] = updated
	var new_stance: String = get_stance(faction_id)
	SignalBus.faction_rep_changed.emit(faction_id, delta, reason)
	SignalBus.faction_rep_snapshot.emit(_reputation.duplicate())
	if old_stance != new_stance:
		SignalBus.faction_stance_changed.emit(faction_id, new_stance)

func join_faction(faction_id: String) -> bool:
	if not _factions_defs.has(faction_id):
		return false
	if get_reputation(faction_id) < Config.JOIN_FACTION_REP_REQUIRED:
		SignalBus.notification_posted.emit("Need Friendly reputation (%d+) to join %s." % [Config.JOIN_FACTION_REP_REQUIRED, faction_id])
		return false
	_joined_faction = faction_id
	SignalBus.faction_joined.emit(faction_id)
	SignalBus.notification_posted.emit("Joined faction: %s" % faction_id)
	return true

func get_joined_faction() -> String:
	return _joined_faction

func _on_npc_killed(_npc_id: String, faction_id: String, killer: String) -> void:
	if killer == "player" and not faction_id.is_empty():
		change_reputation(faction_id, Config.KILL_REP_PENALTY, "killed_member")
		if faction_id == "bandits" or faction_id == "raiders":
			change_reputation("village_folk", 6, "slain_raider")
			change_reputation("merchants", 4, "slain_raider")

func _on_day_passed(day: int) -> void:
	var trader_rep: int = get_reputation("merchants")
	if _caravan_director.should_spawn_caravan(day, trader_rep):
		SignalBus.game_event_triggered.emit("trader_visit")

func _on_save_data_requested(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	w["factions"] = {
		"reputation": _reputation.duplicate(),
		"joined_faction": _joined_faction
	}
	bundle["world"] = w

func _on_save_data_loaded(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	var fdata: Dictionary = w.get("factions", {})
	var rep: Dictionary = fdata.get("reputation", {})
	for k in rep.keys():
		_reputation[str(k)] = int(rep[k])
	_joined_faction = str(fdata.get("joined_faction", ""))
	SignalBus.faction_rep_snapshot.emit(_reputation.duplicate())
