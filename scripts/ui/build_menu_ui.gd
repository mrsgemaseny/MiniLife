class_name BuildMenuUI
extends Control

const PANEL_ID: String = "build"
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")
const ResearchSys = preload("res://scripts/systems/research_system.gd")

@onready var panel_container: PanelContainer = $PanelContainer
@onready var vbox: VBoxContainer = $PanelContainer/VBoxContainer
@onready var title_label: Label = $PanelContainer/VBoxContainer/TitleLabel
@onready var structure_list: Control = $PanelContainer/VBoxContainer/StructureList

var _structures: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_structures = GameManager.load_json_indexed("structures.json")
	_setup_styled_build_menu()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.inventory_changed.connect(_on_inventory_changed)
	SignalBus.tech_tree_updated.connect(func(): if visible: refresh())


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_B or k.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()


var _selected_structure_id: String = "workbench"
var _bg_tex: TextureRect = null
var _detail_icon: TextureRect = null
var _detail_title: Label = null
var _detail_category: Label = null
var _detail_desc: Label = null
var _detail_mats: Label = null
var _detail_action_btn: Button = null


func _setup_styled_build_menu() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Fullscreen Survival Texture Backdrop
	if _bg_tex == null:
		_bg_tex = TextureRect.new()
		_bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
		if ResourceLoader.exists("res://assets/sprites/ui/fullscreen_survival_bg.jpg"):
			_bg_tex.texture = load("res://assets/sprites/ui/fullscreen_survival_bg.jpg")
		add_child(_bg_tex)
		move_child(_bg_tex, 0)

	if panel_container != null:
		panel_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel_container.offset_left = 0
		panel_container.offset_top = 0
		panel_container.offset_right = 0
		panel_container.offset_bottom = 0

		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.08, 0.40) # Tint over texture
		sb.border_color = Color(0.22, 0.24, 0.28, 0.85)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		sb.content_margin_left = 32
		sb.content_margin_right = 32
		sb.content_margin_top = 20
		sb.content_margin_bottom = 24
		panel_container.add_theme_stylebox_override("panel", sb)

	if vbox != null:
		for ch in vbox.get_children():
			vbox.remove_child(ch)
			ch.queue_free()

		vbox.add_theme_constant_override("separation", 10)

		# Top Header
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		var title_vbox: VBoxContainer = VBoxContainer.new()
		title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_vbox.add_theme_constant_override("separation", 2)
		hdr_hbox.add_child(title_vbox)

		var tlbl: Label = Label.new()
		tlbl.text = "СТАНЦИИ И ИНФРАСТРУКТУРА БАЗЫ [B]"
		tlbl.add_theme_font_size_override("font_size", 14)
		tlbl.modulate = Color(0.92, 0.90, 0.86, 1.0) # Antique ivory
		title_vbox.add_child(tlbl)

		var sublbl: Label = Label.new()
		sublbl.text = "Стационарные производственные мастерские, склады и оборонительные сооружения [ESC / B]"
		sublbl.add_theme_font_size_override("font_size", 10)
		sublbl.modulate = Color(0.55, 0.58, 0.64, 1.0)
		title_vbox.add_child(sublbl)

		var close_btn: Button = Button.new()
		close_btn.text = " ✕ ЗАКРЫТЬ [ESC] "
		close_btn.add_theme_font_size_override("font_size", 11)
		close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
		var cb_sb: StyleBoxFlat = StyleBoxFlat.new()
		cb_sb.bg_color = Color(0.18, 0.20, 0.24, 1.0)
		cb_sb.border_color = Color(0.35, 0.38, 0.44, 1.0)
		cb_sb.set_border_width_all(1)
		cb_sb.set_corner_radius_all(3)
		cb_sb.set_content_margin_all(6)
		close_btn.add_theme_stylebox_override("normal", cb_sb)
		close_btn.pressed.connect(close_panel)
		hdr_hbox.add_child(close_btn)
		vbox.add_child(hdr_hbox)

		# Horizontal Separator
		var sep: HSeparator = HSeparator.new()
		var sep_sb: StyleBoxLine = StyleBoxLine.new()
		sep_sb.color = Color(0.20, 0.22, 0.26, 0.90)
		sep_sb.thickness = 1
		sep.add_theme_stylebox_override("separator", sep_sb)
		vbox.add_child(sep)

		# Main 2-Pane Body (Catalog Grid Left + Blueprint Inspector Right)
		var body_hbox: HBoxContainer = HBoxContainer.new()
		body_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_hbox.add_theme_constant_override("separation", 16)
		vbox.add_child(body_hbox)

		# Left Pane: Scrollable 2-Column Catalog
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio = 1.85
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_hbox.add_child(scroll)

		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
		structure_list = grid

		# Right Pane: Blueprint Inspector Card
		var right_panel: PanelContainer = PanelContainer.new()
		right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_panel.size_flags_stretch_ratio = 1.0
		right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var r_sb: StyleBoxFlat = StyleBoxFlat.new()
		r_sb.bg_color = Color(0.10, 0.11, 0.13, 0.95)
		r_sb.border_color = Color(0.24, 0.26, 0.30, 0.85)
		r_sb.set_border_width_all(1)
		r_sb.set_corner_radius_all(4)
		r_sb.set_content_margin_all(14)
		right_panel.add_theme_stylebox_override("panel", r_sb)
		body_hbox.add_child(right_panel)

		var r_vbox: VBoxContainer = VBoxContainer.new()
		r_vbox.add_theme_constant_override("separation", 10)
		right_panel.add_child(r_vbox)

		var r_hdr: Label = Label.new()
		r_hdr.text = "ИНСПЕКТОР ЧЕРТЕЖА"
		r_hdr.add_theme_font_size_override("font_size", 12)
		r_hdr.modulate = Color(0.75, 0.78, 0.84)
		r_vbox.add_child(r_hdr)

		var icon_center: HBoxContainer = HBoxContainer.new()
		icon_center.alignment = BoxContainer.ALIGNMENT_CENTER
		r_vbox.add_child(icon_center)

		var icon_frame: PanelContainer = PanelContainer.new()
		icon_frame.custom_minimum_size = Vector2(80, 80)
		var if_sb: StyleBoxFlat = StyleBoxFlat.new()
		if_sb.bg_color = Color(0.14, 0.15, 0.18, 0.98)
		if_sb.border_color = Color(0.35, 0.38, 0.44, 0.85)
		if_sb.set_border_width_all(1)
		if_sb.set_corner_radius_all(4)
		icon_frame.add_theme_stylebox_override("panel", if_sb)
		icon_center.add_child(icon_frame)

		_detail_icon = TextureRect.new()
		_detail_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_frame.add_child(_detail_icon)

		_detail_title = Label.new()
		_detail_title.add_theme_font_size_override("font_size", 14)
		_detail_title.modulate = Color(0.92, 0.90, 0.86)
		r_vbox.add_child(_detail_title)

		_detail_category = Label.new()
		_detail_category.add_theme_font_size_override("font_size", 10)
		_detail_category.modulate = Color(0.60, 0.63, 0.68)
		r_vbox.add_child(_detail_category)

		_detail_desc = Label.new()
		_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_desc.add_theme_font_size_override("font_size", 10)
		_detail_desc.modulate = Color(0.78, 0.80, 0.84)
		r_vbox.add_child(_detail_desc)

		var div2: HSeparator = HSeparator.new()
		div2.add_theme_stylebox_override("separator", sep_sb)
		r_vbox.add_child(div2)

		_detail_mats = Label.new()
		_detail_mats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_mats.add_theme_font_size_override("font_size", 10)
		r_vbox.add_child(_detail_mats)

		var spacer: Control = Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		r_vbox.add_child(spacer)

		_detail_action_btn = Button.new()
		_detail_action_btn.custom_minimum_size = Vector2(0, 36)
		_detail_action_btn.add_theme_font_size_override("font_size", 11)
		var ab_sb: StyleBoxFlat = StyleBoxFlat.new()
		ab_sb.bg_color = Color(0.20, 0.22, 0.26, 1.0)
		ab_sb.border_color = Color(0.42, 0.45, 0.52, 1.0)
		ab_sb.set_border_width_all(1)
		ab_sb.set_corner_radius_all(3)
		_detail_action_btn.add_theme_stylebox_override("normal", ab_sb)
		_detail_action_btn.pressed.connect(func() -> void:
			if not _selected_structure_id.is_empty():
				close_panel()
				SignalBus.build_mode_changed.emit(_selected_structure_id)
		)
		r_vbox.add_child(_detail_action_btn)


