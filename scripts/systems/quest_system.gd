class_name QuestSystem
extends Node

var _quests_defs: Dictionary = {}
var _active_quests: Dictionary = {} # quest_id -> Dictionary state
var _completed_quests: Dictionary = {}
var _failed_quests: Dictionary = {}
var _delivery_in_progress: bool = false

func _ready() -> void:
	_quests_defs = DataRegistry.get_table("quests")
	_connect_signals()
	SignalBus.game_started.connect(_on_game_started)

func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if not is_new:
		return
	_active_quests.clear()
	_completed_quests.clear()
	_failed_quests.clear()
	_start_initial_quest()
	_emit_snapshot()

func _start_initial_quest() -> void:
	if _active_quests.is_empty() and _completed_quests.is_empty():
		var first_id: String = "cull_wolves_01" if _quests_defs.has("cull_wolves_01") else ""
		if first_id.is_empty() and not _quests_defs.is_empty():
			first_id = str(_quests_defs.keys()[0])
		if not first_id.is_empty():
			start_quest(first_id, "village_elder")

func _connect_signals() -> void:
	SignalBus.quest_start_requested.connect(start_quest)
	SignalBus.quest_turn_in_requested.connect(complete_quest)
	SignalBus.quest_state_queried.connect(_on_quest_state_queried)
	SignalBus.settlement_delivery_quest_requested.connect(_on_settlement_delivery_quest_requested)
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.npc_killed.connect(_on_npc_killed)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.structure_built.connect(_on_structure_built)
	SignalBus.resource_harvested.connect(_on_resource_harvested)
	SignalBus.poi_discovered.connect(_on_poi_discovered)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)

func start_quest(quest_id: String, _giver_id: String = "") -> bool:
	if _quests_defs.get(quest_id, {}).get("type", "") == "delivery":
		return false
	return _start_quest(quest_id)


