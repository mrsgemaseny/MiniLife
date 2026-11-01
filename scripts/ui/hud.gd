class_name HUD
extends Control

const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var hunger_bar: ProgressBar = $MarginContainer/VBoxContainer/HungerBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/StaminaBar
@onready var gold_label: Label = $MarginContainer/VBoxContainer/GoldLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/TimeLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var notification_label: Label = $MarginContainer/VBoxContainer/NotificationLabel

var _active_effects: Array[String] = []
var _blood_label: Label = null
var _biome_label: Label = null
var _resources_label: Label = null
var _hp_val_label: Label = null
var _hunger_val_label: Label = null
var _stam_val_label: Label = null
var _hotbar_buttons: Array[Button] = []
var _toast_timer: float = 0.0
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _minimap: MinimapWidget = null
var _current_biome: String = "plains"
var _current_tile: Vector2i = Vector2i(140, 140)
var _location_banner: Label = null
var _banner_timer: float = 0.0
var _vignette_overlay: ColorRect = null
var _exit_hint_label: Label = null
var _current_weather: String = "clear"

var _hovered_node: Node2D = null
var _hover_timer: float = 0.0
var _inspect_card: PanelContainer = null
var _inspect_title: Label = null
var _inspect_badge: Label = null
var _inspect_details: Label = null
var _inspect_alpha: float = 0.0

func _ready() -> void:
	_setup_styled_hud()
	_connect_signals()
	update_stat("health", 100.0, 100.0)
	update_stat("hunger", 100.0, 100.0)
	update_stat("stamina", 100.0, 100.0)
	update_gold(35)
	update_time(int(GameManager.get_hour()))
	call_deferred("_refresh_hotbar_from_player")

func _process(delta: float) -> void:
	_refresh_time_display()
	_update_world_hover_inspect(delta)
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_panel != null:
			_toast_panel.modulate.a = clampf(_toast_timer / 0.5, 0.0, 1.0)
		if _toast_timer <= 0.0:
			if _toast_panel != null:
				_toast_panel.visible = false
			if notification_label != null:
				notification_label.text = ""
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _location_banner != null:
			_location_banner.modulate.a = clampf(_banner_timer / 0.8, 0.0, 1.0)
			if _banner_timer <= 0.0:
				_location_banner.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_8:
			var slot_idx: int = k - KEY_1
			_activate_hotbar_slot(slot_idx)
	elif event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var player: Node = get_tree().get_first_node_in_group("player")
			if player != null and "active_hotbar_index" in player:
				var cur: int = int(player.get("active_hotbar_index"))
				var step: int = -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				var next_idx: int = posmod(cur + step, 8)
				_activate_hotbar_slot(next_idx)

func _make_bar_style(bg_col: Color, border_col: Color = Color(0.22, 0.25, 0.30, 0.65)) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	return sb

func _make_card_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.56)
	sb.border_color = Color(0.76, 0.62, 0.34, 0.68)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	return sb

func _attach_bar_overlay_label(bar: ProgressBar, init_text: String) -> Label:
	bar.show_percentage = false
	var lbl: Label = Label.new()
	lbl.text = init_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.98, 0.97, 0.92)
	bar.add_child(lbl)
	return lbl