func open_panel() -> void:
	SignalBus.ui_close_all_requested.emit()
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func refresh() -> void:
	if structure_list == null:
		return
	for child in structure_list.get_children():
		structure_list.remove_child(child)
		child.queue_free()

	var player: Node = get_tree().get_first_node_in_group("player")
	var sorted_sids: Array = _structures.keys()
	sorted_sids.sort_custom(func(a: String, b: String) -> bool:
		var req_a: String = str(_structures[a].get("tech_required", ""))
		var req_b: String = str(_structures[b].get("tech_required", ""))
		var lock_a: bool = (req_a != "" and ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_a))
		var lock_b: bool = (req_b != "" and ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_b))
		if lock_a != lock_b:
			return not lock_a
		return false
	)

	var found_selected: bool = false

	for sid in sorted_sids:
		if sid in ["floor", "wood_floor", "wall", "wood_wall", "stone_floor", "door"]:
			continue
		if sid == _selected_structure_id:
			found_selected = true

		var def: Dictionary = _structures[sid]
		var sname: String = str(def.get("name", sid.capitalize()))
		var mats: Array = def.get("materials", [])

		var req_tech: String = str(def.get("tech_required", ""))
		var min_level: int = int(def.get("min_level", 2))
		var is_level_unlocked: bool = true
		if not GameManager.sandbox_for(player) and ProgressionSystem.instance != null:
			is_level_unlocked = ProgressionSystem.instance.current_level >= min_level
		var is_tech_unlocked: bool = true
		if req_tech != "" and not GameManager.sandbox_for(player):
			if ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_tech):
				is_tech_unlocked = false

		var can_build: bool = is_level_unlocked and is_tech_unlocked and _has_materials(player, mats)
		var is_sel: bool = (sid == _selected_structure_id)

		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(260, 54)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		btn.icon = IconFactory.get_icon(sid)
		btn.expand_icon = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)

		var bsb: StyleBoxFlat = StyleBoxFlat.new()
		bsb.set_corner_radius_all(3)
		bsb.content_margin_left = 12
		bsb.content_margin_right = 12

		if is_sel:
			bsb.bg_color = Color(0.18, 0.20, 0.24, 1.0)
			bsb.border_color = Color(0.88, 0.89, 0.94, 1.0)
			bsb.set_border_width_all(2)
		elif not is_level_unlocked or not is_tech_unlocked:
			bsb.bg_color = Color(0.09, 0.10, 0.11, 0.90)
			bsb.border_color = Color(0.20, 0.22, 0.25, 0.50)
			bsb.set_border_width_all(1)
		elif can_build:
			bsb.bg_color = Color(0.13, 0.14, 0.17, 0.98)
			bsb.border_color = Color(0.38, 0.42, 0.48, 0.85)
			bsb.set_border_width_all(1)
		else:
			bsb.bg_color = Color(0.11, 0.12, 0.14, 0.95)
			bsb.border_color = Color(0.25, 0.27, 0.32, 0.70)
			bsb.set_border_width_all(1)

		btn.add_theme_stylebox_override("normal", bsb)
		btn.add_theme_stylebox_override("hover", bsb)
		btn.add_theme_stylebox_override("pressed", bsb)
		btn.add_theme_stylebox_override("focus", bsb)

		if not is_level_unlocked:
			btn.text = "   %s   [УРОВЕНЬ %d]" % [sname, min_level]
			btn.add_theme_color_override("font_color", Color(0.45, 0.48, 0.54, 1.0))
		elif not is_tech_unlocked:
			btn.text = "   %s   [ЗАКРЫТО: %s]" % [sname, req_tech.capitalize().replace("_", " ")]
			btn.add_theme_color_override("font_color", Color(0.45, 0.48, 0.54, 1.0))
		elif can_build:
			btn.text = "   %s   —   Ресурсы: %s  [ГОТОВО]" % [sname, _format_materials(mats)]
			if GameManager.sandbox_for(player):
				btn.text = sname + " — INFINITE VIRTUAL RESOURCES [READY]"
			btn.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86, 1.0))
		else:
			btn.text = "   %s   —   Ресурсы: %s  [НЕ ХВАТАЕТ]" % [sname, _format_materials(mats)]
			btn.add_theme_color_override("font_color", Color(0.72, 0.75, 0.80, 1.0))

		var structure_id_str: String = str(sid)
		btn.pressed.connect(func() -> void:
			_selected_structure_id = structure_id_str
			_update_detail_panel(player)
			refresh()
		)
		structure_list.add_child(btn)

	if not found_selected and not sorted_sids.is_empty():
		_selected_structure_id = sorted_sids[0]
	_update_detail_panel(player)


