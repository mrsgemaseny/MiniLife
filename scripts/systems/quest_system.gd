class_name QuestSystem
extends Node

class Quest extends RefCounted:
	var id: String = ""
	var type: String = "fetch"
	var giver_id: String = ""
	var giver_faction: String = ""
	var objective: Dictionary = {}
	var reward: Dictionary = {}
	var time_limit: float = -1.0
	var fail_consequence: Dictionary = {}
	var is_chain: bool = false
	var next_quest_id: String = ""
	var progress: Dictionary = {"current": 0, "required": 1}
	var elapsed_hours: float = 0.0
	var status: String = "active"

	func is_ready_to_complete() -> bool:
		return int(progress.get("current", 0)) >= int(progress.get("required", 1))

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"type": type,
			"giver_id": giver_id,
			"giver_faction": giver_faction,
			"objective": objective.duplicate(),
			"reward": reward.duplicate(),
			"time_limit": time_limit,
			"fail_consequence": fail_consequence.duplicate(),
			"is_chain": is_chain,
			"next_quest_id": next_quest_id,
			"progress": progress.duplicate(),
			"elapsed_hours": elapsed_hours,
			"status": status
		}

	static func from_dict(d: Dictionary) -> Quest:
		var q: Quest = Quest.new()
		q.id = str(d.get("id", ""))
		q.type = str(d.get("type", "fetch"))
		q.giver_id = str(d.get("giver_id", ""))
		q.giver_faction = str(d.get("giver_faction", ""))
		q.objective = d.get("objective", {}).duplicate()
		q.reward = d.get("reward", {}).duplicate()
		q.time_limit = float(d.get("time_limit", -1.0))
		q.fail_consequence = d.get("fail_consequence", {}).duplicate()
		q.is_chain = bool(d.get("is_chain", false))
		q.next_quest_id = str(d.get("next_quest_id", ""))
		var req: int = int(q.objective.get("count", 1))
		q.progress = d.get("progress", {"current": 0, "required": req}).duplicate()
		q.elapsed_hours = float(d.get("elapsed_hours", 0.0))
		q.status = str(d.get("status", "active"))
		return q

var _quest_defs: Dictionary = {}
var _active: Dictionary = {}
var _completed: Dictionary = {}
var _failed: Dictionary = {}


func _ready() -> void:
	_quest_defs = GameManager.load_json_indexed("quests.json")
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.quest_start_requested.connect(_on_quest_start_requested)
	SignalBus.quest_turn_in_requested.connect(_on_quest_turn_in_requested)
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.entity_died.connect(_on_entity_died)
	SignalBus.poi_discovered.connect(_on_poi_discovered)
	SignalBus.structure_built.connect(_on_structure_built)
	SignalBus.inventory_changed.connect(_on_inventory_changed)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func start_quest(quest_id: String, giver_id: String) -> bool:
	if _active.has(quest_id) or _completed.has(quest_id):
		return false
	if not _quest_defs.has(quest_id):
		return false
	var def: Dictionary = _quest_defs[quest_id]
	var q: Quest = Quest.from_dict(def)
	if giver_id != "":
		q.giver_id = giver_id
	q.status = "active"
	q.elapsed_hours = 0.0
	_active[quest_id] = q
	SignalBus.quest_started.emit(quest_id)
	_emit_log_snapshot()
	return true


func update_objective(quest_id: String, key: String, value: Variant) -> void:
	if not _active.has(quest_id):
		return
	var q: Quest = _active[quest_id]
	q.progress[key] = value
	if q.is_ready_to_complete():
		q.status = "ready"
	SignalBus.quest_objective_updated.emit(quest_id, q.progress.duplicate())
	_emit_log_snapshot()


func complete_quest(quest_id: String) -> void:
	if not _active.has(quest_id):
		return
	var q: Quest = _active[quest_id]
	if q.type == "fetch":
		var item_id: String = str(q.objective.get("item_id", ""))
		var count: int = int(q.objective.get("count", 1))
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and item_id != "":
			SignalBus.item_consume_requested.emit(player, item_id, count)

	_active.erase(quest_id)
	q.status = "completed"
	_completed[quest_id] = q.to_dict()

	SignalBus.quest_reward_granted.emit(q.reward.duplicate())
	var rep_delta: int = int(q.reward.get("rep_delta", 0))
	if rep_delta != 0 and q.giver_faction != "":
		SignalBus.faction_rep_change_requested.emit(q.giver_faction, rep_delta, "Completed quest " + quest_id)
	var join_fac: String = str(q.reward.get("join_faction", ""))
	if join_fac != "":
		SignalBus.faction_join_requested.emit(join_fac)

	SignalBus.quest_completed.emit(quest_id)
	if q.is_chain and q.next_quest_id != "":
		start_quest(q.next_quest_id, q.giver_id)
	_emit_log_snapshot()


