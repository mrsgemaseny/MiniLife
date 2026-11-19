class_name TavernHireUI
extends CanvasLayer

const PANEL_ID: String = "tavern_hire"

var _panel: Control
var _status: Label
var _hire_button: Button
var _tavern: Node
var _actor: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.06, 0.75)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(backdrop)
	var frame: PanelContainer = PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -230.0
	frame.offset_right = 230.0
	frame.offset_top = -100.0
	frame.offset_bottom = 100.0
	_panel.add_child(frame)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	frame.add_child(margin)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var title: Label = Label.new()
	title.text = "Таверна"
	body.add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	var buttons: HBoxContainer = HBoxContainer.new()
	body.add_child(buttons)
	_hire_button = Button.new()
	_hire_button.pressed.connect(_hire)
	buttons.add_child(_hire_button)
	var close_button: Button = Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(close_panel)
	buttons.add_child(close_button)
	_panel.hide()
	SignalBus.ui_close_all_requested.connect(close_panel)


func open_quote(tavern: Node, actor: Node, price: int, available: bool) -> void:
	SignalBus.ui_close_all_requested.emit()
	_tavern = tavern
	_actor = actor
	var player: Player = actor as Player
	var affordable: bool = player.inventory.silver >= price
	_status.text = "Наёмник будет идти с вами и защищать от врагов поблизости. У вас %d серебряных." % player.inventory.silver \
		if available else "У вас уже есть наёмник."
	_hire_button.text = "Нанять за %d серебряных" % price
	_hire_button.disabled = not available or not affordable
	_panel.show()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not _panel.visible:
		return
	_panel.hide()
	_tavern = null
	_actor = null
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _hire() -> void:
	if not is_instance_valid(_tavern) or not is_instance_valid(_actor):
		close_panel()
		return
	var result: Dictionary = {}
	SignalBus.tavern_hire_requested.emit(_tavern, _actor, result)
	if result.get("ok", false):
		close_panel()
		SignalBus.notification_posted.emit("Наёмник присоединился к вам.")
	else:
		_status.text = str(result.get("message", "Не удалось нанять бойца."))


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()