func _setup_styled_hud() -> void:
	# Vignette Overlay for interiors
	_vignette_overlay = ColorRect.new()
	_vignette_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_overlay.color = Color(0.01, 0.02, 0.03, 0.58)
	_vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_overlay.visible = false
	add_child(_vignette_overlay)
	move_child(_vignette_overlay, 0)

	# Location Banner at top-center
	_location_banner = Label.new()
	_location_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_location_banner.position = Vector2(-220, 24)
	_location_banner.custom_minimum_size = Vector2(440, 30)
	_location_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_banner.add_theme_font_size_override("font_size", 16)
	_location_banner.modulate = Color(0.98, 0.88, 0.52)
	_location_banner.visible = false
	add_child(_location_banner)

	# Exit Hint at bottom
	_exit_hint_label = Label.new()
	_exit_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_exit_hint_label.position = Vector2(-160, -135)
	_exit_hint_label.custom_minimum_size = Vector2(320, 22)
	_exit_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exit_hint_label.add_theme_font_size_override("font_size", 11)
	_exit_hint_label.modulate = Color(0.96, 0.84, 0.42)
	_exit_hint_label.text = "Press [E] near entrance to leave"
	_exit_hint_label.visible = false
	add_child(_exit_hint_label)

	# Dedicated floating toast notification pill above hotbar
	_toast_panel = PanelContainer.new()
	_toast_panel.add_theme_stylebox_override("panel", _make_card_style())
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_panel.position = Vector2(-200, -145)
	_toast_panel.custom_minimum_size = Vector2(400, 28)
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	add_child(_toast_panel)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 11)
	_toast_label.modulate = Color(0.98, 0.88, 0.52)
	_toast_panel.add_child(_toast_label)

	var margin: MarginContainer = $MarginContainer
	if margin != null:
		margin.offset_left = 18.0
		margin.offset_top = 14.0
		margin.offset_right = 248.0
		margin.offset_bottom = 222.0

		var bg_panel: Panel = Panel.new()
		bg_panel.add_theme_stylebox_override("panel", _make_card_style())
		bg_panel.position = Vector2(10, 10)
		bg_panel.size = Vector2(246, 218)
		bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_panel)
		move_child(bg_panel, 0)

	var vbox: VBoxContainer = $MarginContainer/VBoxContainer
	if vbox != null:
		vbox.add_theme_constant_override("separation", 4)
		var hdr: Label = Label.new()
		hdr.text = "SURVIVOR VITALS"
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hdr.add_theme_font_size_override("font_size", 11)
		hdr.modulate = Color(0.95, 0.84, 0.52, 0.92)
		vbox.add_child(hdr)
		vbox.move_child(hdr, 0)

	if health_bar != null:
		health_bar.custom_minimum_size = Vector2(228, 17)
		health_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.20, 0.06, 0.07, 0.62)))
		health_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.84, 0.18, 0.22, 0.84), Color(0.96, 0.44, 0.44, 0.75)))
		_hp_val_label = _attach_bar_overlay_label(health_bar, "HP: 100 / 100")
	if hunger_bar != null:
		hunger_bar.custom_minimum_size = Vector2(228, 17)
		hunger_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.20, 0.13, 0.04, 0.62)))
		hunger_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.86, 0.55, 0.14, 0.84), Color(0.98, 0.74, 0.32, 0.75)))
		_hunger_val_label = _attach_bar_overlay_label(hunger_bar, "Food: 100 / 100")
	if stamina_bar != null:
		stamina_bar.custom_minimum_size = Vector2(228, 17)
		stamina_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.06, 0.18, 0.09, 0.62)))
		stamina_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.22, 0.72, 0.36, 0.84), Color(0.45, 0.92, 0.56, 0.75)))
		_stam_val_label = _attach_bar_overlay_label(stamina_bar, "Stamina: 100 / 100")

	if gold_label != null:
		gold_label.add_theme_font_size_override("font_size", 11)
		gold_label.modulate = Color(0.96, 0.84, 0.42)
	if time_label != null:
		time_label.add_theme_font_size_override("font_size", 11)
		time_label.modulate = Color(0.88, 0.92, 0.98)
	if status_label != null:
		status_label.add_theme_font_size_override("font_size", 11)
		status_label.text = "Status: Healthy"

	if vbox != null:
		_blood_label = Label.new()
		_blood_label.text = "Blood: 100%"
		_blood_label.add_theme_font_size_override("font_size", 11)
		_blood_label.modulate = Color(0.94, 0.62, 0.64)
		vbox.add_child(_blood_label)

	# Top-Right Minimap + Resources Card underneath
	_minimap = MinimapWidget.new()
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-196, 10)
	add_child(_minimap)

	var res_panel: PanelContainer = PanelContainer.new()
	res_panel.add_theme_stylebox_override("panel", _make_card_style())
	res_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	res_panel.position = Vector2(-196, 214)
	res_panel.custom_minimum_size = Vector2(186, 66)
	add_child(res_panel)

	var res_vbox: VBoxContainer = VBoxContainer.new()
	res_vbox.add_theme_constant_override("separation", 2)
	res_panel.add_child(res_vbox)

	var res_hdr: Label = Label.new()
	res_hdr.text = "REALM & STOCKS"
	res_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_hdr.add_theme_font_size_override("font_size", 10)
	res_hdr.modulate = Color(0.95, 0.84, 0.52, 0.92)
	res_vbox.add_child(res_hdr)

	_resources_label = Label.new()
	_resources_label.text = "Logs: 14  |  Stone: 12"
	_resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resources_label.add_theme_font_size_override("font_size", 11)
	res_vbox.add_child(_resources_label)

	_biome_label = Label.new()
	_biome_label.text = "Plains (140, 140)"
	_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_biome_label.add_theme_font_size_override("font_size", 10)
	_biome_label.modulate = Color(0.76, 0.88, 0.76)
	res_vbox.add_child(_biome_label)

	# Bottom-Center 8-Slot Hotkey Action Bar with 32x32 Item Icons
	var hotbar_panel: PanelContainer = PanelContainer.new()
	hotbar_panel.add_theme_stylebox_override("panel", _make_card_style())
	hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_panel.position = Vector2(-264, -104)
	hotbar_panel.custom_minimum_size = Vector2(528, 68)
	add_child(hotbar_panel)

	var hb_hbox: HBoxContainer = HBoxContainer.new()
	hb_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hb_hbox.add_theme_constant_override("separation", 6)
	hotbar_panel.add_child(hb_hbox)

	_hotbar_buttons.clear()
	for i in range(8):
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(58, 54)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.expand_icon = true
		var slot_sb: StyleBoxFlat = StyleBoxFlat.new()
		slot_sb.bg_color = Color(0.09, 0.11, 0.15, 0.62)
		slot_sb.border_color = Color(0.48, 0.42, 0.28, 0.72)
		slot_sb.set_border_width_all(1)
		slot_sb.set_corner_radius_all(6)
		slot_sb.content_margin_top = 3
		slot_sb.content_margin_bottom = 2
		btn.add_theme_stylebox_override("normal", slot_sb)
		btn.add_theme_font_size_override("font_size", 10)
		btn.text = "[%d]" % (i + 1)
		var idx: int = i
		btn.pressed.connect(func() -> void: _activate_hotbar_slot(idx))
		hb_hbox.add_child(btn)
		_hotbar_buttons.append(btn)

	# Sleek translucent interactive Quick-Action Dock at bottom edge
	var bottom_bar: PanelContainer = PanelContainer.new()
	var bot_sb: StyleBoxFlat = StyleBoxFlat.new()
	bot_sb.bg_color = Color(0.05, 0.06, 0.09, 0.58)
	bot_sb.border_color = Color(0.65, 0.52, 0.28, 0.62)
	bot_sb.border_width_top = 1
	bot_sb.content_margin_top = 2
	bot_sb.content_margin_bottom = 2
	bottom_bar.add_theme_stylebox_override("panel", bot_sb)
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -30.0
	bottom_bar.offset_bottom = 0.0
	add_child(bottom_bar)

	var dock_hbox: HBoxContainer = HBoxContainer.new()
	dock_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dock_hbox.add_theme_constant_override("separation", 8)
	bottom_bar.add_child(dock_hbox)

	var controls_hint: Label = Label.new()
	controls_hint.text = "[WASD] Move  [LMB] Act  [Scroll/1-8] Tool  [E] Use  |"
	controls_hint.add_theme_font_size_override("font_size", 11)
	controls_hint.modulate = Color(0.82, 0.84, 0.88, 0.88)
	dock_hbox.add_child(controls_hint)

	var menu_defs: Array[Dictionary] = [
		{"label": "Bag [I]", "panel": "inventory", "icon": "cloth"},
		{"label": "Craft [C]", "panel": "craft", "icon": "stone_axe"},
		{"label": "Build [B]", "panel": "build", "icon": "wood"},
		{"label": "Quests [J]", "panel": "quests", "icon": "herb"},
		{"label": "Hero [K]", "panel": "character", "icon": "iron_sword"},
		{"label": "Factions [N]", "panel": "factions", "icon": "chainmail"},
		{"label": "Lore [H]", "panel": "chronicle", "icon": "cooked_food"},
		{"label": "Trophies [L]", "panel": "achievements", "icon": "iron_ingot"},
		{"label": "Save [F5]", "panel": "__save__", "icon": "campfire"}
	]
	for mdef in menu_defs:
		var mbtn: Button = Button.new()
		mbtn.text = str(mdef.get("label", ""))
		mbtn.icon = IconFactory.get_icon(str(mdef.get("icon", "")))
		mbtn.expand_icon = true
		mbtn.custom_minimum_size = Vector2(82, 22)
		mbtn.add_theme_font_size_override("font_size", 10)
		var msb: StyleBoxFlat = StyleBoxFlat.new()
		msb.bg_color = Color(0.11, 0.14, 0.19, 0.66)
		msb.border_color = Color(0.62, 0.50, 0.28, 0.70)
		msb.set_border_width_all(1)
		msb.set_corner_radius_all(4)
		msb.content_margin_left = 5
		msb.content_margin_right = 5
		var msb_hover: StyleBoxFlat = msb.duplicate() as StyleBoxFlat
		msb_hover.bg_color = Color(0.22, 0.19, 0.12, 0.88)
		msb_hover.border_color = Color(0.95, 0.80, 0.36, 0.95)
		mbtn.add_theme_stylebox_override("normal", msb)
		mbtn.add_theme_stylebox_override("hover", msb_hover)
		mbtn.add_theme_stylebox_override("pressed", msb_hover)
		var target_panel: String = str(mdef.get("panel", ""))
		mbtn.pressed.connect(func() -> void:
			if target_panel == "__save__":
				SignalBus.save_requested.emit("")
				SignalBus.notification_posted.emit("World state saved.")
			else:
				SignalBus.ui_panel_requested.emit(target_panel)
		)
		dock_hbox.add_child(mbtn)

	# Smooth World Hover Inspect Card (for trees, rocks, ores, NPCs)
	_inspect_card = PanelContainer.new()
	var ic_style: StyleBoxFlat = StyleBoxFlat.new()
	ic_style.bg_color = Color(0.06, 0.08, 0.12, 0.90)
	ic_style.border_color = Color(0.85, 0.72, 0.38, 0.92)
	ic_style.set_border_width_all(1)
	ic_style.set_corner_radius_all(6)
	ic_style.content_margin_left = 10
	ic_style.content_margin_right = 10
	ic_style.content_margin_top = 6
	ic_style.content_margin_bottom = 6
	_inspect_card.add_theme_stylebox_override("panel", ic_style)
	_inspect_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_card.z_index = 80
	_inspect_card.visible = false
	_inspect_card.modulate.a = 0.0

	var ic_vbox: VBoxContainer = VBoxContainer.new()
	ic_vbox.add_theme_constant_override("separation", 2)
	_inspect_card.add_child(ic_vbox)

	_inspect_title = Label.new()
	_inspect_title.text = "Oak Tree"
	_inspect_title.add_theme_font_size_override("font_size", 12)
	_inspect_title.modulate = Color(0.98, 0.88, 0.52)
	ic_vbox.add_child(_inspect_title)

	_inspect_badge = Label.new()
	_inspect_badge.text = "[ Woodcutting • Axe ]"
	_inspect_badge.add_theme_font_size_override("font_size", 10)
	_inspect_badge.modulate = Color(0.55, 0.82, 0.98)
	ic_vbox.add_child(_inspect_badge)

	_inspect_details = Label.new()
	_inspect_details.text = "Yields: Logs, Wood Chips"
	_inspect_details.add_theme_font_size_override("font_size", 10)
	_inspect_details.modulate = Color(0.82, 0.85, 0.88)
	ic_vbox.add_child(_inspect_details)

	add_child(_inspect_card)

