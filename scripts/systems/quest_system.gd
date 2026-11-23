class_name QuestSystem
extends Node

var _quests_defs: Dictionary = {}
var _active_quests: Dictionary = {} # quest_id -> Dictionary state
var _completed_quests: Dictionary = {}
var _failed_quests: Dictionary = {}

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
	SignalBus.village_quest_action_performed.connect(_on_village_quest_action_performed)
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.npc_killed.connect(_on_npc_killed)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.structure_built.connect(_on_structure_built)
	SignalBus.resource_harvested.connect(_on_resource_harvested)
	SignalBus.poi_discovered.connect(_on_poi_discovered)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)

func start_quest(quest_id: String, _giver_id: String = "") -> bool:
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

func start_village_quest(template_id: String, settlement_id: String) -> bool:
	var template: Dictionary = DataRegistry.get_entry("quests_village", template_id)
	if template.is_empty() or settlement_id.is_empty():
		return false
	var settlement: Dictionary = {}
	SignalBus.village_quest_settlement_queried.emit(settlement_id, settlement)
	if settlement.is_empty() or str(settlement.get("settlement_type", "")) != "village":
		return false
	var reputation: ReputationSystem = get_tree().get_first_node_in_group("reputation_system") as ReputationSystem
	var required_rep: int = int(template.get("min_reputation", -2))
	if required_rep > -2 and (reputation == null or reputation.get_local(settlement_id) < required_rep * 20):
		return false
	var quest_id: String = template_id + "@" + settlement_id
	if _active_quests.has(quest_id) or _completed_quests.has(quest_id) or _failed_quests.has(quest_id):
		return false
	var objective: Dictionary = template.get("objective", {})
	var target_id: String = str(objective.get("target_id", ""))
	if target_id.is_empty():
		return false
	var action_text: String = str(template.get("action", ""))
	var count: int = maxi(1, int(objective.get("count", 1)))
	var target_settlement: String = ""
	var connections: Array = settlement.get("connections", [])
	if not connections.is_empty():
		var neighbor: Dictionary = {}
		SignalBus.village_quest_settlement_queried.emit(str(connections[0]), neighbor)
		target_settlement = str(neighbor.get("name", connections[0]))
	var title: String = str(template.get("hook", template_id)).replace("{settlement}", str(settlement["name"]))
	title = title.replace("{target_settlement}", target_settlement).replace("{faction}", str(settlement.get("owner_faction", "")))
	_active_quests[quest_id] = {
		"id": quest_id, "template_id": template_id, "settlement_id": settlement_id,
		"title": title, "description": action_text.replace("{settlement}", str(settlement["name"])).replace("{target_settlement}", target_settlement).replace("{faction}", str(settlement.get("owner_faction", ""))),
		"type": "village", "action_type": str(template.get("action_type", "")),
		"target_id": target_id, "progress": {"current": 0, "required": count},
		"time_limit": -1.0, "elapsed_hours": 0.0,
	}
	SignalBus.quest_started.emit(quest_id)
	_emit_snapshot()
	return true

func _on_village_quest_action_performed(settlement_id: String, action_type: String, target_id: String, amount: int) -> void:
	if amount <= 0:
		return
	for quest_id: Variant in _active_quests.keys():
		var state: Dictionary = _active_quests[quest_id]
		if str(state.get("type", "")) != "village" or str(state.get("settlement_id", "")) != settlement_id:
			continue
		if str(state.get("action_type", "")) != action_type:
			continue
		var expected: String = str(state.get("target_id", ""))
		if not expected.is_empty() and expected != target_id:
			continue
		advance_quest(str(quest_id), amount)

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
	if cur >= int(prog.get("required", 1)) and str(state.get("type", "")) != "village":
		complete_quest(quest_id)

