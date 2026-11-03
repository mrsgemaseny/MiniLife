class_name CraftMenuUI
extends Control

const PANEL_ID: String = "craft"
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")
const ResearchSys = preload("res://scripts/systems/research_system.gd")

@onready var panel_container: PanelContainer = $PanelContainer

var _active_station: String = ""
var _recipes: Dictionary = {}
var _current_category: String = "all"
var _category_buttons: Dictionary = {}
var _selected_recipe_id: String = ""
var _bg_tex: TextureRect = null

# Dual-Pane UI Elements
var _station_label: Label = null
var _recipe_list_box: VBoxContainer = null
var _scroll_container: ScrollContainer = null

# Right-hand Workshop Inspector & Anvil
var _insp_icon_rect: TextureRect = null
var _insp_title_lbl: Label = null
var _insp_type_lbl: Label = null
var _insp_desc_lbl: Label = null
var _insp_stats_lbl: Label = null
var _insp_station_lbl: Label = null
var _insp_tech_lbl: Label = null
var _insp_mats_box: VBoxContainer = null
var _insp_craft1_btn: Button = null
var _insp_craft5_btn: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_recipes = GameManager.load_json_indexed("recipes.json")
	_setup_styled_craft_menu()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.craft_station_opened.connect(_on_craft_station_opened)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.inventory_changed.connect(_on_inventory_changed)
	SignalBus.tech_tree_updated.connect(func(): if visible: refresh())


func _setup_styled_craft_menu() -> void:
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
		sb.border_color = Color(0.20, 0.22, 0.26, 0.85)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		sb.content_margin_left = 32
		sb.content_margin_right = 32
		sb.content_margin_top = 20
		sb.content_margin_bottom = 24
		panel_container.add_theme_stylebox_override("panel", sb)

		for ch in panel_container.get_children():
			panel_container.remove_child(ch)
			ch.queue_free()

		var main_vbox: VBoxContainer = VBoxContainer.new()
		main_vbox.add_theme_constant_override("separation", 10)
		panel_container.add_child(main_vbox)

		# 1. Header Bar
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		var title_vbox: VBoxContainer = VBoxContainer.new()
		title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_vbox.add_theme_constant_override("separation", 2)
		hdr_hbox.add_child(title_vbox)

		_station_label = Label.new()
		_station_label.text = "МАСТЕРСКАЯ И КУЗНИЦА  —  [ Верстак ]"
		_station_label.add_theme_font_size_override("font_size", 14)
		_station_label.modulate = Color(0.92, 0.90, 0.86, 1.0)
		title_vbox.add_child(_station_label)

		var sub_lbl: Label = Label.new()
		sub_lbl.text = "Изготовление оружия, доспехов, орудий труда и припасов [ESC / C]"
		sub_lbl.add_theme_font_size_override("font_size", 10)
		sub_lbl.modulate = Color(0.55, 0.58, 0.64, 1.0)
		title_vbox.add_child(sub_lbl)

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
		main_vbox.add_child(hdr_hbox)

		# 2. Category Tab Row (Weathered Iron Tabs - NO YELLOW, NO BLUE)
		var cat_hbox: HBoxContainer = HBoxContainer.new()
		cat_hbox.add_theme_constant_override("separation", 6)
		var cats: Array[Dictionary] = [
			{"id": "all", "label": "Все рецепты"},
			{"id": "tools", "label": "Оружие и орудия"},
			{"id": "armor", "label": "Броня и щиты"},
			{"id": "stations", "label": "Станки и дерево"},
			{"id": "survival", "label": "Выживание и медицина"}
		]
		for c in cats:
			var cid: String = str(c.get("id"))
			var clbl: String = str(c.get("label"))
			var cbtn: Button = Button.new()
			cbtn.text = " " + clbl + " "
			cbtn.add_theme_font_size_override("font_size", 10)
			cbtn.add_theme_color_override("font_color", Color(0.85, 0.86, 0.90, 1.0))
			var cbsb: StyleBoxFlat = StyleBoxFlat.new()
			cbsb.bg_color = Color(0.14, 0.16, 0.19, 0.95)
			cbsb.border_color = Color(0.28, 0.30, 0.36, 1.0)
			cbsb.set_border_width_all(1)
			cbsb.set_corner_radius_all(3)
			cbsb.content_margin_left = 12
			cbsb.content_margin_right = 12
			cbsb.content_margin_top = 5
			cbsb.content_margin_bottom = 5
			cbtn.add_theme_stylebox_override("normal", cbsb)
			cbtn.pressed.connect(func():
				_current_category = cid
				refresh()
			)
			_category_buttons[cid] = cbtn
			cat_hbox.add_child(cbtn)
		main_vbox.add_child(cat_hbox)

		var sep: HSeparator = HSeparator.new()
		var sep_sb: StyleBoxLine = StyleBoxLine.new()
		sep_sb.color = Color(0.20, 0.22, 0.26, 0.90)
		sep_sb.thickness = 1
		sep.add_theme_stylebox_override("separator", sep_sb)
		main_vbox.add_child(sep)

		# 3. Dual-Pane Content Body (Left: Recipe Catalog, Right: Recipe Inspector & Forge Anvil)
		var body_hbox: HBoxContainer = HBoxContainer.new()
		body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_hbox.add_theme_constant_override("separation", 16)
		main_vbox.add_child(body_hbox)

		# Left Pane: ScrollContainer
		_scroll_container = ScrollContainer.new()
		_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll_container.size_flags_stretch_ratio = 1.6
		_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body_hbox.add_child(_scroll_container)

		_recipe_list_box = VBoxContainer.new()
		_recipe_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_recipe_list_box.add_theme_constant_override("separation", 6)
		_scroll_container.add_child(_recipe_list_box)

		# Right Pane: Recipe Inspector & Forge Anvil
		_build_inspector_panel(body_hbox)