func _connect_signals() -> void:
	SignalBus.player_stat_changed.connect(update_stat)
	SignalBus.player_gold_changed.connect(update_gold)
	SignalBus.hour_passed.connect(update_time)
	SignalBus.day_passed.connect(func(_d: int) -> void: update_time(int(GameManager.get_hour())))
	SignalBus.status_effect_applied.connect(_on_effect_applied)
	SignalBus.status_effect_expired.connect(_on_effect_expired)
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.player_biome_changed.connect(_on_player_biome_changed)
	SignalBus.inventory_changed.connect(_on_inventory_changed)
	SignalBus.equipment_changed.connect(func(_s: String, _id: String) -> void: _refresh_hotbar_from_player())
	SignalBus.notification_posted.connect(_on_notification_posted)
	SignalBus.interior_entered.connect(_on_interior_entered)
	SignalBus.interior_exited.connect(_on_interior_exited)
	SignalBus.weather_changed.connect(_on_weather_changed)

func _on_interior_entered(_zone_id: String, zone_name: String) -> void:
	if _location_banner != null:
		_location_banner.text = "Entering: " + zone_name
		_location_banner.visible = true
		_location_banner.modulate.a = 1.0
		_banner_timer = 3.0
	if _vignette_overlay != null:
		_vignette_overlay.visible = true
	if _exit_hint_label != null:
		_exit_hint_label.visible = true