func _start_quest(quest_id: String) -> bool:
	if _active_quests.has(quest_id) or _completed_quests.has(quest_id):
		return false
	if not _quests_defs.has(quest_id):
		return false
	var def: Dictionary = _quests_defs[quest_id]
	var obj: Dictionary = def.get("objective", {})
	var req_count: int = int(obj.get("count", def.get("required_count", 1)))
	var target_id: String = str(obj.get("target_id", obj.get("item_id", obj.get("structure_id", obj.get("poi_id", def.get("target_id", ""))))))
	var q_title: String = str(def.get("title", def.get("name", quest_id.replace("_", " ").capitalize())))

	var state: Dictionary = {
		"id": quest_id,
		"title": q_title,
		"type": str(def.get("type", "survive")),
		"target_id": target_id,
		"giver_faction": str(def.get("giver_faction", "")),
		"time_limit": float(def.get("time_limit", def.get("time_limit_hours", -1.0))),
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
	if _quests_defs.get(quest_id, {}).get("type", "") == "delivery":
		return
	_complete_quest(quest_id)


func _complete_quest(quest_id: String) -> void:
	if not _active_quests.has(quest_id):
		return
	var state: Dictionary = _active_quests[quest_id]
	_active_quests.erase(quest_id)
	_completed_quests[quest_id] = state
	SignalBus.quest_completed.emit(quest_id)

	var def: Dictionary = _quests_defs.get(quest_id, {})
	var rewards: Dictionary = def.get("reward", def.get("rewards", {}))
	SignalBus.quest_reward_granted.emit(rewards)

	var giver_faction: String = str(def.get("giver_faction", ""))
	var rep_delta: int = int(rewards.get("rep_delta", 0))
	if rep_delta != 0 and not giver_faction.is_empty():
		SignalBus.faction_rep_change_requested.emit(giver_faction, rep_delta, "quest_" + quest_id)

	var rep_rewards: Dictionary = rewards.get("reputation", {})
	for fid in rep_rewards.keys():
		SignalBus.faction_rep_change_requested.emit(str(fid), int(rep_rewards[fid]), "quest_" + quest_id)

	var join_fac: String = str(rewards.get("join_faction", ""))
	if not join_fac.is_empty():
		SignalBus.faction_join_requested.emit(join_fac)

	var gold_reward: int = int(rewards.get("gold", 0))
	var silver_reward: int = int(rewards.get("silver", 0))
	if gold_reward > 0 or silver_reward > 0:
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and player.get("inventory") is InventoryComponent:
			var inventory: InventoryComponent = player.get("inventory")
			if gold_reward > 0:
				inventory.add_gold(gold_reward)
			if silver_reward > 0:
				inventory.add_silver(silver_reward)

	var unique_trait: String = str(rewards.get("unique_trait", ""))
	if not unique_trait.is_empty():
		var player2: Node = get_tree().get_first_node_in_group("player")
		if player2 != null and player2.get("traits") is TraitsComponent:
			(player2.get("traits") as TraitsComponent).add_trait(unique_trait)

	var next_quest: String = str(def.get("next_quest_id", ""))
	if not next_quest.is_empty():
		start_quest(next_quest, "chain")
	_emit_snapshot()
	var title: String = str(state.get("title", quest_id))
	if state.get("type") == "delivery":
		SignalBus.notification_posted.emit("Поставка принята: %s" % title)
	else:
		SignalBus.notification_posted.emit("Quest Completed: %s" % title)


func _on_quest_state_queried(quest_id: String, result: Dictionary) -> void:
	if _active_quests.has(quest_id):
		result["state"] = "active"
	elif _completed_quests.has(quest_id):
		result["state"] = "completed"
	elif _failed_quests.has(quest_id):
		result["state"] = "failed"
	elif _quests_defs.has(quest_id):
		result["state"] = "available"


func _on_settlement_delivery_quest_requested(quest_id: String, elder: Node2D, turn_in: bool, result: Dictionary) -> void:
	var definition: Dictionary = _quests_defs.get(quest_id, {})
	var settlement_id: String = str(definition.get("settlement_id", ""))
	if definition.get("type", "") != "delivery" or settlement_id.is_empty() \
			or GameManager.get_world_generator_version() < int(definition.get("min_generator_version", 0)) \
			or not is_instance_valid(elder) or not elder is NPCBase or elder.is_queued_for_deletion() or not elder.is_alive() \
			or elder.npc_id != definition.get("giver_id") or elder.get_meta("settlement_id", "") != settlement_id:
		return
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null or player.is_dead or player.global_position.distance_to(elder.global_position) > Config.INTERACT_RANGE:
		result["message"] = "Подойдите к старосте."
		return
	if not turn_in:
		result["ok"] = not _failed_quests.has(quest_id) and _start_quest(quest_id)
		return
	if _delivery_in_progress or not _active_quests.has(quest_id):
		return
	var objective: Dictionary = definition.get("objective", {})
	_delivery_in_progress = true
	SignalBus.settlement_supply_delivery_requested.emit(settlement_id, player, str(objective.get("item_id", "")),
		int(objective.get("count", 0)), result)
	if bool(result.get("ok", false)):
		var progress: Dictionary = _active_quests[quest_id]["progress"]
		progress["current"] = progress["required"]
		_complete_quest(quest_id)
	_delivery_in_progress = false


func fail_quest(quest_id: String, reason: String = "timeout") -> void:
	if not _active_quests.has(quest_id):
		return
	var state: Dictionary = _active_quests[quest_id]
	_active_quests.erase(quest_id)
	_failed_quests[quest_id] = state
	var def: Dictionary = _quests_defs.get(quest_id, {})
	var fail_cons: Dictionary = def.get("fail_consequence", {})
	var rep_pen: int = int(fail_cons.get("rep_delta", 0))
	var giver_faction: String = str(def.get("giver_faction", ""))
	if rep_pen != 0 and not giver_faction.is_empty():
		SignalBus.faction_rep_change_requested.emit(giver_faction, rep_pen, "quest_failed_" + quest_id)
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

func _on_npc_killed(npc_id: String, _faction: String, killer: String) -> void:
	if killer != "player":
		return
	for qid in _active_quests.keys():
		var st: Dictionary = _active_quests[qid]
		var t_id: String = str(st.get("target_id", ""))
		if str(st.get("type", "")) == "kill" and (t_id.is_empty() or t_id == npc_id):
			advance_quest(str(qid), 1)

func _on_item_crafted(item_id: String) -> void:
	for qid in _active_quests.keys():
		var st: Dictionary = _active_quests[qid]
		var t_id: String = str(st.get("target_id", ""))
		if str(st.get("type", "")) == "fetch" and (t_id.is_empty() or t_id == item_id):
			advance_quest(str(qid), 1)

func _on_structure_built(structure_id: String, _tile_pos: Vector2i) -> void:
	for qid in _active_quests.keys():
		var st: Dictionary = _active_quests[qid]
		var t_id: String = str(st.get("target_id", ""))
		if str(st.get("type", "")) == "build" and (t_id.is_empty() or t_id == structure_id):
			advance_quest(str(qid), 1)

func _on_resource_harvested(resource_id: String, amount: int, _tile_pos: Vector2i) -> void:
	for qid in _active_quests.keys():
		var st: Dictionary = _active_quests[qid]
		var t_id: String = str(st.get("target_id", ""))
		if str(st.get("type", "")) == "fetch" and (t_id.is_empty() or t_id == resource_id):
			advance_quest(str(qid), maxi(1, amount))

func _on_poi_discovered(poi_id: String, _tile_pos: Vector2i) -> void:
	for qid in _active_quests.keys():
		var st: Dictionary = _active_quests[qid]
		var t_id: String = str(st.get("target_id", ""))
		if str(st.get("type", "")) == "explore" and (t_id.is_empty() or t_id == poi_id):
			advance_quest(str(qid), 1)

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
	if not w.has("quests"):
		_start_initial_quest()
	_emit_snapshot()
