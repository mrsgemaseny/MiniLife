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
var _toast_timer: float = 0.0
var _minimap: MinimapWidget = null
var _current_biome: String = "plains"
var _current_tile: Vector2i = Vector2i(128, 128)

func _ready() -> void:
	_setup_extended_hud()
	_connect_signals()
	update_stat("health", 100.0, 100.0)
	update_stat("hunger", 100.0, 100.0)
	update_stat("stamina", 100.0, 100.0)
	update_gold(35)
	update_time(int(GameManager.get_hour()))

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and notification_label != null:
			notification_label.text = ""

func _setup_extended_hud() -> void:
	var vbox: VBoxContainer = $MarginContainer/VBoxContainer
	if vbox != null:
		_blood_label = Label.new()
		_blood_label.text = "Blood: 100%"
		vbox.add_child(_blood_label)

		_biome_label = Label.new()
		_biome_label.text = "Biome: Plains (128, 128)"
		vbox.add_child(_biome_label)

		var help_lbl: Label = Label.new()
		help_lbl.text = "[WASD] Move [LMB] Attack/Harvest [E] Interact | [I] Inv [C] Craft [B] Build [J] Quests [K] Sheet [N] Factions [H] Chronicle [L] Trophies"
		help_lbl.add_theme_font_size_override("font_size", 12)
		help_lbl.modulate = Color(0.82, 0.88, 0.95, 0.92)
		vbox.add_child(help_lbl)

	_minimap = MinimapWidget.new()
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-216, 16)
	add_child(_minimap)

func _connect_signals() -> void:
	SignalBus.player_stat_changed.connect(update_stat)
	SignalBus.player_gold_changed.connect(update_gold)
	SignalBus.hour_passed.connect(update_time)
	SignalBus.day_passed.connect(func(_d: int) -> void: update_time(int(GameManager.get_hour())))
	SignalBus.status_effect_applied.connect(_on_effect_applied)
	SignalBus.status_effect_expired.connect(_on_effect_expired)
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.player_biome_changed.connect(_on_player_biome_changed)
	SignalBus.notification_posted.connect(_on_notification_posted)

func update_stat(stat_name: String, current: float, maximum: float) -> void:
	var pct: float = (current / maxf(1.0, maximum)) * 100.0
	match stat_name:
		"health":
			if health_bar != null:
				health_bar.value = pct
				health_bar.tooltip_text = "Health: %d / %d" % [int(current), int(maximum)]
		"hunger":
			if hunger_bar != null:
				hunger_bar.value = pct
				hunger_bar.tooltip_text = "Hunger: %d / %d" % [int(current), int(maximum)]
		"stamina":
			if stamina_bar != null:
				stamina_bar.value = pct
				stamina_bar.tooltip_text = "Stamina: %d / %d" % [int(current), int(maximum)]
		"blood":
			if _blood_label != null:
				_blood_label.text = "Blood: %d%%" % int(round(pct))

func update_gold(amount: int) -> void:
	if gold_label != null:
		gold_label.text = "Gold: %d" % amount

func update_time(hour: int) -> void:
	if time_label != null:
		var day: int = GameManager.get_day()
		var period: String = "Night" if GameManager.is_night() else "Day"
		time_label.text = "Day %d - %02d:00 (%s)" % [day, hour, period]

func _on_player_tile_changed(tile_pos: Vector2i) -> void:
	_current_tile = tile_pos
	_refresh_biome_label()

func _on_player_biome_changed(biome_id: String) -> void:
	_current_biome = biome_id
	_refresh_biome_label()

func _refresh_biome_label() -> void:
	if _biome_label != null:
		_biome_label.text = "Biome: %s (%d, %d)" % [_current_biome.capitalize(), _current_tile.x, _current_tile.y]

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