func _build_inspector_panel(parent: HBoxContainer) -> void:
	var insp_panel: PanelContainer = PanelContainer.new()
	insp_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	insp_panel.size_flags_stretch_ratio = 1.0
	insp_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var isb: StyleBoxFlat = StyleBoxFlat.new()
	isb.bg_color = Color(0.10, 0.11, 0.13, 0.95)
	isb.border_color = Color(0.24, 0.26, 0.30, 0.85)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(4)
	isb.set_content_margin_all(16)
	insp_panel.add_theme_stylebox_override("panel", isb)
	parent.add_child(insp_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	insp_panel.add_child(vb)

	var hdr_lbl: Label = Label.new()
	hdr_lbl.text = "ПАРАМЕТРЫ И НАКОВАЛЬНЯ"
	hdr_lbl.add_theme_font_size_override("font_size", 12)
	hdr_lbl.modulate = Color(0.75, 0.78, 0.84)
	vb.add_child(hdr_lbl)

	# Top Icon & Title Card
	var top_hbox: HBoxContainer = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 12)
	vb.add_child(top_hbox)

	var icon_frame: PanelContainer = PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(64.0, 64.0)
	var if_sb: StyleBoxFlat = StyleBoxFlat.new()
	if_sb.bg_color = Color(0.14, 0.15, 0.18, 0.98)
	if_sb.border_color = Color(0.35, 0.38, 0.44, 0.85)
	if_sb.set_border_width_all(1)
	if_sb.set_corner_radius_all(4)
	icon_frame.add_theme_stylebox_override("panel", if_sb)
	top_hbox.add_child(icon_frame)

	_insp_icon_rect = TextureRect.new()
	_insp_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_insp_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_insp_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_frame.add_child(_insp_icon_rect)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	top_hbox.add_child(title_box)

	_insp_title_lbl = Label.new()
	_insp_title_lbl.text = "Выберите рецепт"
	_insp_title_lbl.add_theme_font_size_override("font_size", 14)
	_insp_title_lbl.modulate = Color(0.92, 0.90, 0.86)
	title_box.add_child(_insp_title_lbl)

	_insp_type_lbl = Label.new()
	_insp_type_lbl.text = "Категория"
	_insp_type_lbl.add_theme_font_size_override("font_size", 10)
	_insp_type_lbl.modulate = Color(0.60, 0.63, 0.68)
	title_box.add_child(_insp_type_lbl)

	_insp_desc_lbl = Label.new()
	_insp_desc_lbl.text = "Выберите предмет из списка для просмотра требований и ковки."
	_insp_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_desc_lbl.add_theme_font_size_override("font_size", 10)
	_insp_desc_lbl.modulate = Color(0.65, 0.68, 0.74)
	vb.add_child(_insp_desc_lbl)

	var info_sep: HSeparator = HSeparator.new()
	var isep_sb: StyleBoxLine = StyleBoxLine.new()
	isep_sb.color = Color(0.20, 0.22, 0.26, 0.90)
	info_sep.add_theme_stylebox_override("separator", isep_sb)
	vb.add_child(info_sep)

	_insp_stats_lbl = Label.new()
	_insp_stats_lbl.text = ""
	_insp_stats_lbl.add_theme_font_size_override("font_size", 10)
	_insp_stats_lbl.modulate = Color(0.85, 0.86, 0.90)
	vb.add_child(_insp_stats_lbl)

	_insp_station_lbl = Label.new()
	_insp_station_lbl.text = "Станок: Ручной крафт"
	_insp_station_lbl.add_theme_font_size_override("font_size", 10)
	_insp_station_lbl.modulate = Color(0.70, 0.73, 0.80, 1.0)
	vb.add_child(_insp_station_lbl)

	_insp_tech_lbl = Label.new()
	_insp_tech_lbl.text = "Исследование: Не требуется"
	_insp_tech_lbl.add_theme_font_size_override("font_size", 10)
	_insp_tech_lbl.modulate = Color(0.70, 0.73, 0.80, 1.0)
	vb.add_child(_insp_tech_lbl)

	var mats_title: Label = Label.new()
	mats_title.text = "ТРЕБУЕМЫЕ МАТЕРИАЛЫ:"
	mats_title.add_theme_font_size_override("font_size", 10)
	mats_title.modulate = Color(0.85, 0.86, 0.90, 1.0)
	vb.add_child(mats_title)

	_insp_mats_box = VBoxContainer.new()
	_insp_mats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_insp_mats_box.add_theme_constant_override("separation", 4)
	vb.add_child(_insp_mats_box)

	# Action Buttons (Forged Iron Action Buttons)
	var action_hbox: HBoxContainer = HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 10)
	vb.add_child(action_hbox)

	var btn_sb: StyleBoxFlat = StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.18, 0.20, 0.24, 1.0)
	btn_sb.border_color = Color(0.38, 0.42, 0.48, 1.0)
	btn_sb.set_border_width_all(1)
	btn_sb.set_corner_radius_all(3)

	_insp_craft1_btn = Button.new()
	_insp_craft1_btn.text = "СКОВАТЬ x1"
	_insp_craft1_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_craft1_btn.custom_minimum_size = Vector2(0.0, 32.0)
	_insp_craft1_btn.add_theme_font_size_override("font_size", 11)
	_insp_craft1_btn.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86, 1.0))
	_insp_craft1_btn.add_theme_stylebox_override("normal", btn_sb)
	_insp_craft1_btn.pressed.connect(func(): _execute_craft(1))
	action_hbox.add_child(_insp_craft1_btn)

	_insp_craft5_btn = Button.new()
	_insp_craft5_btn.text = "СКОВАТЬ x5"
	_insp_craft5_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_craft5_btn.custom_minimum_size = Vector2(0.0, 32.0)
	_insp_craft5_btn.add_theme_font_size_override("font_size", 11)
	_insp_craft5_btn.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86, 1.0))
	_insp_craft5_btn.add_theme_stylebox_override("normal", btn_sb)
	_insp_craft5_btn.pressed.connect(func(): _execute_craft(5))
	action_hbox.add_child(_insp_craft5_btn)


