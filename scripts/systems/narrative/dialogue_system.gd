class_name DialogueSystem
extends Node

# Evaluates dialogue trees (supports both Array and Dictionary "nodes" formats in data/dialogues.json).

var _active_dialogue_id: String = ""
var _active_node_id: String = ""
var _active_npc_id: String = ""
var _active_speaker: Node2D
var _current_choices: Array[Dictionary] = []

func _ready() -> void:
	SignalBus.dialogue_started.connect(_on_dialogue_started)
	SignalBus.dialogue_choice_selected.connect(_on_choice_selected)
	SignalBus.dialogue_end_requested.connect(_end_dialogue)
	SignalBus.dialogue_trade_requested.connect(_open_trade)

func _on_dialogue_started(npc_id: String, dialogue_id: String, speaker: Node2D) -> void:
	_active_npc_id = npc_id
	_active_speaker = speaker
	_active_dialogue_id = dialogue_id
	var dlg: Dictionary = DataRegistry.get_dialogue(dialogue_id)
	if is_instance_valid(speaker):
		var settlement_id: String = str(speaker.get_meta("settlement_id", ""))
		if not settlement_id.is_empty():
			var local_id: String = "%s_%s" % [dialogue_id, settlement_id]
			var local: Dictionary = DataRegistry.get_dialogue(local_id)
			if not local.is_empty() and GameManager.get_world_generator_version() >= int(local.get("min_generator_version", 0)):
				dlg = local
				_active_dialogue_id = local_id
	if dlg.is_empty():
		var fallbacks: Array = DataRegistry.get_rows("dialogues")
		if not fallbacks.is_empty() and fallbacks[0] is Dictionary:
			dlg = fallbacks[0]
			_active_dialogue_id = str(dlg.get("id", ""))
	if dlg.is_empty():
		return
	_active_node_id = str(dlg.get("root_node", dlg.get("start_node", "root")))
	_show_node(dlg, _active_node_id)

func _find_dialogue_node(dlg: Dictionary, node_id: String) -> Dictionary:
	var raw_nodes: Variant = dlg.get("nodes", [])
	if raw_nodes is Dictionary:
		var ndict: Dictionary = raw_nodes
		if ndict.has(node_id) and ndict[node_id] is Dictionary:
			return ndict[node_id]
		if not ndict.is_empty():
			var first_key: Variant = ndict.keys()[0]
			if ndict[first_key] is Dictionary:
				return ndict[first_key]
	elif raw_nodes is Array:
		var narr: Array = raw_nodes
		for item in narr:
			if item is Dictionary and str((item as Dictionary).get("id", "")) == node_id:
				return item
		if not narr.is_empty() and narr[0] is Dictionary:
			return narr[0]
	return {}

func _show_node(dlg: Dictionary, node_id: String) -> void:
	var node_data: Dictionary = _find_dialogue_node(dlg, node_id)
	if node_data.is_empty():
		_end_dialogue()
		return
	var speaker: String = str(node_data.get("speaker", dlg.get("speaker", _active_npc_id.capitalize())))
	var text: String = str(node_data.get("text", "..."))
	_current_choices.clear()
	var raw_choices: Variant = node_data.get("choices", [])
	if raw_choices is Array:
		for c in raw_choices:
			if c is Dictionary:
				var cdict: Dictionary = c
				var cond: Dictionary = cdict.get("condition", cdict.get("conditions", {})) if (cdict.get("condition", cdict.get("conditions", {})) is Dictionary) else {}
				if _evaluate_conditions(cond):
					_current_choices.append(cdict)
	SignalBus.dialogue_node_shown.emit(speaker, text, _current_choices)

func _on_choice_selected(choice_index: int) -> void:
	if choice_index < 0 or choice_index >= _current_choices.size():
		_end_dialogue()
		return
	var choice: Dictionary = _current_choices[choice_index]

	# Execute action from data/dialogues.json
	var act: Variant = choice.get("action", "")
	if act is Dictionary:
		var adict: Dictionary = act
		var atype: String = str(adict.get("type", ""))
		if atype == "start_quest":
			var qid: String = str(adict.get("quest_id", ""))
			if not qid.is_empty():
				SignalBus.quest_start_requested.emit(qid, _active_npc_id)
		elif atype == "turn_in_quest":
			var qid: String = str(adict.get("quest_id", ""))
			if not qid.is_empty():
				SignalBus.quest_turn_in_requested.emit(qid)
		elif atype == "open_trade":
			_open_trade()
			return
		elif atype in ["accept_delivery", "turn_in_delivery"]:
			var result: Dictionary = {}
			SignalBus.settlement_delivery_quest_requested.emit(str(adict.get("quest_id", "")), _active_speaker,
				atype == "turn_in_delivery", result)
			if not bool(result.get("ok", false)):
				SignalBus.notification_posted.emit(str(result.get("message", "Поручение пока недоступно.")))
				return

	var start_quest_id: String = str(choice.get("start_quest", ""))
	if not start_quest_id.is_empty():
		SignalBus.quest_start_requested.emit(start_quest_id, _active_npc_id)
	if bool(choice.get("open_trade", false)):
		_open_trade()
		return

	var next_id: String = str(choice.get("next_node", choice.get("next", "")))
	if next_id == "end" or next_id.is_empty() or (act is String and str(act) == "end"):
		_end_dialogue()
	else:
		var dlg: Dictionary = DataRegistry.get_dialogue(_active_dialogue_id)
		var next_node: Dictionary = _find_dialogue_node(dlg, next_id)
		if next_node.is_empty():
			_end_dialogue()
		else:
			_active_node_id = next_id
			_show_node(dlg, next_id)

func _evaluate_conditions(conds: Dictionary) -> bool:
	if conds.is_empty():
		return true
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	if conds.has("quest_state"):
		var result: Dictionary = {}
		SignalBus.quest_state_queried.emit(str(conds.get("quest_id", "")), result)
		if result.get("state") != conds["quest_state"]:
			return false
	if conds.has("item_id"):
		var req_item: String = str(conds.get("item_id", ""))
		var req_cnt: int = int(conds.get("count", 1))
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if inv == null or not inv.has_item(req_item, req_cnt):
			return false
	if conds.has("min_skill") and conds["min_skill"] is Dictionary:
		var skill_reqs: Dictionary = conds["min_skill"]
		var skills_comp: SkillsComponent = player.get("skills") as SkillsComponent
		if skills_comp != null and not skills_comp.meets_requirements(skill_reqs):
			return false
	return true

func _open_trade() -> void:
	var speaker: Node2D = _active_speaker
	_end_dialogue()
	if is_instance_valid(speaker) and not speaker.is_queued_for_deletion():
		SignalBus.trade_session_requested.emit(speaker)

func _end_dialogue() -> void:
	_active_dialogue_id = ""
	_active_node_id = ""
	_active_npc_id = ""
	_active_speaker = null
	_current_choices.clear()
	SignalBus.dialogue_ended.emit()
