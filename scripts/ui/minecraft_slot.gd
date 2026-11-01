class_name MinecraftSlot
extends Control

signal slot_clicked(slot_index: int, mouse_button: int, shift_pressed: bool)
signal slot_hovered(slot_index: int)
signal slot_unhovered(slot_index: int)

const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")

var slot_index: int = 0
var slot_group: String = "inventory" # "inventory", "hotbar", "armor", "chest", "craft"
var item_data: Dictionary = {}
var is_hovered: bool = false
var hotbar_num: int = 0
var placeholder_text: String = ""

var _icon_rect: TextureRect = null
var _count_label: Label = null
var _hotbar_label: Label = null


func _ready() -> void:
	custom_minimum_size = Vector2(46.0, 46.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(32.0, 32.0)
	_icon_rect.set_anchors_preset(Control.PRESET_CENTER)
	_icon_rect.offset_left = -16.0
	_icon_rect.offset_top = -16.0
	_icon_rect.offset_right = 16.0
	_icon_rect.offset_bottom = 16.0
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)

	_count_label = Label.new()
	_count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_label.offset_left = -26.0
	_count_label.offset_top = -16.0
	_count_label.offset_right = -3.0
	_count_label.offset_bottom = -1.0
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	if hotbar_num > 0:
		_hotbar_label = Label.new()
		_hotbar_label.text = str(hotbar_num)
		_hotbar_label.offset_left = 3.0
		_hotbar_label.offset_top = 1.0
		_hotbar_label.add_theme_font_size_override("font_size", 9)
		_hotbar_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35, 0.85))
		_hotbar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_hotbar_label)

	refresh()


func set_item(data: Dictionary) -> void:
	item_data = data
	refresh()


func refresh() -> void:
	queue_redraw()
	if _icon_rect == null or _count_label == null:
		return

	if item_data.is_empty() or str(item_data.get("item_id", "")).is_empty():
		_icon_rect.texture = null
		_icon_rect.visible = false
		_count_label.text = ""
		_count_label.visible = false
		return

	var item_id: String = str(item_data.get("item_id", ""))
	var count: int = int(item_data.get("count", 1))

	_icon_rect.texture = IconFactory.get_icon(item_id)
	_icon_rect.visible = true

	if count > 1:
		_count_label.text = str(count)
		_count_label.visible = true
	else:
		_count_label.text = ""
		_count_label.visible = false


func _draw() -> void:
	var sz: Vector2 = size
	# 1. Outer dark frame
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.10, 0.11, 0.14, 0.96), true)

	# 2. Recessed slot well
	var well_rect: Rect2 = Rect2(1.0, 1.0, sz.x - 2.0, sz.y - 2.0)
	var well_col: Color = Color(0.18, 0.20, 0.25, 0.94)
	if is_hovered:
		well_col = Color(0.26, 0.29, 0.36, 0.96)
	draw_rect(well_rect, well_col, true)

	# 3. Inner shadow bevel (Minecraft-style inset: top/left dark, bottom/right highlight)
	draw_line(Vector2(1.0, 1.0), Vector2(sz.x - 1.0, 1.0), Color(0.08, 0.09, 0.11, 0.90), 1.5)
	draw_line(Vector2(1.0, 1.0), Vector2(1.0, sz.y - 1.0), Color(0.08, 0.09, 0.11, 0.90), 1.5)
	draw_line(Vector2(1.0, sz.y - 1.5), Vector2(sz.x - 1.0, sz.y - 1.5), Color(0.38, 0.42, 0.50, 0.70), 1.0)
	draw_line(Vector2(sz.x - 1.5, 1.0), Vector2(sz.x - 1.5, sz.y - 1.0), Color(0.38, 0.42, 0.50, 0.70), 1.0)

	# 4. Hotbar gold accent border if in hotbar
	if slot_group == "hotbar":
		draw_rect(Rect2(0.0, 0.0, sz.x, sz.y), Color(0.85, 0.68, 0.25, 0.60), false, 1.0)

	# 5. Placeholder text for empty armor/shield slots
	if item_data.is_empty() and placeholder_text != "":
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(5.0, sz.y * 0.5 + 4.0), placeholder_text, HORIZONTAL_ALIGNMENT_CENTER, sz.x - 10.0, 9, Color(0.42, 0.46, 0.52, 0.55))

	# 6. Minecraft Durability Bar
	if not item_data.is_empty() and item_data.has("durability"):
		var dur: int = int(item_data.get("durability", -1))
		var item_id: String = str(item_data.get("item_id", ""))
		var def: Dictionary = DataRegistry.get_item(item_id)
		var max_dur: int = int(def.get("durability", 100))
		if max_dur > 0 and dur >= 0 and dur < max_dur:
			var ratio: float = clampf(float(dur) / float(max_dur), 0.0, 1.0)
			var bar_w: float = sz.x - 8.0
			var bar_x: float = 4.0
			var bar_y: float = sz.y - 5.0
			# Backing
			draw_rect(Rect2(bar_x, bar_y, bar_w, 2.0), Color(0.0, 0.0, 0.0, 0.90), true)
			# Fill (Green -> Yellow -> Red)
			var fill_col: Color = Color(0.22, 0.85, 0.25)
			if ratio < 0.25:
				fill_col = Color(0.92, 0.20, 0.20)
			elif ratio < 0.60:
				fill_col = Color(0.95, 0.80, 0.15)
			draw_rect(Rect2(bar_x, bar_y, bar_w * ratio, 2.0), fill_col, true)


func _on_mouse_entered() -> void:
	is_hovered = true
	queue_redraw()
	slot_hovered.emit(slot_index)


func _on_mouse_exited() -> void:
	is_hovered = false
	queue_redraw()
	slot_unhovered.emit(slot_index)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		var is_shift: bool = mb.shift_pressed
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			slot_clicked.emit(slot_index, mb.button_index, is_shift)
			accept_event()