func open_panel(station_id: String = "") -> void:
	if station_id == "":
		station_id = _detect_nearby_station()
	_active_station = station_id
	visible = true
	_pick_default_recipe()
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func _detect_nearby_station() -> String:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node2D):
		return ""
	var ptile: Vector2i = Config.iso_to_world((player as Node2D).global_position)
	var stations: Array[Node] = get_tree().get_nodes_in_group("craft_station")
	var best_station: String = ""
	var best_dist: int = 999
	for node in stations:
		if node is Node2D and node.has_method("get_station_id"):
			var st_id: String = str(node.call("get_station_id"))
			if st_id != "":
				var stile: Vector2i = Config.iso_to_world((node as Node2D).global_position)
				var d: int = Config.tile_distance(ptile, stile)
				if d <= 3 and d < best_dist:
					best_dist = d
					best_station = st_id
	return best_station


func close_panel() -> void:
	if not visible:
		return
	_active_station = ""
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _pick_default_recipe() -> void:
	var sorted_rids: Array = _recipes.keys()
	for rid in sorted_rids:
		var recipe: Dictionary = _recipes[rid]
		var req_station: String = str(recipe.get("station", ""))
		if (_active_station == "" and req_station == "") or (_active_station != "" and (req_station == "" or req_station == _active_station)):
			_selected_recipe_id = rid
			return
	if not sorted_rids.is_empty():
		_selected_recipe_id = str(sorted_rids[0])


