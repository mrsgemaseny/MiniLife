class_name ItemActionComponent
extends Node2D

var remaining: float = 0.0
var duration: float = 0.0
var title: String = ""
var stamina_per_second: float = 0.0
var _finish: Callable
var _origin: Vector2

func _ready() -> void:
	SignalBus.player_damaged.connect(func(_amount: float, _source: String) -> void: cancel())
	SignalBus.save_data_requested.connect(func(_bundle: Dictionary) -> void: cancel())
	SignalBus.save_data_loaded.connect(func(_bundle: Dictionary) -> void: cancel())

func begin(label: String, seconds: float, completion: Callable, stamina_cost: float = 0.0) -> bool:
	if remaining > 0.0:
		return false
	title = label
	duration = maxf(seconds, 0.01)
	remaining = duration
	_finish = completion
	stamina_per_second = stamina_cost
	_origin = (get_parent() as Node2D).global_position
	get_parent().set_meta("item_action_busy", true)
	queue_redraw()
	return true

func cancel() -> void:
	remaining = 0.0
	_finish = Callable()
	get_parent().set_meta("item_action_busy", false)
	queue_redraw()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if remaining <= 0.0 or GameManager.is_paused():
		return
	var actor: Node2D = get_parent() as Node2D
	if not actor.is_alive() or actor.global_position.distance_to(_origin) > 3.0 or Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
		cancel()
		return
	var stats: StatsComponent = actor.get("stats") as StatsComponent
	var cost: float = stamina_per_second * minf(delta, remaining)
	if stats != null and stats.stamina < cost:
		cancel()
		SignalBus.notification_posted.emit("Too exhausted to continue.")
		return
	if stats != null:
		stats.modify("stamina", -cost)
	remaining = maxf(0.0, remaining - delta)
	queue_redraw()
	if remaining == 0.0:
		var callback: Callable = _finish
		cancel()
		if callback.is_valid():
			callback.call()

func _draw() -> void:
	if remaining <= 0.0:
		return
	draw_rect(Rect2(-32, -65, 64, 6), Color(0.08, 0.07, 0.06))
	draw_rect(Rect2(-31, -64, 62 * (1.0 - remaining / duration), 4), Color(0.8, 0.64, 0.3))
	draw_string(ThemeDB.fallback_font, Vector2(-52, -70), title, HORIZONTAL_ALIGNMENT_LEFT, 180, 10)