func _on_interior_exited(_zone_id: String) -> void:
	if _location_banner != null:
		_location_banner.text = "Returning to Realm..."
		_location_banner.visible = true
		_location_banner.modulate.a = 1.0
		_banner_timer = 2.0
	if _vignette_overlay != null:
		_vignette_overlay.visible = false
	if _exit_hint_label != null:
		_exit_hint_label.visible = false

func _on_inventory_changed(entity: Node, _snapshot: Dictionary) -> void:
	if entity != null and entity.is_in_group("player"):
		_refresh_hotbar_from_player()

func _refresh_hotbar_from_player() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not (player.get("inventory") is InventoryComponent):
		return
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	var active_idx: int = int(player.get("active_hotbar_index")) if "active_hotbar_index" in player else 0
	if _resources_label != null:
		var wood_cnt: int = inv.count_of("wood")
		var stone_cnt: int = inv.count_of("stone")
		_resources_label.text = "Logs: %d  |  Stone: %d" % [wood_cnt, stone_cnt]

	for i in range(_hotbar_buttons.size()):
		var btn: Button = _hotbar_buttons[i]
		var is_active: bool = (i == active_idx)
		var slot_sb: StyleBoxFlat = StyleBoxFlat.new()
		slot_sb.bg_color = Color(0.28, 0.22, 0.09, 0.80) if is_active else Color(0.09, 0.11, 0.15, 0.58)
		slot_sb.border_color = Color(0.98, 0.84, 0.30, 0.96) if is_active else Color(0.48, 0.42, 0.28, 0.68)
		slot_sb.set_border_width_all(2 if is_active else 1)
		slot_sb.set_corner_radius_all(6)
		slot_sb.content_margin_top = 3
		slot_sb.content_margin_bottom = 2
		btn.add_theme_stylebox_override("normal", slot_sb)
		btn.add_theme_stylebox_override("hover", slot_sb)
		btn.add_theme_stylebox_override("pressed", slot_sb)
		btn.add_theme_stylebox_override("focus", slot_sb)

		var slot: Dictionary = inv.get_slot(i)
		if slot.is_empty():
			btn.icon = null
			btn.text = "[%d]" % (i + 1)
			btn.tooltip_text = "Empty Slot [%d]" % (i + 1)
			btn.modulate = Color(0.98, 0.92, 0.68, 0.90) if is_active else Color(0.62, 0.65, 0.70, 0.75)
		else:
			var item_id: String = str(slot.get("item_id", ""))
			var count: int = int(slot.get("count", 1))
			var def: Dictionary = DataRegistry.get_item(item_id)
			var full_name: String = str(def.get("name", item_id))
			btn.icon = IconFactory.get_icon(item_id)
			btn.text = "[%d] x%d" % [i + 1, count] if count > 1 else "[%d]" % (i + 1)
			btn.tooltip_text = "%s (x%d) — Press [%d] or Click" % [full_name, count, i + 1]
			btn.modulate = Color(1.0, 0.98, 0.86, 1.0) if is_active else Color(0.94, 0.92, 0.88, 0.92)

