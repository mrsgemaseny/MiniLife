class_name DialogueUI
extends Control

@onready var speaker_label: Label = $PanelContainer/VBoxContainer/SpeakerLabel
@onready var body_label: Label = $PanelContainer/VBoxContainer/DialogueText
@onready var choices_box: VBoxContainer = $PanelContainer/VBoxContainer/ChoicesBox

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	SignalBus.dialogue_node_shown.connect(_on_dialogue_node_shown)
	SignalBus.dialogue_ended.connect(_on_dialogue_ended)
	SignalBus.ui_close_all_requested.connect(_on_close_all)

func _on_dialogue_node_shown(speaker: String, text: String, choices: Array) -> void:
	visible = true
	SignalBus.ui_panel_toggled.emit("dialogue", true, true)
	if speaker_label != null:
		speaker_label.text = speaker
	if body_label != null:
		body_label.text = text
	if choices_box == null:
		return
	for child in choices_box.get_children():
		choices_box.remove_child(child)
		child.queue_free()

	for i in range(choices.size()):
		var choice: Dictionary = choices[i] if choices[i] is Dictionary else {}
		var btn: Button = Button.new()
		btn.text = str(choice.get("text", "Continue"))
		var idx: int = i
		btn.pressed.connect(func() -> void:
			SignalBus.dialogue_choice_selected.emit(idx)
		)
		choices_box.add_child(btn)

	var trade_btn: Button = Button.new()
	trade_btn.text = "[Barter / Trade Goods]"
	trade_btn.pressed.connect(func() -> void:
		var npc_node: Node = get_tree().get_first_node_in_group("npc")
		SignalBus.dialogue_end_requested.emit()
		SignalBus.trade_session_requested.emit(npc_node)
	)
	choices_box.add_child(trade_btn)

	var leave_btn: Button = Button.new()
	leave_btn.text = "[Leave]"
	leave_btn.pressed.connect(func() -> void:
		SignalBus.dialogue_end_requested.emit()
	)
	choices_box.add_child(leave_btn)

func _on_dialogue_ended() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit("dialogue", false, true)

func _on_close_all() -> void:
	if visible:
		SignalBus.dialogue_end_requested.emit()
