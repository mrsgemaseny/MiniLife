class_name CraftMenuUI
extends Control

const PANEL_ID: String = "craft"
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")
const ResearchSys = preload("res://scripts/systems/research_system.gd")

@onready var panel_container: PanelContainer = $PanelContainer
@onready var vbox: VBoxContainer = $PanelContainer/VBoxContainer
@onready var station_label: Label = $PanelContainer/VBoxContainer/StationLabel
@onready var recipe_list: VBoxContainer = $PanelContainer/VBoxContainer/RecipeList

var _active_station: String = ""
var _recipes: Dictionary = {}
var _current_category: String = "all"
var _category_buttons: Dictionary = {}


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
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Full-screen dark backdrop overlay (freezes focus, blocks world clicks)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	move_child(backdrop, 0)

	if panel_container != null:
		panel_container.offset_left = -300.0
		panel_container.offset_top = -260.0
		panel_container.offset_right = 300.0
		panel_container.offset_bottom = 260.0
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.13, 0.16, 0.96)
		sb.border_color = Color(0.78, 0.64, 0.34, 0.90)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(14)
		panel_container.add_theme_stylebox_override("panel", sb)

	if vbox != null:
		vbox.add_theme_constant_override("separation", 8)

		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		if station_label != null:
			vbox.remove_child(station_label)
			station_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			station_label.add_theme_font_size_override("font_size", 14)
			station_label.modulate = Color(0.96, 0.86, 0.52)
			hdr_hbox.add_child(station_label)
		var close_btn: Button = Button.new()
		close_btn.text = " [X] Close "
		close_btn.add_theme_font_size_override("font_size", 11)
		close_btn.pressed.connect(close_panel)
		hdr_hbox.add_child(close_btn)
		vbox.add_child(hdr_hbox)
		vbox.move_child(hdr_hbox, 0)

		# Category Filter Tab Row
		var cat_hbox: HBoxContainer = HBoxContainer.new()
		cat_hbox.add_theme_constant_override("separation", 6)
		var cats: Array[Dictionary] = [
			{"id": "all", "label": "All"},
			{"id": "tools", "label": "Weapons/Tools"},
			{"id": "armor", "label": "Armor"},
			{"id": "stations", "label": "Stations"},
			{"id": "survival", "label": "Survival/Meds"}
		]
		for c in cats:
			var cid: String = str(c.get("id"))
			var clbl: String = str(c.get("label"))
			var cbtn: Button = Button.new()
			cbtn.text = " " + clbl + " "
			cbtn.add_theme_font_size_override("font_size", 10)
			cbtn.pressed.connect(func():
				_current_category = cid
				refresh()
			)
			_category_buttons[cid] = cbtn
			cat_hbox.add_child(cbtn)
		vbox.add_child(cat_hbox)
		vbox.move_child(cat_hbox, 1)

		# Shift craft hint
		var hint_lbl: Label = Label.new()
		hint_lbl.text = "Click: Craft x1   |   Shift+Click: Craft x5"
		hint_lbl.add_theme_font_size_override("font_size", 9)
		hint_lbl.modulate = Color(0.65, 0.70, 0.78)
		vbox.add_child(hint_lbl)
		vbox.move_child(hint_lbl, 2)


func open_panel(station_id: String = "") -> void:
	if station_id == "":
		station_id = _detect_nearby_station()
	_active_station = station_id
	visible = true
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


func refresh() -> void:
	if _active_station == "":
		_active_station = _detect_nearby_station()
	if station_label != null:
		station_label.text = "CRAFTING  —  " + (_active_station.capitalize() if _active_station != "" else "Hand Crafting")
	if recipe_list == null:
		return
	for child in recipe_list.get_children():
		recipe_list.remove_child(child)
		child.queue_free()

	# Highlight active category button
	for cid in _category_buttons:
		var btn: Button = _category_buttons[cid]
		btn.modulate = Color(1.0, 0.85, 0.35) if cid == _current_category else Color(0.70, 0.72, 0.78)

	var player: Node = get_tree().get_first_node_in_group("player")
	for rid in _recipes:
		var recipe: Dictionary = _recipes[rid]
		var req_station: String = str(recipe.get("station", ""))
		if _active_station == "" and req_station != "":
			continue
		if _active_station != "" and req_station != "" and req_station != _active_station:
			continue

		var out: Dictionary = recipe.get("output", {})
		var out_id: String = str(out.get("item_id", rid))
		var out_count: int = int(out.get("count", 1))
		var item_def: Dictionary = DataRegistry.get_item(out_id)
		var item_type: String = str(item_def.get("type", ""))

		# Filter by category
		if not _matches_category(item_type, out_id):
			continue

		var item_title: String = str(item_def.get("name", out_id.capitalize()))

		# Check tech unlock
		var req_tech: String = str(recipe.get("tech_required", ""))
		var is_tech_unlocked: bool = true
		if req_tech != "":
			if ResearchSys.instance != null and not ResearchSys.instance.is_researched(req_tech):
				is_tech_unlocked = false

		var can_craft: bool = is_tech_unlocked and _meets_requirements(player, recipe)

		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(540, 40)
		btn.icon = IconFactory.get_icon(out_id)
		btn.expand_icon = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)

		if not is_tech_unlocked:
			btn.text = "  🔒 LOCKED: %s  —  Requires Tech: %s" % [item_title, req_tech.capitalize()]
			btn.disabled = true
			var lsb: StyleBoxFlat = StyleBoxFlat.new()
			lsb.bg_color = Color(0.14, 0.08, 0.08, 0.65)
			lsb.border_color = Color(0.65, 0.25, 0.25, 0.80)
			lsb.set_border_width_all(1)
			lsb.set_corner_radius_all(6)
			lsb.content_margin_left = 8
			btn.add_theme_stylebox_override("disabled", lsb)
		else:
			btn.text = "  %s x%d   —   Requires: %s" % [item_title, out_count, _format_inputs(recipe.get("inputs", []))]
			btn.disabled = not can_craft
			var rsb: StyleBoxFlat = StyleBoxFlat.new()
			rsb.bg_color = Color(0.12, 0.16, 0.22, 0.80) if can_craft else Color(0.08, 0.09, 0.12, 0.50)
			rsb.border_color = Color(0.45, 0.82, 0.52, 0.85) if can_craft else Color(0.32, 0.34, 0.38, 0.45)
			rsb.set_border_width_all(1)
			rsb.set_corner_radius_all(6)
			rsb.content_margin_left = 8
			btn.add_theme_stylebox_override("normal", rsb)
			btn.add_theme_stylebox_override("disabled", rsb)

		var recipe_id_str: String = str(rid)
		btn.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if player != null and is_tech_unlocked:
					var count: int = 5 if ev.shift_pressed else 1
					for _step in range(count):
						if not CraftSystem.new().can_craft(recipe_id_str, player, _active_station).get("ok", false):
							break
						SignalBus.craft_requested.emit(recipe_id_str, player, _active_station)
					refresh()
		)
		recipe_list.add_child(btn)


func _matches_category(item_type: String, item_id: String) -> bool:
	if _current_category == "all":
		return true
	elif _current_category == "tools":
		return item_type in ["weapon", "tool", "ammo"]
	elif _current_category == "armor":
		return item_type in ["armor", "shield"] or item_id.find("shield") != -1 or item_id.find("chainmail") != -1
	elif _current_category == "stations":
		return item_type in ["station", "building"] or item_id in ["plank", "cloth"]
	elif _current_category == "survival":
		return item_type in ["consumable", "medicine", "food"] or item_id in ["bandage", "torch", "medicine", "poison"]
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