func _activate_hotbar_slot(slot_idx: int) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("use_slot_item"):
		player.call("use_slot_item", slot_idx)
		_refresh_hotbar_from_player()

func update_stat(stat_name: String, current: float, maximum: float) -> void:
	var pct: float = (current / maxf(1.0, maximum)) * 100.0
	match stat_name:
		"health":
			if health_bar != null:
				health_bar.value = pct
				health_bar.tooltip_text = "Health: %d / %d" % [int(current), int(maximum)]
			if _hp_val_label != null:
				_hp_val_label.text = "HP: %d / %d" % [int(round(current)), int(round(maximum))]
		"hunger":
			if hunger_bar != null:
				hunger_bar.value = pct
				hunger_bar.tooltip_text = "Hunger: %d / %d" % [int(current), int(maximum)]
				var h_col: Color = Color(0.28, 0.76, 0.38, 0.88)
				if pct < 10.0:
					h_col = Color(0.88, 0.20, 0.22, 0.92)
				elif pct < 30.0:
					h_col = Color(0.94, 0.58, 0.18, 0.90)
				hunger_bar.add_theme_stylebox_override("fill", _make_bar_style(h_col, h_col.lightened(0.20)))
			if _hunger_val_label != null:
				_hunger_val_label.text = "Food: %d / %d" % [int(round(current)), int(round(maximum))]
		"stamina":
			if stamina_bar != null:
				stamina_bar.value = pct
				stamina_bar.tooltip_text = "Stamina: %d / %d" % [int(current), int(maximum)]
			if _stam_val_label != null:
				_stam_val_label.text = "Stamina: %d / %d" % [int(round(current)), int(round(maximum))]
		"blood":
			if _blood_label != null:
				_blood_label.text = "Blood: %d%%" % int(round(pct))

