class_name FurnaceUI
extends Control

const PANEL_ID: String = "furnace"
const FurnaceSys = preload("res://scripts/systems/crafting/furnace_system.gd")
const MCSlot = preload("res://scripts/ui/minecraft_slot.gd")

var _active_furnace_id: String = ""
var _tile_pos: Vector2i = Vector2i.ZERO

var _panel: PanelContainer = null
var _input_slot: Control = null
var _fuel_slot: Control = null
var _output_slot: Control = null
var _flame_widget: Control = null
var _arrow_widget: Control = null

var _inv_slots: Array[Control] = []
var _hotbar_slots: Array[Control] = []

# Floating cursor stack for Minecraft drag & drop
var _cursor_stack: Dictionary = {}
var _cursor_display: Control = null
var _cursor_icon: TextureRect = null
var _cursor_count_lbl: Label = null

# Minecraft Floating Tooltip
var _tooltip_panel: PanelContainer = null
var _tt_title: Label = null
var _tt_stats: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.furnace_opened.connect(open_furnace)
	SignalBus.ui_close_all_requested.connect(close_furnace)
	if FurnaceSys.instance != null:
		FurnaceSys.instance.furnace_updated.connect(_on_furnace_updated)
	SignalBus.inventory_changed.connect(func(_ent, _snap):
		if visible:
			refresh()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			close_furnace()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	var mpos: Vector2 = get_global_mouse_position()

	# Update floating cursor item
	if _cursor_display != null:
		if not _cursor_stack.is_empty():
			_cursor_display.visible = true
			_cursor_display.global_position = mpos + Vector2(12.0, 12.0)
		else:
			_cursor_display.visible = false

	# Update floating tooltip position
	if _tooltip_panel != null and _tooltip_panel.visible:
		var vp_sz: Vector2 = get_viewport_rect().size
		var tt_sz: Vector2 = _tooltip_panel.size
		var tx: float = mpos.x + 16.0
		var ty: float = mpos.y + 16.0
		if tx + tt_sz.x > vp_sz.x - 10.0:
			tx = mpos.x - tt_sz.x - 10.0
		if ty + tt_sz.y > vp_sz.y - 10.0:
			ty = mpos.y - tt_sz.y - 10.0
		_tooltip_panel.global_position = Vector2(maxf(10.0, tx), maxf(10.0, ty))


func open_furnace(furnace_id: String, tile_pos: Vector2i) -> void:
	_active_furnace_id = furnace_id
	_tile_pos = tile_pos
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_furnace() -> void:
	if not visible:
		return
	_return_cursor_stack_to_player()
	_hide_tooltip()
	_active_furnace_id = ""
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Full-screen dark backdrop overlay (freezes focus, blocks world clicks)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and not _cursor_stack.is_empty():
			_drop_cursor_item()
	)
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -260.0
	_panel.offset_top = -250.0
	_panel.offset_right = 260.0
	_panel.offset_bottom = 250.0

	var bg_box: StyleBoxFlat = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.12, 0.13, 0.16, 0.96)
	bg_box.border_color = Color(0.92, 0.48, 0.22, 0.92)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(8)
	bg_box.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", bg_box)
	add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(main_vbox)

	# 1. Header Bar
	var hdr: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "STONE SMELTING FURNACE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(1.0, 0.70, 0.35)
	hdr.add_child(title)

	var close_btn: Button = Button.new()
	close_btn.text = " [X] "
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(close_furnace)
	hdr.add_child(close_btn)
	main_vbox.add_child(hdr)

	# 2. Machine Smelting Chamber
	var machine_box: PanelContainer = PanelContainer.new()
	var m_sb: StyleBoxFlat = StyleBoxFlat.new()
	m_sb.bg_color = Color(0.08, 0.08, 0.10, 0.90)
	m_sb.border_color = Color(0.24, 0.25, 0.30, 0.85)
	m_sb.set_border_width_all(1)
	m_sb.set_corner_radius_all(6)
	m_sb.set_content_margin_all(12)
	machine_box.add_theme_stylebox_override("panel", m_sb)
	main_vbox.add_child(machine_box)

	var machine_hbox: HBoxContainer = HBoxContainer.new()
	machine_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	machine_hbox.add_theme_constant_override("separation", 24)
	machine_box.add_child(machine_hbox)

	# Left Stack: Input Slot + Fire Flame + Fuel Slot
	var left_stack: VBoxContainer = VBoxContainer.new()
	left_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	left_stack.add_theme_constant_override("separation", 6)
	machine_hbox.add_child(left_stack)

	_input_slot = MCSlot.new()
	_input_slot.slot_group = "furnace_input"
	_input_slot.placeholder_text = "Ore/Meat"
	_input_slot.slot_clicked.connect(func(_idx, btn, shift): _on_furnace_slot_clicked("input", btn, shift))
	_input_slot.slot_hovered.connect(func(_idx): _on_furnace_slot_hovered("input"))
	_input_slot.slot_unhovered.connect(func(_idx): _hide_tooltip())
	left_stack.add_child(_input_slot)

	# Animated Fire Flame Widget
	_flame_widget = Control.new()
	_flame_widget.custom_minimum_size = Vector2(28.0, 20.0)
	_flame_widget.draw.connect(_draw_flame)
	left_stack.add_child(_flame_widget)

	_fuel_slot = MCSlot.new()
	_fuel_slot.slot_group = "furnace_fuel"
	_fuel_slot.placeholder_text = "Fuel"
	_fuel_slot.slot_clicked.connect(func(_idx, btn, shift): _on_furnace_slot_clicked("fuel", btn, shift))
	_fuel_slot.slot_hovered.connect(func(_idx): _on_furnace_slot_hovered("fuel"))
	_fuel_slot.slot_unhovered.connect(func(_idx): _hide_tooltip())
	left_stack.add_child(_fuel_slot)

	# Smelt Arrow Progress Widget
	_arrow_widget = Control.new()
	_arrow_widget.custom_minimum_size = Vector2(40.0, 24.0)
	_arrow_widget.draw.connect(_draw_arrow)
	machine_hbox.add_child(_arrow_widget)

	# Right Stack: Output Slot
	var right_stack: VBoxContainer = VBoxContainer.new()
	right_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	machine_hbox.add_child(right_stack)

	_output_slot = MCSlot.new()
	_output_slot.slot_group = "furnace_output"
	_output_slot.placeholder_text = "Result"
	_output_slot.custom_minimum_size = Vector2(48.0, 48.0)
	_output_slot.slot_clicked.connect(func(_idx, btn, shift): _on_furnace_slot_clicked("output", btn, shift))
	_output_slot.slot_hovered.connect(func(_idx): _on_furnace_slot_hovered("output"))
	_output_slot.slot_unhovered.connect(func(_idx): _hide_tooltip())
	right_stack.add_child(_output_slot)

	# 3. Separator
	var sep: HSeparator = HSeparator.new()
	main_vbox.add_child(sep)

	# 4. Player Inventory Section
	var inv_hdr: Label = Label.new()
	inv_hdr.text = "PLAYER INVENTORY"
	inv_hdr.add_theme_font_size_override("font_size", 10)
	inv_hdr.modulate = Color(0.68, 0.74, 0.82)
	main_vbox.add_child(inv_hdr)

	# 3x8 Backpack Grid (indices 8 to 31)
	var inv_grid: GridContainer = GridContainer.new()
	inv_grid.columns = 8
	inv_grid.add_theme_constant_override("h_separation", 4)
	inv_grid.add_theme_constant_override("v_separation", 4)
	main_vbox.add_child(inv_grid)

	_inv_slots.clear()
	for i in range(8, 32):
		var s: Control = MCSlot.new()
		s.slot_index = i
		s.slot_group = "inventory"
		s.slot_clicked.connect(_on_player_slot_clicked)
		s.slot_hovered.connect(_on_player_slot_hovered)
		s.slot_unhovered.connect(func(_idx): _hide_tooltip())
		_inv_slots.append(s)
		inv_grid.add_child(s)

	# 1x8 Hotbar Grid (indices 0 to 7)
	var hotbar_grid: GridContainer = GridContainer.new()
	hotbar_grid.columns = 8
	hotbar_grid.add_theme_constant_override("h_separation", 4)
	hotbar_grid.add_theme_constant_override("v_separation", 4)
	main_vbox.add_child(hotbar_grid)

	_hotbar_slots.clear()
	for i in range(8):
		var s: Control = MCSlot.new()
		s.slot_index = i
		s.slot_group = "hotbar"
		s.hotbar_num = i + 1
		s.slot_clicked.connect(_on_player_slot_clicked)
		s.slot_hovered.connect(_on_player_slot_hovered)
		s.slot_unhovered.connect(func(_idx): _hide_tooltip())
		_hotbar_slots.append(s)
		hotbar_grid.add_child(s)

	# Floating cursor display
	_cursor_display = Control.new()
	_cursor_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_display.visible = false
	_cursor_display.z_index = 120

	_cursor_icon = TextureRect.new()
	_cursor_icon.custom_minimum_size = Vector2(32.0, 32.0)
	_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_display.add_child(_cursor_icon)

	_cursor_count_lbl = Label.new()
	_cursor_count_lbl.offset_left = 18.0
	_cursor_count_lbl.offset_top = 16.0
	_cursor_count_lbl.offset_right = 44.0
	_cursor_count_lbl.offset_bottom = 32.0
	_cursor_count_lbl.add_theme_font_size_override("font_size", 11)
	_cursor_count_lbl.add_theme_color_override("font_color", Color.WHITE)
	_cursor_count_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_cursor_count_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_cursor_count_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_cursor_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_display.add_child(_cursor_count_lbl)
	add_child(_cursor_display)

	# Floating Tooltip
	_build_floating_tooltip()


