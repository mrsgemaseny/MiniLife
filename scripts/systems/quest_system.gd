class_name QuestSystem
extends Node

var _quests_defs: Dictionary = {}
var _active_quests: Dictionary = {} # quest_id -> Dictionary state
var _completed_quests: Dictionary = {}
var _failed_quests: Dictionary = {}

func _ready() -> void:
	_quests_defs = DataRegistry.get_table("quests")
	_connect_signals()
	call_deferred("_start_initial_quest")

func _start_initial_quest() -> void:
	if _active_quests.is_empty() and _completed_quests.is_empty():
		var first_id: String = "tutorial_survival" if _quests_defs.has("tutorial_survival") else ""
		if first_id.is_empty() and not _quests_defs.is_empty():
			first_id = str(_quests_defs.keys()[0])
		if not first_id.is_empty():
			start_quest(first_id, "system")

func _connect_signals() -> void:
	SignalBus.quest_start_requested.connect(start_quest)
	SignalBus.quest_turn_in_requested.connect(complete_quest)
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.npc_killed.connect(_on_npc_killed)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.structure_built.connect(_on_structure_built)
	SignalBus.resource_harvested.connect(_on_resource_harvested)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)

func start_quest(quest_id: String, _giver_id: String = "") -> bool:
	if _active_quests.has(quest_id) or _completed_quests.has(quest_id):
		return false
	if not _quests_defs.has(quest_id):
		return false
	var def: Dictionary = _quests_defs[quest_id]
	var req_count: int = int(def.get("required_count", 1))
	var objs: Array = def.get("objectives", [])
	if not objs.is_empty() and objs[0] is Dictionary:
		req_count = int((objs[0] as Dictionary).get("target", req_count))

	var state: Dictionary = {
		"id": quest_id,
		"title": str(def.get("title", def.get("name", quest_id))),
		"type": str(def.get("type", "survive")),
		"target_id": str(def.get("target_id", "")),
		"time_limit": float(def.get("time_limit_hours", -1.0)),
		"elapsed_hours": 0.0,
		"progress": {"current": 0, "required": maxi(1, req_count)}
	}
	_active_quests[quest_id] = state
	SignalBus.quest_started.emit(quest_id)
	_emit_snapshot()
	return true

func advance_quest(quest_id: String, delta_count: int = 1) -> void:
	if not _active_quests.has(quest_id):
		return
	var state: Dictionary = _active_quests[quest_id]
	var prog: Dictionary = state.get("progress", {"current": 0, "required": 1})
	var cur: int = clampi(int(prog.get("current", 0)) + delta_count, 0, int(prog.get("required", 1)))
	prog["current"] = cur
	state["progress"] = prog
	_active_quests[quest_id] = state
	SignalBus.quest_objective_updated.emit(quest_id, prog)
	_emit_snapshot()
	if cur >= int(prog.get("required", 1)):
		complete_quest(quest_id)

func complete_quest(quest_id: String) -> void:
	if not _active_quests.has(quest_id):
		return
	var state: Dictionary = _active_quests[quest_id]
	_active_quests.erase(quest_id)
	_completed_quests[quest_id] = state
	SignalBus.quest_completed.emit(quest_id)

	var def: Dictionary = _quests_defs.get(quest_id, {})
	var rewards: Dictionary = def.get("rewards", {})
	SignalBus.quest_reward_granted.emit(rewards)

	var rep_rewards: Dictionary = rewards.get("reputation", {})
	for fid in rep_rewards.keys():
		SignalBus.faction_rep_change_requested.emit(str(fid), int(rep_rewards[fid]), "quest_" + quest_id)

	var gold_reward: int = int(rewards.get("gold", 0))
	if gold_reward > 0:
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and player.get("inventory") is InventoryComponent:
			(player.get("inventory") as InventoryComponent).add_gold(gold_reward)

	var next_quest: String = str(def.get("next_quest_id", ""))
	if not next_quest.is_empty():
		start_quest(next_quest, "chain")
	_emit_snapshot()
	SignalBus.notification_posted.emit("Quest Completed: %s" % str(state.get("title", quest_id)))

func fail_quest(quest_id: String, reason: String = "timeout") -> void:
	if not _active_quests.has(quest_id):
		return
	var state: Dictionary = _active_quests[quest_id]
	_active_quests.erase(quest_id)
	_failed_quests[quest_id] = state
	SignalBus.quest_failed.emit(quest_id, reason)
	_emit_snapshot()

func _emit_snapshot() -> void:
	SignalBus.quest_log_changed.emit({
		"active": _active_quests.duplicate(true),
		"completed": _completed_quests.duplicate(true),
		"failed": _failed_quests.duplicate(true)
	})

func _on_hour_passed(_hour: int) -> void:
	var to_fail: Array[String] = []
	for qid in _active_quests.keys():
		var state: Dictionary = _active_quests[qid]
		var tlimit: float = float(state.get("time_limit", -1.0))
		if tlimit > 0.0:
			var elapsed: float = float(state.get("elapsed_hours", 0.0)) + 1.0
			state["elapsed_hours"] = elapsed
			_active_quests[qid] = state
			if elapsed >= tlimit:
				to_fail.append(str(qid))
	for qid in to_fail:
		fail_quest(qid, "expired")
	if not to_fail.is_empty():
		_emit_snapshot()

func _on_npc_killed(_npc_id: String, _faction: String, killer: String) -> void:
	if killer != "player":
		return
	for qid in _active_quests.keys():
		advance_quest(str(qid), 1)

func _on_item_crafted(_item_id: String) -> void:
	for qid in _active_quests.keys():
		advance_quest(str(qid), 1)

func _on_structure_built(_structure_id: String, _tile_pos: Vector2i) -> void:
	for qid in _active_quests.keys():
		advance_quest(str(qid), 1)

func _on_resource_harvested(_resource_id: String, amount: int, _tile_pos: Vector2i) -> void:
	for qid in _active_quests.keys():
		advance_quest(str(qid), maxi(1, amount))

func _on_save_data_requested(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	w["quests"] = {
		"active": _active_quests.duplicate(true),
		"completed": _completed_quests.duplicate(true),
		"failed": _failed_quests.duplicate(true)
	}
	bundle["world"] = w

func _on_save_data_loaded(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	var q: Dictionary = w.get("quests", {})
	_active_quests = q.get("active", {}).duplicate(true)
	_completed_quests = q.get("completed", {}).duplicate(true)
	_failed_quests = q.get("failed", {}).duplicate(true)
	_emit_snapshot()