func complete_quest(quest_id: String) -> void:
	if not _active_quests.has(quest_id):
		return
	var state: Dictionary = _active_quests[quest_id]
	if str(state.get("type", "")) == "village":
		_complete_village_quest(quest_id, state)
		return
	_active_quests.erase(quest_id)
	_completed_quests[quest_id] = state
	SignalBus.quest_completed.emit(quest_id)

	var def: Dictionary = _quests_defs.get(quest_id, {})
	if str(def.get("next_quest_id", "")).is_empty():
		for candidate: Dictionary in _quests_defs.values():
			if str(candidate.get("next_quest_id", "")) == quest_id:
				SignalBus.quest_chain_completed.emit(quest_id)
				break
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
	if gold_reward > 0:
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and player.get("inventory") is InventoryComponent:
			(player.get("inventory") as InventoryComponent).add_gold(gold_reward)

	var unique_trait: String = str(rewards.get("unique_trait", ""))
	if not unique_trait.is_empty():
		var player2: Node = get_tree().get_first_node_in_group("player")
		if player2 != null and player2.get("traits") is TraitsComponent:
			(player2.get("traits") as TraitsComponent).add_trait(unique_trait)

	var next_quest: String = str(def.get("next_quest_id", ""))
	if not next_quest.is_empty():
		start_quest(next_quest, "chain")
	_emit_snapshot()
	SignalBus.notification_posted.emit("Quest Completed: %s" % str(state.get("title", quest_id)))

func _complete_village_quest(quest_id: String, state: Dictionary) -> void:
	var template: Dictionary = DataRegistry.get_entry("quests_village", str(state.get("template_id", "")))
	if template.is_empty():
		return
	var progress: Dictionary = state.get("progress", {})
	var required: int = maxi(1, int(progress.get("required", 1)))
	var target_id: String = str(state.get("target_id", ""))
	var action_type: String = str(state.get("action_type", ""))
	var player: Node = get_tree().get_first_node_in_group("player")
	var inventory: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	var needs_items: bool = action_type == "доставка" or (action_type == "поиск" and DataRegistry.has_entry("items", target_id))
	if needs_items:
		if inventory == null or not inventory.has_item(target_id, required):
			return
	elif int(progress.get("current", 0)) < required:
		return
	var effect_set: Dictionary = template.get("effects", {})
	var changes: Dictionary = effect_set.get("success", {})
	var result: Dictionary = {}
	SignalBus.village_quest_ripple_requested.emit(str(state["settlement_id"]), changes, result)
	if not bool(result.get("applied", false)):
		return
	if needs_items:
		inventory.remove_item(target_id, required)
	var reward_text: String = str(template.get("reward", ""))
	if inventory != null and reward_text.contains("серебра"):
		var digits: RegEx = RegEx.new()
		digits.compile("[0-9]+")
		var match_number: RegExMatch = digits.search(reward_text)
		if match_number != null:
			inventory.add_silver(int(match_number.get_string()))
	_active_quests.erase(quest_id)
	_completed_quests[quest_id] = state
	SignalBus.quest_completed.emit(quest_id)
	SignalBus.local_rep_change_requested.emit(str(state["settlement_id"]), 5, "quest_" + quest_id)
	_emit_snapshot()
	SignalBus.notification_posted.emit(str(template.get("resolution", {}).get("success", "Задание выполнено.")))

func fail_quest(quest_id: String, reason: String = "timeout") -> void:
	if not _active_quests.has(quest_id):
		return
	var state: Dictionary = _active_quests[quest_id]
	if str(state.get("type", "")) == "village":
		var template: Dictionary = DataRegistry.get_entry("quests_village", str(state.get("template_id", "")))
		var changes: Dictionary = template.get("effects", {}).get("fail", {})
		var result: Dictionary = {}
		SignalBus.village_quest_ripple_requested.emit(str(state.get("settlement_id", "")), changes, result)
		if not bool(result.get("applied", false)):
			return
		SignalBus.local_rep_change_requested.emit(str(state["settlement_id"]), -5, "quest_failed_" + quest_id)
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
	for qid in _active_quests.keys():
		var village: Dictionary = _active_quests[qid]
		if str(village.get("type", "")) == "village" and str(village.get("action_type", "")) == "охота" and str(village.get("target_id", "")) == npc_id:
			advance_quest(str(qid), 1)
			break

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
	for qid in _active_quests.keys():
		var village: Dictionary = _active_quests[qid]
		if str(village.get("type", "")) == "village" and str(village.get("action_type", "")) == "поиск" and str(village.get("target_id", "")) == resource_id:
			advance_quest(str(qid), maxi(1, amount))
			break

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