func refresh() -> void:
	if _active_station == "":
		_active_station = _detect_nearby_station()
	if _station_label != null:
		var st_title: String = _active_station.capitalize() if _active_station != "" else "Ручной крафт"
		_station_label.text = "МАСТЕРСКАЯ И КУЗНИЦА  —  [ %s ]" % st_title

	if _recipe_list_box == null:
		return
	for child in _recipe_list_box.get_children():
		_recipe_list_box.remove_child(child)
		child.queue_free()

	for cid in _category_buttons:
		var btn: Button = _category_buttons[cid]
		btn.modulate = Color(0.95, 0.93, 0.90) if cid == _current_category else Color(0.55, 0.58, 0.64)

	var player: Node = get_tree().get_first_node_in_group("player")
	var sorted_rids: Array = _recipes.keys()
	sorted_rids.sort_custom(func(a: String, b: String) -> bool:
		var req_a: String = str(_recipes[a].get("tech_required", ""))
		var req_b: String = str(_recipes[b].get("tech_required", ""))
		var lock_a: bool = (req_a != "" and ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_a))
		var lock_b: bool = (req_b != "" and ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_b))
		if lock_a != lock_b:
			return not lock_a
		return false
	)

	var found_selected: bool = false
	for rid in sorted_rids:
		var recipe: Dictionary = _recipes[rid]
		var req_station: String = str(recipe.get("station", ""))
		if _active_station == "" and req_station != "":
			continue
		if _active_station != "" and req_station != "" and req_station != _active_station:
			var is_brew: bool = (req_station in ["campfire", "alchemy_station"]) and (_active_station in ["campfire", "alchemy_station"])
			if not is_brew:
				continue

		var out: Dictionary = recipe.get("output", {})
		var out_id: String = str(out.get("item_id", rid))
		var out_count: int = int(out.get("count", 1))
		var item_def: Dictionary = DataRegistry.get_item(out_id)
		var item_type: String = str(item_def.get("type", ""))

		if not _matches_category(item_type, out_id):
			continue

		if _selected_recipe_id == rid:
			found_selected = true

		var item_title: String = str(item_def.get("name", out_id.capitalize()))
		var req_tech: String = str(recipe.get("tech_required", ""))
		var is_tech_unlocked: bool = true
		if req_tech != "":
			if ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_tech):
				is_tech_unlocked = false

		var can_craft: bool = is_tech_unlocked and _meets_requirements(player, recipe)

		var card: Button = _build_recipe_card(rid, recipe, item_title, out_id, out_count, is_tech_unlocked, req_tech, can_craft)
		_recipe_list_box.add_child(card)

	if not found_selected and not sorted_rids.is_empty():
		_pick_default_recipe()

	_update_inspector(player)


func _build_recipe_card(rid: String, recipe: Dictionary, title: String, out_id: String, out_count: int, is_unlocked: bool, req_tech: String, can_craft: bool) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(0.0, 46.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.icon = IconFactory.get_icon(out_id)
	btn.expand_icon = true

	var is_selected: bool = (rid == _selected_recipe_id)

	var card_sb: StyleBoxFlat = StyleBoxFlat.new()
	card_sb.set_corner_radius_all(3)
	card_sb.content_margin_left = 12
	card_sb.content_margin_right = 12
	card_sb.content_margin_top = 4
	card_sb.content_margin_bottom = 4

	if not is_unlocked:
		card_sb.bg_color = Color(0.08, 0.09, 0.11, 0.90)
		card_sb.border_color = Color(0.32, 0.18, 0.18, 0.85)
		card_sb.set_border_width_all(1)
		btn.text = "   %s  •  [ЗАКРЫТО: Требует %s]" % [title, req_tech.capitalize()]
		btn.add_theme_color_override("font_color", Color(0.55, 0.52, 0.52, 1.0))
	elif can_craft:
		card_sb.bg_color = Color(0.16, 0.18, 0.22, 0.98) if is_selected else Color(0.12, 0.13, 0.16, 0.95)
		card_sb.border_color = Color(0.42, 0.68, 0.42, 0.95) if is_selected else Color(0.24, 0.28, 0.32, 0.80)
		card_sb.set_border_width_all(2 if is_selected else 1)
		btn.text = "   %s x%d   —   %s   [ГОТОВО]" % [title, out_count, _format_inputs(recipe.get("inputs", []))]
		btn.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86, 1.0))
	else:
		card_sb.bg_color = Color(0.14, 0.15, 0.18, 0.95) if is_selected else Color(0.10, 0.11, 0.13, 0.90)
		card_sb.border_color = Color(0.48, 0.50, 0.56, 0.90) if is_selected else Color(0.22, 0.24, 0.28, 0.70)
		card_sb.set_border_width_all(2 if is_selected else 1)
		btn.text = "   %s x%d   —   %s   [НЕТ РЕСУРСОВ]" % [title, out_count, _format_inputs(recipe.get("inputs", []))]
		btn.add_theme_color_override("font_color", Color(0.70, 0.72, 0.76, 1.0))

	btn.add_theme_stylebox_override("normal", card_sb)
	btn.add_theme_stylebox_override("hover", card_sb)
	btn.add_theme_stylebox_override("pressed", card_sb)
	btn.add_theme_font_size_override("font_size", 11)

	var target_rid: String = rid
	btn.pressed.connect(func():
		_selected_recipe_id = target_rid
		refresh()
	)
	return btn


