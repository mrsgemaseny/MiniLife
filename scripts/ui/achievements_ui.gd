class_name AchievementsUI
extends Control

const PANEL_ID: String = "achievements"

@onready var panel_container: PanelContainer = $PanelContainer
@onready var vbox: VBoxContainer = $PanelContainer/VBoxContainer
@onready var title_label: Label = $PanelContainer/VBoxContainer/TitleLabel
@onready var list_box: VBoxContainer = $PanelContainer/VBoxContainer/ListBox

var _defs: Dictionary = {}
var _unlocked: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_defs = DataRegistry.get_table("achievements")
	_setup_styled_achievements()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.achievements_data_loaded.connect(_on_data_loaded)

func _make_card_sb(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb

func _setup_styled_achievements() -> void:
	if panel_container != null:
		panel_container.offset_left = -260.0
		panel_container.offset_top = -195.0
		panel_container.offset_right = 260.0
		panel_container.offset_bottom = 195.0
		var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
		frame_sb.bg_color = Color(0.06, 0.08, 0.12, 0.78)
		frame_sb.border_color = Color(0.78, 0.64, 0.34, 0.85)
		frame_sb.set_border_width_all(2)
		frame_sb.set_corner_radius_all(10)
		frame_sb.set_content_margin_all(14)
		panel_container.add_theme_stylebox_override("panel", frame_sb)

	if vbox != null:
		vbox.add_theme_constant_override("separation", 8)
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		if title_label != null:
			vbox.remove_child(title_label)
			title_label.text = "TROPHIES & LEGACY ACHIEVEMENTS  [L]"
			title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title_label.add_theme_font_size_override("font_size", 14)
			title_label.modulate = Color(0.96, 0.86, 0.52)
			hdr_hbox.add_child(title_label)
		var close_btn: Button = Button.new()
		close_btn.text = " [X] Close "
		close_btn.add_theme_font_size_override("font_size", 11)
		close_btn.add_theme_stylebox_override("normal", _make_card_sb(Color(0.28, 0.10, 0.12, 0.80), Color(0.85, 0.38, 0.38, 0.85)))
		close_btn.pressed.connect(close_panel)
		hdr_hbox.add_child(close_btn)
		vbox.add_child(hdr_hbox)
		vbox.move_child(hdr_hbox, 0)

func open_panel() -> void:
	visible = true
	SignalBus.achievements_data_requested.emit()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)

func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)

func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()
	elif visible:
		close_panel()

func _on_data_loaded(data: Dictionary) -> void:
	_unlocked = data.get("unlocked", {})
	if list_box == null:
		return
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()
	for aid in _defs:
		var def: Dictionary = _defs[aid]
		var is_done: bool = _unlocked.has(aid)
		var acard: PanelContainer = PanelContainer.new()
		var bg: Color = Color(0.14, 0.18, 0.14, 0.78) if is_done else Color(0.09, 0.11, 0.15, 0.65)
		var border: Color = Color(0.92, 0.76, 0.28, 0.90) if is_done else Color(0.32, 0.36, 0.42, 0.55)
		acard.add_theme_stylebox_override("panel", _make_card_sb(bg, border))
		var lbl: Label = Label.new()
		lbl.text = "[%s]  %s  —  %s" % ["UNLOCKED" if is_done else "LOCKED", str(def.get("title", def.get("name", aid))), str(def.get("description", ""))]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.modulate = Color(0.98, 0.92, 0.64) if is_done else Color(0.68, 0.72, 0.78)
		acard.add_child(lbl)
		list_box.add_child(acard)
