class_name HUD
extends Control

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var hunger_bar: ProgressBar = $MarginContainer/VBoxContainer/HungerBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/StaminaBar
@onready var gold_label: Label = $MarginContainer/VBoxContainer/GoldLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/TimeLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var notification_label: Label = $MarginContainer/VBoxContainer/NotificationLabel

var _active_statuses: Array[String] = []
var _notification_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SignalBus.player_stat_changed.connect(_on_player_stat_changed)
	SignalBus.player_gold_changed.connect(_on_player_gold_changed)
	SignalBus.hour_passed.connect(_on_time_changed)
	SignalBus.day_passed.connect(_on_time_changed)
	SignalBus.status_effect_applied.connect(_on_status_applied)
	SignalBus.status_effect_expired.connect(_on_status_expired)
	SignalBus.notification_posted.connect(_on_notification_posted)
	SignalBus.player_died.connect(_on_player_died)
	_refresh_time()


func _process(delta: float) -> void:
	if _notification_timer > 0.0:
		_notification_timer -= delta
		if _notification_timer <= 0.0 and notification_label != null:
			notification_label.text = ""


func _on_player_stat_changed(stat: String, value: float, max_value: float) -> void:
	match stat:
		"health":
			if health_bar != null:
				health_bar.max_value = maxf(max_value, 1.0)
				health_bar.value = value
		"hunger":
			if hunger_bar != null:
				hunger_bar.max_value = maxf(max_value, 1.0)
				hunger_bar.value = value
		"stamina":
			if stamina_bar != null:
				stamina_bar.max_value = maxf(max_value, 1.0)
				stamina_bar.value = value


func _on_player_gold_changed(gold: int) -> void:
	if gold_label != null:
		gold_label.text = "Gold: %d" % gold


func _on_time_changed(_val: int) -> void:
	_refresh_time()


func _refresh_time() -> void:
	if time_label != null:
		time_label.text = "Day %d - %02d:00" % [GameManager.get_day(), int(GameManager.get_hour())]


func _on_status_applied(target: Node, effect: String, _duration: float) -> void:
	if target != null and not target.is_in_group("player"):
		return
	if not _active_statuses.has(effect):
		_active_statuses.append(effect)
	_refresh_statuses()


func _on_status_expired(target: Node, effect: String) -> void:
	if target != null and not target.is_in_group("player"):
		return
	_active_statuses.erase(effect)
	_refresh_statuses()


func _refresh_statuses() -> void:
	if status_label != null:
		status_label.text = "Status: " + (", ".join(_active_statuses) if not _active_statuses.is_empty() else "None")


func _on_notification_posted(message: String) -> void:
	if notification_label != null:
		notification_label.text = message
		_notification_timer = 4.0


func _on_player_died() -> void:
	_on_notification_posted("PERMADEATH: Your journey has ended.")