func _update_inspector(player: Node) -> void:
	if _selected_recipe_id == "" or not _recipes.has(_selected_recipe_id):
		return
	var recipe: Dictionary = _recipes[_selected_recipe_id]
	var out: Dictionary = recipe.get("output", {})
	var out_id: String = str(out.get("item_id", _selected_recipe_id))
	var out_count: int = int(out.get("count", 1))
	var item_def: Dictionary = DataRegistry.get_item(out_id)

	var title_text: String = str(item_def.get("name", out_id.capitalize()))
	if out_count > 1:
		title_text += " (Yields x%d)" % out_count
	_insp_title_lbl.text = title_text

	_insp_icon_rect.texture = IconFactory.get_icon(out_id)

	var item_type: String = str(item_def.get("type", "Material")).capitalize()
	var slot_info: String = str(item_def.get("equip_slot", ""))
	_insp_type_lbl.text = "%s  %s" % [item_type, ("• Slot: " + slot_info.capitalize()) if slot_info != "" else ""]

	var weight: float = float(item_def.get("weight", 1.0))
	var durability: int = int(item_def.get("durability", -1))
	var stats: Dictionary = item_def.get("stats", {})
	var stat_parts: PackedStringArray = PackedStringArray()
	stat_parts.append("Weight: %.1f kg" % weight)
	if durability > 0:
		stat_parts.append("Durability: %d" % durability)
	if stats.has("damage"):
		stat_parts.append("Damage: %d" % int(stats["damage"]))
	if stats.has("attack_speed"):
		stat_parts.append("Speed: %.2fx" % float(stats["attack_speed"]))
	if stats.has("defense"):
		stat_parts.append("Defense: +%d" % int(stats["defense"]))
	if stats.has("mining_power"):
		stat_parts.append("Mining Power: Tier %d" % int(stats["mining_power"]))
	if stats.has("tool_type"):
		stat_parts.append("Tool: %s" % str(stats["tool_type"]).capitalize())
	if stats.has("nutrition"):
		stat_parts.append("Nutrition: +%d" % int(stats["nutrition"]))
	_insp_stats_lbl.text = " | ".join(stat_parts)

	var req_station: String = str(recipe.get("station", ""))
	_insp_station_lbl.text = "Станок: %s" % (req_station.capitalize() if req_station != "" else "Ручной крафт (без станка)")

	var req_tech: String = str(recipe.get("tech_required", ""))
	if req_tech == "":
		_insp_tech_lbl.text = "Исследование: Не требуется (Базовые знания)"
		_insp_tech_lbl.modulate = Color(0.70, 0.74, 0.80)
	else:
		var is_tech_done: bool = (ResearchSys.instance != null and ResearchSys.instance.is_researched(req_tech))
		_insp_tech_lbl.text = "Исследование: %s  [%s]" % [req_tech.capitalize(), "ИЗУЧЕНО" if is_tech_done else "ЗАКРЫТО"]
		_insp_tech_lbl.modulate = Color(0.52, 0.78, 0.50) if is_tech_done else Color(0.85, 0.38, 0.38)

	# Build Materials Checklist
	for ch in _insp_mats_box.get_children():
		_insp_mats_box.remove_child(ch)
		ch.queue_free()

	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	var all_mats_ok: bool = true
	for inp in recipe.get("inputs", []):
		if inp is Dictionary:
			var mat_id: String = str(inp.get("item_id", ""))
			var needed: int = int(inp.get("count", 1))
			var have: int = inv.get_item_count(mat_id) if inv != null else 0
			var has_enough: bool = (have >= needed)
			if not has_enough:
				all_mats_ok = false

			var mat_def: Dictionary = DataRegistry.get_item(mat_id)
			var mat_name: String = str(mat_def.get("name", mat_id.capitalize()))

			var mat_row: HBoxContainer = HBoxContainer.new()
			mat_row.add_theme_constant_override("separation", 8)

			var m_icon: TextureRect = TextureRect.new()
			m_icon.custom_minimum_size = Vector2(22.0, 22.0)
			m_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			m_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			m_icon.texture = IconFactory.get_icon(mat_id)
			mat_row.add_child(m_icon)

			var m_lbl: Label = Label.new()
			m_lbl.text = "%s: %d / %d" % [mat_name, have, needed]
			m_lbl.add_theme_font_size_override("font_size", 10)
			m_lbl.modulate = Color(0.55, 0.78, 0.52, 1.0) if has_enough else Color(0.85, 0.38, 0.38, 1.0)
			mat_row.add_child(m_lbl)

			_insp_mats_box.add_child(mat_row)

	var is_tech_unlocked: bool = (req_tech == "" or (ResearchSys.instance != null and ResearchSys.instance.is_researched(req_tech)))
	var can_forge: bool = is_tech_unlocked and all_mats_ok

	_insp_craft1_btn.disabled = not can_forge
	_insp_craft5_btn.disabled = not can_forge
	if not is_tech_unlocked:
		_insp_craft1_btn.text = "[ТРЕБУЕТСЯ ИССЛЕДОВАНИЕ]"
	elif not all_mats_ok:
		_insp_craft1_btn.text = "[НЕДОСТАТОЧНО РЕСУРСОВ]"
	else:
		_insp_craft1_btn.text = "СКОВАТЬ x1"