func _build_floating_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.visible = false
	_tooltip_panel.z_index = 130

	var tt_sb: StyleBoxFlat = StyleBoxFlat.new()
	tt_sb.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	tt_sb.border_color = Color(0.85, 0.55, 0.25, 0.90)
	tt_sb.set_border_width_all(1)
	tt_sb.set_corner_radius_all(5)
	tt_sb.set_content_margin_all(8)
	_tooltip_panel.add_theme_stylebox_override("panel", tt_sb)
	add_child(_tooltip_panel)

	var tt_vbox: VBoxContainer = VBoxContainer.new()
	tt_vbox.add_theme_constant_override("separation", 3)
	_tooltip_panel.add_child(tt_vbox)

	_tt_title = Label.new()
	_tt_title.add_theme_font_size_override("font_size", 12)
	tt_vbox.add_child(_tt_title)

	_tt_stats = Label.new()
	_tt_stats.add_theme_font_size_override("font_size", 10)
	_tt_stats.modulate = Color(0.80, 0.85, 0.90)
	tt_vbox.add_child(_tt_stats)


func _draw_flame() -> void:
	if _flame_widget == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, _flame_widget.size)
	var cx: float = rect.size.x * 0.5
	var cy: float = rect.size.y * 0.5

	var is_burning: bool = false
	var ratio: float = 0.0
	if _active_furnace_id != "" and FurnaceSys.instance != null:
		var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
		var max_b: float = float(state.get("max_burn_time", 8.0))
		if max_b <= 0.0:
			max_b = 8.0
		var cur_b: float = float(state.get("burn_remaining", 0.0))
		if cur_b > 0.0:
			is_burning = true
			ratio = clampf(cur_b / max_b, 0.0, 1.0)

	# Draw unlit ember / hearth base
	_flame_widget.draw_rect(Rect2(cx - 8.0, cy - 6.0, 16.0, 12.0), Color(0.18, 0.16, 0.18), true)

	if is_burning:
		var h: float = 14.0 * ratio
		var flame_pts: PackedVector2Array = [
			Vector2(cx, cy + 6.0 - h),
			Vector2(cx + 6.0, cy + 6.0),
			Vector2(cx - 6.0, cy + 6.0)
		]
		_flame_widget.draw_colored_polygon(flame_pts, Color(1.0, 0.55, 0.15))
		# Inner hot core
		var core_pts: PackedVector2Array = [
			Vector2(cx, cy + 6.0 - (h * 0.6)),
			Vector2(cx + 3.0, cy + 6.0),
			Vector2(cx - 3.0, cy + 6.0)
		]
		_flame_widget.draw_colored_polygon(core_pts, Color(1.0, 0.95, 0.40))


