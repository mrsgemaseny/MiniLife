class_name DialogueSystem
extends Node

# Evaluates dialogue trees, condition gates (skills, reputation, items), and choice effects.

var _active_dialogue_id: String = ""
var _active_node_id: String = ""
var _active_npc_id: String = ""
var _current_choices: Array[Dictionary] = []

func _ready() -> void:
	SignalBus.dialogue_started.connect(_on_dialogue_started)
	SignalBus.dialogue_choice_selected.connect(_on_choice_selected)
	SignalBus.dialogue_end_requested.connect(_end_dialogue)

func _on_dialogue_started(npc_id: String, dialogue_id: String) -> void:
	_active_npc_id = npc_id
	_active_dialogue_id = dialogue_id
	var dlg: Dictionary = DataRegistry.get_dialogue(dialogue_id)
	if dlg.is_empty():
		var fallbacks: Array = DataRegistry.get_rows("dialogues")
		if not fallbacks.is_empty() and fallbacks[0] is Dictionary:
			dlg = fallbacks[0]
	if dlg.is_empty():
		return
	_active_node_id = str(dlg.get("root_node", dlg.get("start_node", "start")))
	_show_node(dlg, _active_node_id)

func _show_node(dlg: Dictionary, node_id: String) -> void:
	var nodes: Dictionary = dlg.get("nodes", {})
	var node_data: Dictionary = nodes.get(node_id, {})
	if node_data.is_empty():
		_end_dialogue()
		return
	var speaker: String = str(dlg.get("speaker", _active_npc_id.capitalize()))
	var text: String = str(node_data.get("text", "..."))
	_current_choices.clear()
	var raw_choices: Array = node_data.get("choices", [])
	for c in raw_choices:
		if c is Dictionary and _evaluate_conditions((c as Dictionary).get("conditions", {})):
			_current_choices.append(c as Dictionary)
	SignalBus.dialogue_node_shown.emit(speaker, text, _current_choices)

func _on_choice_selected(choice_index: int) -> void:
	if choice_index < 0 or choice_index >= _current_choices.size():
		_end_dialogue()
		return
	var choice: Dictionary = _current_choices[choice_index]
	var start_quest_id: String = str(choice.get("start_quest", ""))
	if not start_quest_id.is_empty():
		SignalBus.quest_start_requested.emit(start_quest_id, _active_npc_id)
	if bool(choice.get("open_trade", false)):
		var trader_node: Node = _find_npc_by_id(_active_npc_id)
		SignalBus.trade_session_requested.emit(trader_node)
	var next_id: String = str(choice.get("next", "end"))
	var dlg: Dictionary = DataRegistry.get_dialogue(_active_dialogue_id)
	if next_id == "end" or next_id.is_empty() or not dlg.get("nodes", {}).has(next_id):
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
	if conds.has("min_skill"):
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
	_current_choices.clear()
	SignalBus.dialogue_ended.emit()