func _update_detail_panel(player: Node) -> void:
	if not _structures.has(_selected_structure_id):
		return
	var def: Dictionary = _structures[_selected_structure_id]
	var sname: String = str(def.get("name", _selected_structure_id.capitalize()))
	var mats: Array = def.get("materials", [])
	var req_tech: String = str(def.get("tech_required", ""))
	var min_level: int = int(def.get("min_level", 2))

	var is_level_unlocked: bool = true
	if not GameManager.sandbox_for(player) and ProgressionSystem.instance != null:
		is_level_unlocked = ProgressionSystem.instance.current_level >= min_level
	var is_tech_unlocked: bool = true
	if req_tech != "" and not GameManager.sandbox_for(player):
		if ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_tech):
			is_tech_unlocked = false
	var can_build: bool = is_level_unlocked and is_tech_unlocked and _has_materials(player, mats)

	if _detail_icon != null:
		_detail_icon.texture = IconFactory.get_icon(_selected_structure_id)
	if _detail_title != null:
		_detail_title.text = sname
	if _detail_category != null:
		if not is_level_unlocked:
			_detail_category.text = "Требуется уровень %d" % min_level
			_detail_category.modulate = Color(0.75, 0.45, 0.42)
		else:
			_detail_category.text = "Категория: Базовая инфраструктура" if req_tech.is_empty() else ("Требует исследования: %s" % req_tech.capitalize().replace("_", " "))
			_detail_category.modulate = Color(0.60, 0.63, 0.68) if is_tech_unlocked else Color(0.75, 0.45, 0.42)
		if GameManager.sandbox_for(player):
			_detail_category.text = "God mode: all blueprints available"
	if _detail_desc != null:
		_detail_desc.text = str(def.get("description", "Стационарное сооружение выживания. Устанавливается на подготовленной расчищенной территории базы."))
	if _detail_mats != null:
		var mat_lines: Array[String] = []
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
		for m in mats:
			if m is Dictionary:
				var mid: String = str(m.get("item_id", ""))
				var req_c: int = int(m.get("count", 1))
				var cur_c: int = inv.count_of(mid) if inv != null else 0
				mat_lines.append("• %s: %d / %d" % [mid.capitalize(), cur_c, req_c])
		_detail_mats.text = "Необходимые материалы:\n" + "\n".join(mat_lines)
		if GameManager.sandbox_for(player):
			_detail_mats.text = "INFINITE VIRTUAL RESOURCES\nNo materials consumed from inventory."
		_detail_mats.modulate = Color(0.88, 0.89, 0.92) if can_build else Color(0.75, 0.77, 0.82)

	if _detail_action_btn != null:
		_detail_action_btn.modulate = Color.WHITE
		if not is_level_unlocked:
			_detail_action_btn.text = "ТРЕБУЕТСЯ УРОВЕНЬ %d" % min_level
			_detail_action_btn.disabled = true
		elif not is_tech_unlocked:
			_detail_action_btn.text = "ТЕХНОЛОГИЯ НЕ ИЗУЧЕНА"
			_detail_action_btn.disabled = true
		elif can_build:
			_detail_action_btn.text = "ВЫБРАТЬ ЧЕРТЕЖ ДЛЯ ПОСТРОЙКИ"
			_detail_action_btn.disabled = false
		else:
			_detail_action_btn.text = "НЕДОСТАТОЧНО РЕСУРСОВ"
			_detail_action_btn.disabled = true


func _has_materials(player: Node, mats: Array) -> bool:
	if GameManager.sandbox_for(player):
		return true
	if player == null:
		return false
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if inv == null:
		return false
	for m in mats:
		if m is Dictionary:
			if not inv.has_item(str(m.get("item_id", "")), int(m.get("count", 1))):
				return false
	return true


func _format_materials(mats: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for m in mats:
		if m is Dictionary:
			parts.append("%s x%d" % [str(m.get("item_id", "")), int(m.get("count", 1))])
	return ", ".join(parts)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()
	elif visible:
		close_panel()


func _on_inventory_changed(_entity: Node, _snapshot: Dictionary) -> void:
	if visible:
		refresh()