func update_gold(amount: int) -> void:
	if gold_label != null:
		gold_label.text = "Coins: %dg" % amount

func update_time(_hour: int) -> void:
	_refresh_time_display()

func _on_weather_changed(weather_type: String) -> void:
	_current_weather = weather_type
	_refresh_time_display()

func _refresh_time_display() -> void:
	if time_label == null:
		return
	var day: int = GameManager.get_day()
	var raw_h: float = GameManager.get_hour()
	var h: int = int(floor(raw_h))
	var m: int = int(floor((raw_h - float(h)) * 60.0))

	var phase: String = "Night"
	if raw_h >= 4.5 and raw_h < 6.5:
		phase = "Dawn"
	elif raw_h >= 6.5 and raw_h < 11.5:
		phase = "Morning"
	elif raw_h >= 11.5 and raw_h < 16.5:
		phase = "Midday"
	elif raw_h >= 16.5 and raw_h < 19.5:
		phase = "Sunset"
	elif raw_h >= 19.5 and raw_h < 21.5:
		phase = "Dusk"
	else:
		phase = "Night"

	var w_name: String = _current_weather.capitalize()
	if _current_weather == "storm":
		w_name = "Thunderstorm"

	time_label.text = "Day %d  |  %02d:%02d (%s)  •  %s" % [day, h, m, phase, w_name]

