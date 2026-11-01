class_name FurnaceUI
extends Control

const PANEL_ID: String = "furnace"
const FurnaceSys = preload("res://scripts/systems/crafting/furnace_system.gd")

var _active_furnace_id: String = ""
var _tile_pos: Vector2i = Vector2i.ZERO

var _panel: PanelContainer = null
var _ore_label: Label = null
var _fuel_label: Label = null
var _burn_bar: ProgressBar = null
var _smelt_bar: ProgressBar = null
var _output_label: Label = null
var _collect_btn: Button = null
var _inv_container: VBoxContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.furnace_opened.connect(open_furnace)
	SignalBus.ui_close_all_requested.connect(close_furnace)
	if FurnaceSys.instance != null:
		FurnaceSys.instance.furnace_updated.connect(_on_furnace_updated)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			close_furnace()
			get_viewport().set_input_as_handled()


func open_furnace(furnace_id: String, tile_pos: Vector2i) -> void:
	_active_furnace_id = furnace_id
	_tile_pos = tile_pos
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_furnace() -> void:
	if not visible:
		return
	_active_furnace_id = ""
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -340.0
	_panel.offset_top = -220.0
	_panel.offset_right = 340.0
	_panel.offset_bottom = 220.0

	var bg_box: StyleBoxFlat = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.08, 0.08, 0.11, 0.94)
	bg_box.border_color = Color(0.92, 0.45, 0.20, 0.90)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(10)
	bg_box.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", bg_box)
	add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(main_vbox)

	# Header Bar
	var hdr: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "STONE SMELTING FURNACE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(1.0, 0.65, 0.35)
	hdr.add_child(title)

	var close_btn: Button = Button.new()
	close_btn.text = " [X] Close "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(close_furnace)
	hdr.add_child(close_btn)
	main_vbox.add_child(hdr)

	# 2-Column Layout
	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	main_vbox.add_child(cols)

	# Left Column: Furnace Machine Controls
	var f_box: VBoxContainer = VBoxContainer.new()
	f_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f_box.add_theme_constant_override("separation", 8)
	cols.add_child(f_box)

	# Ore Slot
	var ore_card: PanelContainer = _make_subpanel()
	var ore_vb: VBoxContainer = VBoxContainer.new()
	_ore_label = Label.new()
	_ore_label.text = "Raw Ore: Empty"
	_ore_label.add_theme_font_size_override("font_size", 11)
	ore_vb.add_child(_ore_label)

	var ore_btns: HBoxContainer = HBoxContainer.new()
	var btn_add_iron: Button = Button.new()
	btn_add_iron.text = "+ Iron Ore"
	btn_add_iron.add_theme_font_size_override("font_size", 10)
	btn_add_iron.pressed.connect(func(): _insert_ore("iron_ore"))
	ore_btns.add_child(btn_add_iron)

	var btn_add_copper: Button = Button.new()
	btn_add_copper.text = "+ Copper Ore"
	btn_add_copper.add_theme_font_size_override("font_size", 10)
	btn_add_copper.pressed.connect(func(): _insert_ore("copper_ore"))
	ore_btns.add_child(btn_add_copper)
	ore_vb.add_child(ore_btns)
	ore_card.add_child(ore_vb)
	f_box.add_child(ore_card)

	# Fuel Slot
	var fuel_card: PanelContainer = _make_subpanel()
	var fuel_vb: VBoxContainer = VBoxContainer.new()
	_fuel_label = Label.new()
	_fuel_label.text = "Fuel: Empty"
	_fuel_label.add_theme_font_size_override("font_size", 11)
	fuel_vb.add_child(_fuel_label)

	_burn_bar = ProgressBar.new()
	_burn_bar.custom_minimum_size = Vector2(0.0, 10.0)
	_burn_bar.max_value = 20.0
	_burn_bar.value = 0.0
	_burn_bar.show_percentage = false
	fuel_vb.add_child(_burn_bar)

	var fuel_btns: HBoxContainer = HBoxContainer.new()
	var btn_add_coal: Button = Button.new()
	btn_add_coal.text = "+ Add Coal (+20s)"
	btn_add_coal.add_theme_font_size_override("font_size", 10)
	btn_add_coal.pressed.connect(func(): _insert_fuel("coal"))
	fuel_btns.add_child(btn_add_coal)

	var btn_add_wood: Button = Button.new()
	btn_add_wood.text = "+ Add Wood (+8s)"
	btn_add_wood.add_theme_font_size_override("font_size", 10)
	btn_add_wood.pressed.connect(func(): _insert_fuel("wood"))
	fuel_btns.add_child(btn_add_wood)
	fuel_vb.add_child(fuel_btns)
	fuel_card.add_child(fuel_vb)
	f_box.add_child(fuel_card)

	# Smelting Progress Bar
	var p_card: PanelContainer = _make_subpanel()
	var p_vb: VBoxContainer = VBoxContainer.new()
	var p_title: Label = Label.new()
	p_title.text = "Smelting Progress"
	p_title.add_theme_font_size_override("font_size", 10)
	p_vb.add_child(p_title)

	_smelt_bar = ProgressBar.new()
	_smelt_bar.custom_minimum_size = Vector2(0.0, 14.0)
	_smelt_bar.max_value = 1.0
	_smelt_bar.value = 0.0
	p_vb.add_child(_smelt_bar)
	p_card.add_child(p_vb)
	f_box.add_child(p_card)

	# Output Chamber
	var out_card: PanelContainer = _make_subpanel()
	var out_vb: VBoxContainer = VBoxContainer.new()
	_output_label = Label.new()
	_output_label.text = "Output: Empty"
	_output_label.add_theme_font_size_override("font_size", 11)
	_output_label.modulate = Color(0.95, 0.82, 0.35)
	out_vb.add_child(_output_label)

	_collect_btn = Button.new()
	_collect_btn.text = "★ COLLECT INGOTS ★"
	_collect_btn.add_theme_font_size_override("font_size", 11)
	_collect_btn.pressed.connect(_on_collect_pressed)
	out_vb.add_child(_collect_btn)
	out_card.add_child(out_vb)
	f_box.add_child(out_card)

	# Right Column: Player Inventory Overview
	var r_box: VBoxContainer = VBoxContainer.new()
	r_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_box.add_theme_constant_override("separation", 6)
	cols.add_child(r_box)

	var inv_title: Label = Label.new()
	inv_title.text = "PLAYER SMELTING MATERIALS"
	inv_title.add_theme_font_size_override("font_size", 12)
	inv_title.modulate = Color(0.75, 0.85, 0.95)
	r_box.add_child(inv_title)

	var inv_scroll: ScrollContainer = ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_box.add_child(inv_scroll)

	_inv_container = VBoxContainer.new()
	_inv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_container.add_theme_constant_override("separation", 4)
	inv_scroll.add_child(_inv_container)