func fail_quest(quest_id: String, reason: String) -> void:
	if not _active.has(quest_id):
		return
	var q: Quest = _active[quest_id]
	_active.erase(quest_id)
	q.status = "failed"
	_failed[quest_id] = q.to_dict()

	var rep_delta: int = int(q.fail_consequence.get("rep_delta", 0))
	if rep_delta != 0 and q.giver_faction != "":
		SignalBus.faction_rep_change_requested.emit(q.giver_faction, rep_delta, "Failed quest: " + reason)
	if bool(q.fail_consequence.get("giver_dies", false)) and q.giver_id != "":
		SignalBus.npc_kill_requested.emit(q.giver_id, "Quest failed: " + quest_id)

	SignalBus.quest_failed.emit(quest_id, reason)
	_emit_log_snapshot()


func get_active_quests() -> Array[Quest]:
	var out: Array[Quest] = []
	for qid in _active:
		out.append(_active[qid])
	return out


func is_quest_active(quest_id: String) -> bool:
	return _active.has(quest_id)


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		_active.clear()
		_completed.clear()
		_failed.clear()
	_emit_log_snapshot()


func _on_quest_start_requested(quest_id: String, giver_id: String) -> void:
	start_quest(quest_id, giver_id)


func _on_quest_turn_in_requested(quest_id: String) -> void:
	if not _active.has(quest_id):
		return
	var q: Quest = _active[quest_id]
	if q.is_ready_to_complete():
		complete_quest(quest_id)


func _on_hour_passed(_hour: int) -> void:
	var expired: Array[String] = []
	for qid in _active:
		var q: Quest = _active[qid]
		if q.time_limit > 0.0:
			q.elapsed_hours += 1.0
			if q.elapsed_hours >= q.time_limit:
				expired.append(str(qid))
	for qid in expired:
		fail_quest(qid, "Time limit expired")


func _on_inventory_changed(entity: Node, _snapshot: Dictionary) -> void:
	if entity == null or not entity.is_in_group("player"):
		return
	var inv: InventoryComponent = entity.get("inventory") as InventoryComponent
	if inv == null:
		return
	for qid in _active:
		var q: Quest = _active[qid]
		if q.type == "fetch":
			var item_id: String = str(q.objective.get("item_id", ""))
			var cur: int = inv.count_of(item_id)
			update_objective(str(qid), "current", cur)


func _on_entity_died(entity: Node, killer_id: String) -> void:
	if killer_id != "player" or entity == null:
		return
	var def_id: String = str(entity.get("enemy_id")) if "enemy_id" in entity else ""
	var fac: String = str(entity.call("get_faction")) if entity.has_method("get_faction") else ""
	for qid in _active:
		var q: Quest = _active[qid]
		if q.type == "kill":
			var target: String = str(q.objective.get("target_id", ""))
			if target == def_id or target == fac:
				var cur: int = int(q.progress.get("current", 0)) + 1
				update_objective(str(qid), "current", cur)


func _on_poi_discovered(poi_id: String, _pos: Vector2i) -> void:
	for qid in _active:
		var q: Quest = _active[qid]
		if q.type == "explore":
			var target_poi: String = str(q.objective.get("poi_id", ""))
			if target_poi == "" or target_poi == poi_id:
				update_objective(str(qid), "current", int(q.progress.get("current", 0)) + 1)


func _on_structure_built(structure_id: String, _tile_pos: Vector2i) -> void:
	for qid in _active:
		var q: Quest = _active[qid]
		if q.type == "build":
			if str(q.objective.get("structure_id", "")) == structure_id:
				update_objective(str(qid), "current", int(q.progress.get("current", 0)) + 1)


func _emit_log_snapshot() -> void:
	var active_dict: Dictionary = {}
	for qid in _active:
		active_dict[qid] = (_active[qid] as Quest).to_dict()
	SignalBus.quest_log_changed.emit({
		"active": active_dict,
		"completed": _completed.duplicate(),
		"failed": _failed.duplicate()
	})


func _on_save_data_requested(bundle: Dictionary) -> void:
	var p: Dictionary = bundle.get("player", {})
	var active_out: Dictionary = {}
	for qid in _active:
		active_out[qid] = (_active[qid] as Quest).to_dict()
	p["quests"] = {
		"active": active_out,
		"completed": _completed.duplicate(),
		"failed": _failed.duplicate()
	}
	bundle["player"] = p


func _on_save_data_loaded(bundle: Dictionary) -> void:
	_active.clear()
	_completed.clear()
	_failed.clear()
	var p: Dictionary = bundle.get("player", {})
	var qdata: Dictionary = p.get("quests", {})
	var act: Dictionary = qdata.get("active", {})
	for qid in act:
		if act[qid] is Dictionary:
			_active[str(qid)] = Quest.from_dict(act[qid])
	_completed = qdata.get("completed", {}).duplicate()
	_failed = qdata.get("failed", {}).duplicate()
	_emit_log_snapshot()