func _draw_arrow() -> void:
	if _arrow_widget == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, _arrow_widget.size)
	var cx: float = rect.size.x * 0.5
	var cy: float = rect.size.y * 0.5

	var prog: float = 0.0
	if _active_furnace_id != "" and FurnaceSys.instance != null:
		var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
		prog = clampf(float(state.get("smelt_progress", 0.0)), 0.0, 1.0)

	# Base recessed arrow (dark slot)
	_arrow_widget.draw_rect(Rect2(cx - 16.0, cy - 3.0, 20.0, 6.0), Color(0.16, 0.17, 0.20), true)
	var head_bg: PackedVector2Array = [
		Vector2(cx + 4.0, cy - 8.0),
		Vector2(cx + 16.0, cy),
		Vector2(cx + 4.0, cy + 8.0)
	]
	_arrow_widget.draw_colored_polygon(head_bg, Color(0.16, 0.17, 0.20))

	# Filled progress arrow (gold fill)
	if prog > 0.0:
		var fill_w: float = 32.0 * prog
		var shaft_w: float = clampf(fill_w, 0.0, 20.0)
		if shaft_w > 0.0:
			_arrow_widget.draw_rect(Rect2(cx - 16.0, cy - 3.0, shaft_w, 6.0), Color(0.96, 0.80, 0.35), true)
		if fill_w > 20.0:
			var head_ratio: float = (fill_w - 20.0) / 12.0
			var head_fg: PackedVector2Array = [
				Vector2(cx + 4.0, cy - 8.0 * head_ratio),
				Vector2(cx + 4.0 + (12.0 * head_ratio), cy),
				Vector2(cx + 4.0, cy + 8.0 * head_ratio)
			]
			_arrow_widget.draw_colored_polygon(head_fg, Color(0.96, 0.80, 0.35))


