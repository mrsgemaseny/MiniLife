class_name CaravanCargoUI
extends CanvasLayer

var _panel: Control
var _title: Label
var _items: ItemList
var _ids: Array[String] = []
var _cargo_id: String = ""
var _escort_button: Button
var _note: Label

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
	frame.offset_left = -280.0
	frame.offset_right = 280.0
	frame.offset_top = -230.0
	frame.offset_bottom = 230.0
	_panel.add_child(frame)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	frame.add_child(margin)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	_title = Label.new()
	body.add_child(_title)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_note)
	_escort_button = Button.new()
	_escort_button.text = "Escort convoy — 150 silver"
	_escort_button.pressed.connect(_accept_escort)
	body.add_child(_escort_button)
	_items = ItemList.new()
	_items.custom_minimum_size = Vector2(480.0, 220.0)
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_items)
	var buttons: HBoxContainer = HBoxContainer.new()
	body.add_child(buttons)
	for entry: Array in [["Take one", 1], ["Take stack", 0]]:
		var button: Button = Button.new()
		button.text = str(entry[0])
		button.pressed.connect(_take.bind(int(entry[1])))
		buttons.add_child(button)
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close_panel)
	buttons.add_child(close_button)
	_panel.hide()
	SignalBus.alife_cargo_opened.connect(_open)
	SignalBus.ui_close_all_requested.connect(close_panel)

func _open(id: String) -> void:
	_cargo_id = id
	_refresh()
	_panel.show()
	SignalBus.ui_panel_toggled.emit("caravan_cargo", true, true)

func close_panel() -> void:
	if _panel == null or not _panel.visible:
		return
	_panel.hide()
	SignalBus.ui_panel_toggled.emit("caravan_cargo", false, true)

func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	var data: Dictionary = {}
	SignalBus.alife_cargo_queried.emit(_cargo_id, data)
	_title.text = str(data.get("title", "Caravan supplies"))
	var wreck: bool = bool(data.get("is_wreck", false))
	_note.text = "Salvage the supplies left in this wreck." if wreck else "Taking supplies from a live caravan is theft. Escort reward is paid after delivery; stay within 12 tiles of the convoy."
	_escort_button.visible = not wreck
	_escort_button.disabled = not bool(data.get("escort_available", false))
	match str(data.get("escort_state", "")):
		"accepted": _escort_button.text = "Escort accepted — 150 silver reserved"
		"reward_pending": _escort_button.text = "Delivery complete — reward pending"
		"paid": _escort_button.text = "Escort complete — reward paid"
		"failed": _escort_button.text = "Escort failed for this trip"
		_: _escort_button.text = "Escort convoy — 150 silver"
	_ids.assign((data.get("cargo", {}) as Dictionary).keys())
	_ids.sort()
	_items.clear()
	for id: String in _ids:
		var definition: Dictionary = DataRegistry.get_item("bread" if id == "food" else id)
		_items.add_item("%s x%d" % [str(definition.get("name", id)), int(data["cargo"][id])])

func _take(count: int) -> void:
	var selected: PackedInt32Array = _items.get_selected_items()
	if selected.is_empty() or selected[0] >= _ids.size():
		return
	var result: Dictionary = {}
	SignalBus.alife_cargo_take_requested.emit(_cargo_id, _ids[selected[0]], count, result)
	_refresh()

func _accept_escort() -> void:
	var result: Dictionary = {}
	SignalBus.alife_escort_accept_requested.emit(_cargo_id, result)
	_refresh()
