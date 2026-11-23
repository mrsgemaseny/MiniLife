class_name DialogueSystem
extends Node

# Evaluates dialogue trees (supports both Array and Dictionary "nodes" formats in data/dialogues.json).

var _active_dialogue_id: String = ""
var _active_node_id: String = ""
var _active_npc_id: String = ""
var _active_settlement_id: String = ""
var _active_resident_settlement_id: String = ""
var _current_choices: Array[Dictionary] = []
var _role_lines: Dictionary = {}

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues_ru.json"))
	if parsed is Dictionary:
		_role_lines = parsed
	SignalBus.village_elder_interacted.connect(_on_village_elder_interacted)
	SignalBus.village_resident_spoken_to.connect(_on_village_resident_spoken_to)
	SignalBus.dialogue_started.connect(_on_dialogue_started)
	SignalBus.dialogue_choice_selected.connect(_on_choice_selected)
	SignalBus.dialogue_end_requested.connect(_end_dialogue)

func _on_dialogue_started(npc_id: String, dialogue_id: String) -> void:
	_active_npc_id = npc_id
	_active_dialogue_id = dialogue_id
	if npc_id == "village_elder" and not _active_settlement_id.is_empty():
		_show_village_elder()
		return
	if npc_id == "wanderer_npc" and not _active_resident_settlement_id.is_empty():
		_show_village_resident()
		return
	_active_settlement_id = ""
	_active_resident_settlement_id = ""
	var dlg: Dictionary = DataRegistry.get_dialogue(dialogue_id)
	if dlg.is_empty():
		var fallbacks: Array = DataRegistry.get_rows("dialogues")
		if not fallbacks.is_empty() and fallbacks[0] is Dictionary:
			dlg = fallbacks[0]
			_active_dialogue_id = str(dlg.get("id", ""))
	if dlg.is_empty():
		return
	_active_node_id = str(dlg.get("root_node", dlg.get("start_node", "root")))
	_show_node(dlg, _active_node_id)

func _on_village_elder_interacted(settlement_id: String) -> void:
	_active_settlement_id = settlement_id
	_active_resident_settlement_id = ""

func _on_village_resident_spoken_to(settlement_id: String, _resident_uid: String) -> void:
	_active_resident_settlement_id = settlement_id
	_active_settlement_id = ""

func _show_village_resident() -> void:
	var reputation: Dictionary = {}
	SignalBus.local_rep_queried.emit(_active_resident_settlement_id, reputation)
	var level: int = clampi(floori(float(reputation.get("value", 0)) / 20.0), -2, 2)
	var lines: Array = _role_lines.get("крестьянин", {}).get("rep_%d" % level, [])
	var text_line: String = "День добрый. Поле нынче сухое."
	if not lines.is_empty():
		text_line = str(lines[posmod(hash(_active_resident_settlement_id) + GameManager.get_day(), lines.size())])
	_current_choices.clear()
	_current_choices.append({"text": "Спасибо за разговор.", "action": "end"})
	SignalBus.dialogue_node_shown.emit("Житель", text_line, _current_choices)

func _show_village_elder() -> void:
	var settlement: Dictionary = {}
	SignalBus.village_quest_settlement_queried.emit(_active_settlement_id, settlement)
	if settlement.is_empty():
		_end_dialogue()
		return
	var available: Dictionary = {}
	SignalBus.village_quest_offers_queried.emit(_active_settlement_id, available)
	var reputation: Dictionary = {}
	SignalBus.local_rep_queried.emit(_active_settlement_id, reputation)
	var level: int = clampi(floori(float(reputation.get("value", 0)) / 20.0), -2, 2)
	var lines: Array = _role_lines.get("староста", {}).get("rep_%d" % level, [])
	var greeting: String = "Здравствуй, путник. Нужна работа?"
	if not lines.is_empty():
		greeting = str(lines[posmod(hash(_active_settlement_id) + GameManager.get_day(), lines.size())])
	_current_choices.clear()
	for row: Dictionary in available.get("turn_ins", []):
		_current_choices.append({"text": "Сдать: " + str(row["title"]), "action": {"type": "turn_in_quest", "quest_id": str(row["id"])}})
	for row: Dictionary in available.get("offers", []):
		var template_id: String = str(row["id"])
		var template: Dictionary = DataRegistry.get_entry("quests_village", template_id)
		var description: String = str(template.get("action", ""))
		description = description.replace("{settlement}", str(settlement.get("name", "")))
		var target_name: String = "соседнего поселения"
		var connections: Array = settlement.get("connections", [])
		if not connections.is_empty():
			var neighbor: Dictionary = {}
			SignalBus.village_quest_settlement_queried.emit(str(connections[0]), neighbor)
			target_name = str(neighbor.get("name", connections[0]))
		description = description.replace("{target_settlement}", target_name)
		description = description.replace("{faction}", str(settlement.get("owner_faction", "")))
		_current_choices.append({"text": description, "action": {"type": "start_village_quest", "template_id": template_id}})
	_current_choices.append({"text": "Пока не могу помочь.", "action": "end"})
	SignalBus.dialogue_node_shown.emit("Староста", greeting, _current_choices)

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
		if atype == "start_village_quest":
			var result: Dictionary = {}
			SignalBus.village_quest_start_requested.emit(str(adict.get("template_id", "")), _active_settlement_id, result)
			if not bool(result.get("started", false)):
				SignalBus.notification_posted.emit("Староста пока не может дать это поручение.")
			_end_dialogue()
			return
		if atype == "start_quest":
			var qid: String = str(adict.get("quest_id", ""))
			if not qid.is_empty():
				SignalBus.quest_start_requested.emit(qid, _active_npc_id)
		elif atype == "turn_in_quest":
			var qid: String = str(adict.get("quest_id", ""))
			if not qid.is_empty():
				SignalBus.quest_turn_in_requested.emit(qid)
		elif atype == "open_trade":
			var trader_node: Node = _find_npc_by_id(_active_npc_id)
			SignalBus.trade_session_requested.emit(trader_node)

	var start_quest_id: String = str(choice.get("start_quest", ""))
	if not start_quest_id.is_empty():
		SignalBus.quest_start_requested.emit(start_quest_id, _active_npc_id)
	if bool(choice.get("open_trade", false)):
		var trader_node: Node = _find_npc_by_id(_active_npc_id)
		SignalBus.trade_session_requested.emit(trader_node)

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

func _find_npc_by_id(npc_id: String) -> Node:
	for n in get_tree().get_nodes_in_group("npc"):
		if "npc_id" in n and str(n.get("npc_id")) == npc_id:
			return n
	return null

func _end_dialogue() -> void:
	_active_dialogue_id = ""
	_active_node_id = ""
	_active_settlement_id = ""
	_active_resident_settlement_id = ""
	_current_choices.clear()
	SignalBus.dialogue_ended.emit()
