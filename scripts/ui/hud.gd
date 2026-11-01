class_name HUD
extends Control

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
var _minimap: MinimapWidget = null
var _current_biome: String = "plains"
var _current_tile: Vector2i = Vector2i(140, 140)

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
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and notification_label != null:
			notification_label.text = ""

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_8:
			var slot_idx: int = k - KEY_1
			_activate_hotbar_slot(slot_idx)

func _make_bar_style(bg_col: Color, border_col: Color = Color(0.18, 0.20, 0.24, 0.9)) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	return sb

func _make_card_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.93)
	sb.border_color = Color(0.68, 0.55, 0.28, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
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
	var margin: MarginContainer = $MarginContainer
	if margin != null:
		margin.offset_left = 20.0
		margin.offset_top = 18.0
		margin.offset_right = 272.0
		margin.offset_bottom = 224.0

		var bg_panel: Panel = Panel.new()
		bg_panel.add_theme_stylebox_override("panel", _make_card_style())
		bg_panel.position = Vector2(10, 10)
		bg_panel.size = Vector2(272, 222)
		bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_panel)
		move_child(bg_panel, 0)

	var vbox: VBoxContainer = $MarginContainer/VBoxContainer
	if vbox != null:
		vbox.add_theme_constant_override("separation", 5)
		var hdr: Label = Label.new()
		hdr.text = "SURVIVOR STATUS"
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.modulate = Color(0.95, 0.84, 0.52)
		vbox.add_child(hdr)
		vbox.move_child(hdr, 0)

	if health_bar != null:
		health_bar.custom_minimum_size = Vector2(248, 20)
		health_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.24, 0.07, 0.08, 0.95)))
		health_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.84, 0.18, 0.20, 0.96), Color(0.96, 0.42, 0.42, 0.8)))
		_hp_val_label = _attach_bar_overlay_label(health_bar, "HP: 100 / 100")
	if hunger_bar != null:
		hunger_bar.custom_minimum_size = Vector2(248, 20)
		hunger_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.24, 0.15, 0.05, 0.95)))
		hunger_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.86, 0.55, 0.14, 0.96), Color(0.98, 0.74, 0.32, 0.8)))
		_hunger_val_label = _attach_bar_overlay_label(hunger_bar, "Food: 100 / 100")
	if stamina_bar != null:
		stamina_bar.custom_minimum_size = Vector2(248, 20)
		stamina_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.07, 0.22, 0.11, 0.95)))
		stamina_bar.add_theme_stylebox_override("fill", _make_bar_style(Color(0.22, 0.72, 0.36, 0.96), Color(0.45, 0.92, 0.56, 0.8)))
		_stam_val_label = _attach_bar_overlay_label(stamina_bar, "Stamina: 100 / 100")

	if gold_label != null:
		gold_label.add_theme_font_size_override("font_size", 12)
		gold_label.modulate = Color(0.96, 0.84, 0.42)
	if time_label != null:
		time_label.add_theme_font_size_override("font_size", 12)
		time_label.modulate = Color(0.88, 0.92, 0.98)
	if status_label != null:
		status_label.add_theme_font_size_override("font_size", 12)
		status_label.text = "Status: Healthy"

	if vbox != null:
		_blood_label = Label.new()
		_blood_label.text = "Blood: 100%"
		_blood_label.add_theme_font_size_override("font_size", 12)
		_blood_label.modulate = Color(0.94, 0.62, 0.64)
		vbox.add_child(_blood_label)

	# Top-Right Minimap + Resources Card underneath
	_minimap = MinimapWidget.new()
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-204, 10)
	add_child(_minimap)

	var res_panel: PanelContainer = PanelContainer.new()
	res_panel.add_theme_stylebox_override("panel", _make_card_style())
	res_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	res_panel.position = Vector2(-204, 226)
	res_panel.custom_minimum_size = Vector2(192, 72)
	add_child(res_panel)

	var res_vbox: VBoxContainer = VBoxContainer.new()
	res_vbox.add_theme_constant_override("separation", 3)
	res_panel.add_child(res_vbox)

	var res_hdr: Label = Label.new()
	res_hdr.text = "RESOURCES & REALM"
	res_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_hdr.add_theme_font_size_override("font_size", 11)
	res_hdr.modulate = Color(0.95, 0.84, 0.52)
	res_vbox.add_child(res_hdr)

	_resources_label = Label.new()
	_resources_label.text = "  Logs: 14    |   Stone: 12"
	_resources_label.add_theme_font_size_override("font_size", 12)
	res_vbox.add_child(_resources_label)

	_biome_label = Label.new()
	_biome_label.text = "  Biome: Plains (140, 140)"
	_biome_label.add_theme_font_size_override("font_size", 11)
	_biome_label.modulate = Color(0.76, 0.86, 0.74)
	res_vbox.add_child(_biome_label)

	# Bottom-Center 8-Slot Hotkey Action Bar (matching ui_world_design_reference)
	var hotbar_panel: PanelContainer = PanelContainer.new()
	hotbar_panel.add_theme_stylebox_override("panel", _make_card_style())
	hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_panel.position = Vector2(-268, -98)
	hotbar_panel.custom_minimum_size = Vector2(536, 66)
	add_child(hotbar_panel)

	var hb_vbox: VBoxContainer = VBoxContainer.new()
	hb_vbox.add_theme_constant_override("separation", 2)
	hotbar_panel.add_child(hb_vbox)

	var hb_title: Label = Label.new()
	hb_title.text = "HOTKEY ACTION BAR [1 - 8]"
	hb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb_title.add_theme_font_size_override("font_size", 10)
	hb_title.modulate = Color(0.95, 0.84, 0.52)
	hb_vbox.add_child(hb_title)

	var hb_hbox: HBoxContainer = HBoxContainer.new()
	hb_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hb_hbox.add_theme_constant_override("separation", 6)
	hb_vbox.add_child(hb_hbox)

	_hotbar_buttons.clear()
	for i in range(8):
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(58, 42)
		var slot_sb: StyleBoxFlat = StyleBoxFlat.new()
		slot_sb.bg_color = Color(0.13, 0.15, 0.19, 0.95)
		slot_sb.border_color = Color(0.45, 0.39, 0.25, 0.90)
		slot_sb.set_border_width_all(1)
		slot_sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", slot_sb)
		btn.add_theme_font_size_override("font_size", 10)
		btn.text = "[%d]\n--" % (i + 1)
		var idx: int = i
		btn.pressed.connect(func() -> void: _activate_hotbar_slot(idx))
		hb_hbox.add_child(btn)
		_hotbar_buttons.append(btn)

	# Sleek bottom keybind bar anchored at bottom edge
	var bottom_bar: PanelContainer = PanelContainer.new()
	var bot_sb: StyleBoxFlat = StyleBoxFlat.new()
	bot_sb.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	bot_sb.border_color = Color(0.55, 0.45, 0.24, 0.85)
	bot_sb.border_width_top = 1
	bottom_bar.add_theme_stylebox_override("panel", bot_sb)
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -24.0
	bottom_bar.offset_bottom = 0.0
	add_child(bottom_bar)

	var help_lbl: Label = Label.new()
	help_lbl.text = "  [WASD] Move   [LMB] Attack / Harvest   [E] Talk / Station   |   [I] Bag   [C] Craft   [B] Build   [J] Quests   [K] Hero   [N] Factions   [H] Lore   [L] Trophies   [F5] Save"
	help_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_lbl.add_theme_font_size_override("font_size", 11)
	help_lbl.modulate = Color(0.88, 0.86, 0.78, 0.95)
	bottom_bar.add_child(help_lbl)

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
		_resources_label.text = "  Logs: %d    |   Stone: %d" % [wood_cnt, stone_cnt]

	for i in range(_hotbar_buttons.size()):
		var btn: Button = _hotbar_buttons[i]
		var is_active: bool = (i == active_idx)
		var slot_sb: StyleBoxFlat = StyleBoxFlat.new()
		slot_sb.bg_color = Color(0.24, 0.20, 0.11, 0.98) if is_active else Color(0.13, 0.15, 0.19, 0.95)
		slot_sb.border_color = Color(0.98, 0.84, 0.30, 1.0) if is_active else Color(0.45, 0.39, 0.25, 0.90)
		slot_sb.set_border_width_all(2 if is_active else 1)
		slot_sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", slot_sb)
		btn.add_theme_stylebox_override("hover", slot_sb)
		btn.add_theme_stylebox_override("pressed", slot_sb)
		btn.add_theme_stylebox_override("focus", slot_sb)

		var slot: Dictionary = inv.get_slot(i)
		if slot.is_empty():
			btn.text = "[%d]\n--" % (i + 1)
			btn.modulate = Color(0.98, 0.92, 0.68) if is_active else Color(0.65, 0.68, 0.72)
		else:
			var item_id: String = str(slot.get("item_id", ""))
			var count: int = int(slot.get("count", 1))
			var def: Dictionary = DataRegistry.get_item(item_id)
			var short_name: String = str(def.get("name", item_id)).split(" ")[-1].substr(0, 7)
			btn.text = "[%d] %s\nx%d" % [i + 1, short_name, count]
			btn.modulate = Color(1.0, 0.96, 0.78) if is_active else Color(0.92, 0.90, 0.82)

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

func update_time(hour: int) -> void:
	if time_label != null:
		var day: int = GameManager.get_day()
		var period: String = "Night" if GameManager.is_night() else "Day"
		time_label.text = "Day %d  |  %02d:00 (%s)" % [day, hour, period]

func _on_player_tile_changed(tile_pos: Vector2i) -> void:
	_current_tile = tile_pos
	_refresh_biome_label()

func _on_player_biome_changed(biome_id: String) -> void:
	_current_biome = biome_id
	_refresh_biome_label()

func _refresh_biome_label() -> void:
	if _biome_label != null:
		_biome_label.text = "  Biome: %s (%d, %d)" % [_current_biome.capitalize(), _current_tile.x, _current_tile.y]

func _on_notification_posted(message: String) -> void:
	if notification_label == null:
		return
	notification_label.text = message
	notification_label.modulate = Color(0.95, 0.90, 0.55)
	_toast_timer = 4.0

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