func _on_player_tile_changed(tile_pos: Vector2i) -> void:
	_current_tile = tile_pos
	_refresh_biome_label()

func _on_player_biome_changed(biome_id: String) -> void:
	_current_biome = biome_id
	_refresh_biome_label()

func _refresh_biome_label() -> void:
	if _biome_label != null:
		_biome_label.text = "%s (%d, %d)" % [_current_biome.capitalize(), _current_tile.x, _current_tile.y]

func _on_notification_posted(message: String) -> void:
	if _toast_panel != null and _toast_label != null:
		_toast_label.text = message
		_toast_panel.visible = true
		_toast_panel.modulate.a = 1.0
	if notification_label != null:
		notification_label.text = message
		notification_label.modulate = Color(0.95, 0.90, 0.55)
	_toast_timer = 3.5

func _on_effect_applied(entity: Node, effect_id: String, _duration: float) -> void:
	if entity == null or not entity.is_in_group("player"):
		return
	if not _active_effects.has(effect_id):
		_active_effects.append(effect_id)
	_refresh_status_label()

func _on_effect_expired(entity: Node, effect_id: String) -> void:
	if entity == null or not entity.is_in_group("player"):
		return
	_active_effects.erase(effect_id)
	_refresh_status_label()

func _refresh_status_label() -> void:
	if status_label != null:
		status_label.text = "Status: " + (", ".join(_active_effects) if not _active_effects.is_empty() else "Healthy")

func _update_world_hover_inspect(delta: float) -> void:
	if _inspect_card == null:
		return

	var mouse_world: Vector2 = get_global_mouse_position()
	var candidate: Node2D = null
	var candidate_top_offset: float = -40.0

	var harvestables: Array[Node] = get_tree().get_nodes_in_group("harvestable")
	for node in harvestables:
		if not (node is Node2D) or not (node as Node2D).is_visible_in_tree():
			continue
		var n2d: Node2D = node as Node2D
		var gpos: Vector2 = n2d.global_position
		var def_id: String = str(n2d.get("node_def_id"))
		var is_tree: bool = def_id.find("tree") != -1 or def_id.find("pine") != -1 or def_id.find("oak") != -1
		var is_rock: bool = def_id.find("rock") != -1 or def_id.find("ore") != -1 or def_id.find("boulder") != -1 or def_id.find("deposit") != -1

		var hw: float = 38.0 if is_tree else (28.0 if is_rock else 22.0)
		var top_y: float = -74.0 if is_tree else (-36.0 if is_rock else -26.0)
		var bot_y: float = 14.0

		if mouse_world.x >= gpos.x - hw and mouse_world.x <= gpos.x + hw and mouse_world.y >= gpos.y + top_y and mouse_world.y <= gpos.y + bot_y:
			candidate = n2d
			candidate_top_offset = top_y
			break

	if candidate == null:
		var interactables: Array[Node] = get_tree().get_nodes_in_group("interactable")
		for node in interactables:
			if not (node is Node2D) or not (node as Node2D).is_visible_in_tree():
				continue
			var n2d: Node2D = node as Node2D
			var gpos: Vector2 = n2d.global_position
			if mouse_world.distance_to(gpos + Vector2(0.0, -10.0)) <= 32.0:
				candidate = n2d
				candidate_top_offset = -32.0
				break

	if candidate == null:
		var npcs: Array[Node] = get_tree().get_nodes_in_group("npc")
		for node in npcs:
			if not (node is Node2D) or not (node as Node2D).is_visible_in_tree():
				continue
			var n2d: Node2D = node as Node2D
			var gpos: Vector2 = n2d.global_position
			if mouse_world.distance_to(gpos + Vector2(0.0, -18.0)) <= 26.0:
				candidate = n2d
				candidate_top_offset = -48.0
				break

	if candidate != null:
		if candidate == _hovered_node:
			_hover_timer += delta
			if _hover_timer >= 1.0:
				_inspect_alpha = move_toward(_inspect_alpha, 1.0, delta * 4.5)
				_inspect_card.visible = true
				_populate_inspect_card(candidate)
				var screen_pos: Vector2 = get_viewport().get_canvas_transform() * (candidate.global_position + Vector2(0.0, candidate_top_offset - 6.0))
				_inspect_card.position = Vector2(
					clampf(screen_pos.x - _inspect_card.size.x * 0.5, 10.0, get_viewport_rect().size.x - _inspect_card.size.x - 10.0),
					clampf(screen_pos.y - _inspect_card.size.y, 10.0, get_viewport_rect().size.y - _inspect_card.size.y - 10.0)
				)
		else:
			_hovered_node = candidate
			_hover_timer = 0.0
			_inspect_alpha = move_toward(_inspect_alpha, 0.0, delta * 8.0)
	else:
		_hovered_node = null
		_hover_timer = 0.0
		_inspect_alpha = move_toward(_inspect_alpha, 0.0, delta * 6.0)

	_inspect_card.modulate.a = _inspect_alpha
	if _inspect_alpha <= 0.001:
		_inspect_card.visible = false

