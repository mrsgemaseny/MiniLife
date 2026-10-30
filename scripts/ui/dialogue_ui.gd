class_name DialogueUI
extends Control

const PANEL_ID: String = "dialogue"

@onready var speaker_label: Label = $PanelContainer/VBoxContainer/SpeakerLabel
@onready var dialogue_text: Label = $PanelContainer/VBoxContainer/DialogueText
@onready var choices_box: VBoxContainer = $PanelContainer/VBoxContainer/ChoicesBox

var _dialogues: Dictionary = {}
var _current_tree: Dictionary = {}
var _current_npc_id: String = ""
var _rep_snapshot: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dialogues = GameManager.load_json_indexed("dialogues.json")
	SignalBus.dialogue_started.connect(_on_dialogue_started)
	SignalBus.dialogue_end_requested.connect(close_dialogue)
	SignalBus.ui_close_all_requested.connect(close_dialogue)
	SignalBus.faction_rep_snapshot.connect(func(rep_map: Dictionary) -> void:
		_rep_snapshot = rep_map
	)


func close_dialogue() -> void:
	if not visible:
		return
	visible = false
	_current_tree.clear()
	_current_npc_id = ""
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)
	SignalBus.dialogue_ended.emit()


func _on_dialogue_started(npc_id: String, dialogue_id: String) -> void:
	if not _dialogues.has(dialogue_id):
		return
	_current_npc_id = npc_id
	_current_tree = _dialogues[dialogue_id]
	visible = true
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)
	var nodes: Array = _current_tree.get("nodes", [])
	if not nodes.is_empty() and nodes[0] is Dictionary:
		_show_node(nodes[0])


func _show_node(node_data: Dictionary) -> void:
	if speaker_label != null:
		speaker_label.text = str(node_data.get("speaker", _current_npc_id))
	if dialogue_text != null:
		dialogue_text.text = str(node_data.get("text", ""))
	if choices_box == null:
		return
	for child in choices_box.get_children():
		choices_box.remove_child(child)
		child.queue_free()

	var choices: Array = node_data.get("choices", [])
	for c in choices:
		if not (c is Dictionary):
			continue
		var choice_dict: Dictionary = c
		var cond: Dictionary = choice_dict.get("condition", {})
		if not _evaluate_condition(cond):
			continue
		var btn: Button = Button.new()
		btn.text = str(choice_dict.get("text", "Continue"))
		btn.pressed.connect(func() -> void:
			_execute_action(choice_dict.get("action", {}))
			var next_id: String = str(choice_dict.get("next_node", ""))
			if next_id == "":
				close_dialogue()
			else:
				var next_node: Dictionary = _find_node(next_id)
				if next_node.is_empty():
					close_dialogue()
				else:
					_show_node(next_node)
		)
		choices_box.add_child(btn)


func _find_node(node_id: String) -> Dictionary:
	for n in _current_tree.get("nodes", []):
		if n is Dictionary and str(n.get("id", "")) == node_id:
			return n
	return {}


func _evaluate_condition(cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	if cond.has("skill"):
		var skills: SkillsComponent = player.get("skills") as SkillsComponent
		var req_level: int = int(cond.get("level", 1))
		if skills == null or skills.get_level(str(cond["skill"])) < req_level:
			return false
	if cond.has("min_gold"):
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if inv == null or inv.gold < int(cond["min_gold"]):
			return false
	if cond.has("item_id"):
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if inv == null or not inv.has_item(str(cond["item_id"]), int(cond.get("count", 1))):
			return false
	if cond.has("faction") and cond.has("min_rep"):
		var rep: int = int(_rep_snapshot.get(str(cond["faction"]), 0))
		if rep < int(cond["min_rep"]):
			return false
	return true


func _execute_action(action: Variant) -> void:
	if action is String:
		if str(action) == "end":
			close_dialogue()
		return
	if not (action is Dictionary):
		return
	var act: Dictionary = action
	var atype: String = str(act.get("type", ""))
	match atype:
		"start_quest":
			SignalBus.quest_start_requested.emit(str(act.get("quest_id", "")), _current_npc_id)
		"turn_in_quest":
			SignalBus.quest_turn_in_requested.emit(str(act.get("quest_id", "")))
		"open_craft":
			SignalBus.craft_station_opened.emit(str(act.get("station", "")))
		"change_rep":
			SignalBus.faction_rep_change_requested.emit(str(act.get("faction", "")), int(act.get("delta", 0)), "Dialogue choice")