func _make_subpanel() -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.85)
	sb.border_color = Color(0.24, 0.28, 0.34, 0.70)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	pc.add_theme_stylebox_override("panel", sb)
	return pc


func _insert_ore(item_id: String) -> void:
	if FurnaceSys.instance != null and _active_furnace_id != "":
		var player: Node = get_tree().get_first_node_in_group("player")
		FurnaceSys.instance.add_ore(_active_furnace_id, player, item_id, 1)
		refresh()


func _insert_fuel(item_id: String) -> void:
	if FurnaceSys.instance != null and _active_furnace_id != "":
		var player: Node = get_tree().get_first_node_in_group("player")
		FurnaceSys.instance.add_fuel(_active_furnace_id, player, item_id, 1)
		refresh()


func _on_collect_pressed() -> void:
	if FurnaceSys.instance != null and _active_furnace_id != "":
		var player: Node = get_tree().get_first_node_in_group("player")
		FurnaceSys.instance.take_output(_active_furnace_id, player)
		refresh()


func _on_furnace_updated(fid: String) -> void:
	if visible and fid == _active_furnace_id:
		refresh()


func refresh() -> void:
	if _active_furnace_id == "" or FurnaceSys.instance == null:
		return

	var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
	var ore_item: String = str(state.get("ore_item", ""))
	var ore_cnt: int = int(state.get("ore_count", 0))
	_ore_label.text = "Raw Ore: %s (x%d)" % [ore_item.capitalize() if ore_item != "" else "Empty", ore_cnt]

	var fuel_item: String = str(state.get("fuel_item", ""))
	var fuel_cnt: int = int(state.get("fuel_count", 0))
	var burn_rem: float = float(state.get("burn_remaining", 0.0))
	_fuel_label.text = "Fuel: %s (x%d) | Fire: %.1fs" % [fuel_item.capitalize() if fuel_item != "" else "Empty", fuel_cnt, burn_rem]
	_burn_bar.value = burn_rem

	var prog: float = float(state.get("smelt_progress", 0.0))
	_smelt_bar.value = prog

	var out_item: String = str(state.get("out_item", ""))
	var out_cnt: int = int(state.get("out_count", 0))
	_output_label.text = "Output: %s (x%d)" % [out_item.capitalize() if out_item != "" else "Empty", out_cnt]
	_collect_btn.disabled = (out_cnt <= 0)

	# Populate Player Inventory items
	for c in _inv_container.get_children():
		_inv_container.remove_child(c)
		c.queue_free()

	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if inv != null:
			var relevant_keys: Array[String] = ["coal", "wood", "iron_ore", "copper_ore"]
			for k in relevant_keys:
				var count: int = inv.get_item_count(k)
				var btn: Button = Button.new()
				btn.text = "%s: %d" % [k.capitalize(), count]
				btn.add_theme_font_size_override("font_size", 10)
				btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				btn.disabled = (count <= 0)
				btn.pressed.connect(func():
					if k in ["coal", "wood"]:
						_insert_fuel(k)
					else:
						_insert_ore(k)
				)
				_inv_container.add_child(btn)
