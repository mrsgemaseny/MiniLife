class_name ProjectileEntity
extends Node2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = Config.PROJECTILE_SPEED
var damage: float = 14.0
var damage_type: String = "physical"
var shooter: Node = null
var _distance_travelled: float = 0.0


func _process(delta: float) -> void:
	var step: float = speed * delta
	global_position += direction * step
	_distance_travelled += step
	queue_redraw()

	for node in get_tree().get_nodes_in_group("combatant"):
		if node == shooter or not (node is Node2D):
			continue
		if global_position.distance_to((node as Node2D).global_position) <= 18.0:
			SignalBus.damage_requested.emit(node, damage, damage_type, shooter)
			queue_free()
			return

	if _distance_travelled >= Config.RANGED_MAX_RANGE:
		queue_free()


func _draw() -> void:
	var tail: Vector2 = -direction * 14.0
	draw_line(tail, Vector2.ZERO, Color(0.92, 0.82, 0.55), 2.5)
	draw_circle(Vector2.ZERO, 2.5, Color(0.85, 0.88, 0.92))