func _execute_craft(multiplier: int) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or _selected_recipe_id == "":
		return
	var recipe: Dictionary = _recipes.get(_selected_recipe_id, {})
	var req_tech: String = str(recipe.get("tech_required", ""))
	if req_tech != "" and ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_tech):
		return

	var cs: CraftSystem = CraftSystem.new()
	for _step in range(multiplier):
		if not cs.can_craft(_selected_recipe_id, player, _active_station).get("ok", false):
			break
		SignalBus.craft_requested.emit(_selected_recipe_id, player, _active_station)
	refresh()


func _matches_category(item_type: String, item_id: String) -> bool:
	if _current_category == "all":
		return true
	elif _current_category == "tools":
		return item_type in ["weapon", "tool", "ammo"] or item_id.find("pick") != -1 or item_id.find("axe") != -1
	elif _current_category == "armor":
		return item_type in ["armor", "shield"] or item_id.find("shield") != -1 or item_id.find("chainmail") != -1 or item_id.find("tunic") != -1
	elif _current_category == "stations":
		return item_type in ["station", "building", "block"] or item_id in ["plank", "cloth", "chest", "bed", "alchemy_station"]
	elif _current_category == "survival":
		return item_type in ["consumable", "medicine", "food"] or item_id in ["bandage", "torch", "medicine", "poison", "water_bottle", "empty_bottle"] or item_id.begins_with("potion_")
	return true


func _meets_requirements(player: Node, recipe: Dictionary) -> bool:
	if player == null:
		return false
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	var skills: SkillsComponent = player.get("skills") as SkillsComponent
	if inv == null or skills == null:
		return false
	if not skills.meets_requirements(recipe.get("skill_required", {})):
		return false
	for inp in recipe.get("inputs", []):
		if inp is Dictionary:
			if not inv.has_item(str(inp.get("item_id", "")), int(inp.get("count", 1))):
				return false
	return true


func _format_inputs(inputs: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for inp in inputs:
		if inp is Dictionary:
			parts.append("%s x%d" % [str(inp.get("item_id", "")).capitalize(), int(inp.get("count", 1))])
	return ", ".join(parts)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel("")
	elif visible:
		close_panel()


func _on_craft_station_opened(station_id: String) -> void:
	open_panel(station_id)


func _on_item_crafted(_item_id: String) -> void:
	if visible:
		refresh()


func _on_inventory_changed(_entity: Node, _snapshot: Dictionary) -> void:
	if visible:
		refresh()

