extends Node2D

var resident_count: int = 0
var camp_id: String = ""
var _offered_item: String = ""
var _offer_expires_msec: int = 0

func _ready() -> void:
	add_to_group("interactable")

func interaction_hit_test(point: Vector2) -> bool:
	return Rect2(-30, -38, 60, 55).has_point(to_local(point))

func interact(actor: Node) -> void:
	var result: Dictionary = {}
	var now: int = Time.get_ticks_msec()
	var item: String = _offered_item if now <= _offer_expires_msec else ""
	SignalBus.refugee_aid_requested.emit(camp_id, actor, item, result)
	_offered_item = str(result.get("offer_item", ""))
	_offer_expires_msec = now + 5000
	if result.has("message"):
		SignalBus.notification_posted.emit(str(result["message"]))

func show_residents(count: int) -> void:
	if resident_count != count:
		resident_count = count
		queue_redraw()

func _draw() -> void:
	var tents: int = clampi(ceili(resident_count / 4.0), 1, 3)
	for index: int in range(tents):
		var origin: Vector2 = Vector2(float(index - (tents - 1) * 0.5) * 36.0, -17.0)
		var canvas: PackedVector2Array = PackedVector2Array([
			origin + Vector2(-16, 0), origin + Vector2(-8, -17),
			origin + Vector2(9, -19), origin + Vector2(17, -1),
		])
		draw_colored_polygon(canvas, Color("b5a07b"))
		draw_polyline(canvas, Color("4a3e32"), 2.0, true)
		draw_line(origin + Vector2(-8, -17), origin + Vector2(0, -2), Color("73624a"), 2.0, true)
		draw_colored_polygon(PackedVector2Array([origin + Vector2(-5, -1), origin + Vector2(2, -12), origin + Vector2(9, -1)]), Color("594837"))
	draw_circle(Vector2(16, 7), 6.0, Color("534941"))
	draw_circle(Vector2(16, 6), 4.0, Color("ed9449"))
	draw_circle(Vector2(16, 5), 2.0, Color("ffe2a0"))