func _on_furnace_updated(fid: String) -> void:
	if visible and fid == _active_furnace_id:
		refresh()


func refresh() -> void:
	if _active_furnace_id == "" or FurnaceSys.instance == null:
		return

	var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)

	# Input slot
	var in_item: String = str(state.get("ore_item", ""))
	var in_cnt: int = int(state.get("ore_count", 0))
	if _input_slot != null:
		_input_slot.set_item({"item_id": in_item, "count": in_cnt, "durability": -1} if in_cnt > 0 else {})

	# Fuel slot
	var fuel_item: String = str(state.get("fuel_item", ""))
	var fuel_cnt: int = int(state.get("fuel_count", 0))
	if _fuel_slot != null:
		_fuel_slot.set_item({"item_id": fuel_item, "count": fuel_cnt, "durability": -1} if fuel_cnt > 0 else {})

	# Output slot
	var out_item: String = str(state.get("out_item", ""))
	var out_cnt: int = int(state.get("out_count", 0))
	if _output_slot != null:
		_output_slot.set_item({"item_id": out_item, "count": out_cnt, "durability": -1} if out_cnt > 0 else {})

	# Redraw animated widgets
	if _flame_widget != null:
		_flame_widget.queue_redraw()
	if _arrow_widget != null:
		_arrow_widget.queue_redraw()

	# Refresh player backpack & hotbar
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv != null:
		for i in range(_hotbar_slots.size()):
			_hotbar_slots[i].set_item(inv.get_slot(i))
		for i in range(_inv_slots.size()):
			_inv_slots[i].set_item(inv.get_slot(i + 8))

	_update_cursor_display()