func _populate_inspect_card(target: Node2D) -> void:
	if target == null:
		return
	if target is ResourceNode or target.is_in_group("harvestable"):
		var def_id: String = str(target.get("node_def_id"))
		var def: Dictionary = DataRegistry.get_resource_node(def_id)
		var display_name: String = str(def.get("name", def_id.capitalize().replace("_", " ")))
		var tool_req: String = str(def.get("tool", "hands")).capitalize()
		var skill_req: String = str(def.get("skill", "survival")).capitalize()
		var hits_left: int = int(target.get("hits_remaining"))
		var max_hits: int = int(def.get("hits", 4))

		_inspect_title.text = display_name
		_inspect_badge.text = "[ %s • Required: %s ]" % [skill_req, tool_req]

		var drops_desc: String = ""
		var drops: Array = def.get("drops", [])
		if not drops.is_empty():
			var item_names: Array[String] = []
			for d in drops:
				if d is Dictionary:
					var it_id: String = str(d.get("item_id", ""))
					var it_def: Dictionary = DataRegistry.get_item(it_id)
					var it_name: String = str(it_def.get("name", it_id.capitalize().replace("_", " ")))
					item_names.append(it_name)
			drops_desc = "Yields: " + (", ".join(item_names) if not item_names.is_empty() else "Raw Materials")
		else:
			var res_type: String = str(def.get("type", "resource"))
			drops_desc = "Resource (" + res_type.capitalize() + ")"

		_inspect_details.text = "%s  |  Integrity: %d/%d" % [drops_desc, hits_left, max_hits]
	elif target.is_in_group("npc"):
		var npc_name: String = str(target.get("display_name"))
		var faction: String = str(target.get("faction_id")).capitalize()
		_inspect_title.text = npc_name if not npc_name.is_empty() else "Inhabitant"
		_inspect_badge.text = "[ Faction: %s ]" % faction
		_inspect_details.text = "Press [E] to interact or trade"
	elif target.is_in_group("interactable") or target.has_method("get_station_id"):
		var sid: String = str(target.get("structure_id"))
		var sdef: Dictionary = DataRegistry.get_structure(sid)
		var sname: String = str(sdef.get("name", sid.capitalize().replace("_", " ")))
		_inspect_title.text = sname
		_inspect_badge.text = "[ Station / Structure • E or RMB ]"
		_inspect_details.text = "Interact range: 3 tiles"