func _on_furnace_slot_clicked(slot_type: String, mouse_btn: int, shift_pressed: bool) -> void:
	if _active_furnace_id == "" or FurnaceSys.instance == null:
		return
	var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null

	if slot_type == "output":
		var out_id: String = str(state.get("out_item", ""))
		var out_cnt: int = int(state.get("out_count", 0))
		if out_cnt <= 0 or out_id == "":
			return
		if shift_pressed and inv != null:
			FurnaceSys.instance.take_output(_active_furnace_id, player)
		else:
			if _cursor_stack.is_empty():
				_cursor_stack = {"item_id": out_id, "count": out_cnt, "durability": -1}
				state["out_item"] = ""
				state["out_count"] = 0
			elif str(_cursor_stack.get("item_id", "")) == out_id:
				_cursor_stack["count"] = int(_cursor_stack["count"]) + out_cnt
				state["out_item"] = ""
				state["out_count"] = 0
	elif slot_type == "input":
		var cur_in: String = str(state.get("ore_item", ""))
		var cur_cnt: int = int(state.get("ore_count", 0))
		if _cursor_stack.is_empty():
			if cur_cnt > 0:
				if mouse_btn == MOUSE_BUTTON_RIGHT and cur_cnt > 1:
					var take: int = int(ceil(float(cur_cnt) / 2.0))
					_cursor_stack = {"item_id": cur_in, "count": take, "durability": -1}
					state["ore_count"] = cur_cnt - take
				else:
					_cursor_stack = {"item_id": cur_in, "count": cur_cnt, "durability": -1}
					state["ore_item"] = ""
					state["ore_count"] = 0
		else:
			var c_id: String = str(_cursor_stack.get("item_id", ""))
			if FurnaceSys.is_valid_input(c_id):
				if cur_cnt == 0 or cur_in == c_id:
					state["ore_item"] = c_id
					if mouse_btn == MOUSE_BUTTON_RIGHT:
						state["ore_count"] = cur_cnt + 1
						_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
					else:
						state["ore_count"] = cur_cnt + int(_cursor_stack.get("count", 1))
						_cursor_stack["count"] = 0
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}
	elif slot_type == "fuel":
		var cur_fuel: String = str(state.get("fuel_item", ""))
		var cur_cnt: int = int(state.get("fuel_count", 0))
		if _cursor_stack.is_empty():
			if cur_cnt > 0:
				if mouse_btn == MOUSE_BUTTON_RIGHT and cur_cnt > 1:
					var take: int = int(ceil(float(cur_cnt) / 2.0))
					_cursor_stack = {"item_id": cur_fuel, "count": take, "durability": -1}
					state["fuel_count"] = cur_cnt - take
				else:
					_cursor_stack = {"item_id": cur_fuel, "count": cur_cnt, "durability": -1}
					state["fuel_item"] = ""
					state["fuel_count"] = 0
		else:
			var c_id: String = str(_cursor_stack.get("item_id", ""))
			if FurnaceSys.is_valid_fuel(c_id):
				if cur_cnt == 0 or cur_fuel == c_id:
					state["fuel_item"] = c_id
					if mouse_btn == MOUSE_BUTTON_RIGHT:
						state["fuel_count"] = cur_cnt + 1
						_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
					else:
						state["fuel_count"] = cur_cnt + int(_cursor_stack.get("count", 1))
						_cursor_stack["count"] = 0
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}

	refresh()


func _on_player_slot_clicked(slot_index: int, mouse_btn: int, shift_pressed: bool) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv == null:
		return

	var slot_data: Dictionary = inv.get_slot(slot_index)

	if shift_pressed:
		if slot_data.is_empty():
			return
		var it_id: String = str(slot_data.get("item_id", ""))
		var it_cnt: int = int(slot_data.get("count", 1))
		var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
		if FurnaceSys.is_valid_fuel(it_id):
			var cur_f: String = str(state.get("fuel_item", ""))
			if cur_f == "" or cur_f == it_id:
				state["fuel_item"] = it_id
				state["fuel_count"] = int(state.get("fuel_count", 0)) + it_cnt
				inv.set_slot(slot_index, {})
		elif FurnaceSys.is_valid_input(it_id):
			var cur_i: String = str(state.get("ore_item", ""))
			if cur_i == "" or cur_i == it_id:
				state["ore_item"] = it_id
				state["ore_count"] = int(state.get("ore_count", 0)) + it_cnt
				inv.set_slot(slot_index, {})
		else:
			inv.quick_move_slot(slot_index)
		refresh()
		return

	# Normal Left / Right click stack management
	if _cursor_stack.is_empty():
		if not slot_data.is_empty():
			if mouse_btn == MOUSE_BUTTON_RIGHT and int(slot_data.get("count", 1)) > 1:
				var total: int = int(slot_data.get("count", 1))
				var take: int = int(ceil(float(total) / 2.0))
				_cursor_stack = {"item_id": str(slot_data.get("item_id")), "count": take, "durability": int(slot_data.get("durability", -1))}
				slot_data["count"] = total - take
				inv.set_slot(slot_index, slot_data)
			else:
				_cursor_stack = slot_data.duplicate(true)
				inv.set_slot(slot_index, {})
	else:
		if slot_data.is_empty():
			if mouse_btn == MOUSE_BUTTON_RIGHT:
				inv.set_slot(slot_index, {"item_id": str(_cursor_stack.get("item_id")), "count": 1, "durability": int(_cursor_stack.get("durability", -1))})
				_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
				if int(_cursor_stack["count"]) <= 0:
					_cursor_stack = {}
			else:
				inv.set_slot(slot_index, _cursor_stack.duplicate(true))
				_cursor_stack = {}
		else:
			var c_id: String = str(_cursor_stack.get("item_id", ""))
			var s_id: String = str(slot_data.get("item_id", ""))
			if c_id == s_id and int(_cursor_stack.get("durability", -1)) == int(slot_data.get("durability", -1)):
				var def: Dictionary = DataRegistry.get_item(c_id)
				var limit: int = int(def.get("stack_limit", 64))
				var s_cnt: int = int(slot_data.get("count", 1))
				var c_cnt: int = int(_cursor_stack.get("count", 1))
				if mouse_btn == MOUSE_BUTTON_RIGHT:
					if s_cnt < limit:
						slot_data["count"] = s_cnt + 1
						_cursor_stack["count"] = c_cnt - 1
						if int(_cursor_stack["count"]) <= 0:
							_cursor_stack = {}
						inv.set_slot(slot_index, slot_data)
				else:
					var space: int = limit - s_cnt
					var transfer: int = mini(space, c_cnt)
					slot_data["count"] = s_cnt + transfer
					_cursor_stack["count"] = c_cnt - transfer
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}
					inv.set_slot(slot_index, slot_data)
			else:
				# Swap
				var tmp: Dictionary = slot_data.duplicate(true)
				inv.set_slot(slot_index, _cursor_stack.duplicate(true))
				_cursor_stack = tmp

	refresh()


func _on_player_slot_hovered(slot_index: int) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv != null:
		var s: Dictionary = inv.get_slot(slot_index)
		_show_item_tooltip(s)


func _on_furnace_slot_hovered(slot_type: String) -> void:
	if _active_furnace_id == "" or FurnaceSys.instance == null:
		return
	var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
	var item_id: String = ""
	var cnt: int = 0
	if slot_type == "input":
		item_id = str(state.get("ore_item", ""))
		cnt = int(state.get("ore_count", 0))
	elif slot_type == "fuel":
		item_id = str(state.get("fuel_item", ""))
		cnt = int(state.get("fuel_count", 0))
	elif slot_type == "output":
		item_id = str(state.get("out_item", ""))
		cnt = int(state.get("out_count", 0))

	if item_id != "" and cnt > 0:
		_show_item_tooltip({"item_id": item_id, "count": cnt, "durability": -1})
	else:
		_hide_tooltip()


func _show_item_tooltip(slot_data: Dictionary) -> void:
	if slot_data.is_empty() or str(slot_data.get("item_id", "")) == "":
		_hide_tooltip()
		return
	var it_id: String = str(slot_data.get("item_id", ""))
	var def: Dictionary = DataRegistry.get_item(it_id)
	var dname: String = str(def.get("name", it_id.capitalize()))
	_tt_title.text = dname
	_tt_title.modulate = Color(0.96, 0.86, 0.45)
	_tt_stats.text = "Type: %s  |  Count: %d" % [str(def.get("type", "Material")).capitalize(), int(slot_data.get("count", 1))]
	_tooltip_panel.visible = true


func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false


func _update_cursor_display() -> void:
	if _cursor_display == null:
		return
	if _cursor_stack.is_empty():
		_cursor_display.visible = false
	else:
		_cursor_display.visible = true
		var it_id: String = str(_cursor_stack.get("item_id", ""))
		var cnt: int = int(_cursor_stack.get("count", 1))
		var icon_tex: Texture2D = ItemIconFactory.get_icon(it_id)
		_cursor_icon.texture = icon_tex
		_cursor_count_lbl.text = str(cnt) if cnt > 1 else ""


func _drop_cursor_item() -> void:
	if _cursor_stack.is_empty():
		return
	var it_id: String = str(_cursor_stack.get("item_id", ""))
	var cnt: int = int(_cursor_stack.get("count", 1))
	_cursor_stack = {}
	_update_cursor_display()
	SignalBus.item_dropped.emit(it_id, cnt)
	SignalBus.notification_posted.emit("Dropped %s x%d" % [it_id.capitalize(), cnt])


func _return_cursor_stack_to_player() -> void:
	if _cursor_stack.is_empty():
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv != null:
		inv.add_item(str(_cursor_stack.get("item_id", "")), int(_cursor_stack.get("count", 1)))
	_cursor_stack = {}
	_update_cursor_display()
