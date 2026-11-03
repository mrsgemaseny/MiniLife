class_name ProjectileEntity
extends Node2D

const ARROW_LENGTH: float = 16.0
const JAVELIN_LENGTH: float = 58.0

var projectile_type: String = "arrow" # "arrow" or "javelin"
var item_id: String = "arrow"
var direction: Vector2 = Vector2.RIGHT
var speed: float = Config.PROJECTILE_SPEED
var damage: float = 14.0
var damage_type: String = "physical"
var shooter: Node = null
var max_range: float = Config.RANGED_MAX_RANGE

var _distance_travelled: float = 0.0
var _current_altitude: float = 12.0
var _flight_dir: Vector2 = Vector2.RIGHT
var _is_stuck: bool = false
var _stuck_timer: float = 3.5


func _ready() -> void:
	_flight_dir = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	if item_id == "javelins" or item_id == "javelin":
		projectile_type = "javelin"


func _process(delta: float) -> void:
	if _is_stuck:
		_stuck_timer -= delta
		if _stuck_timer <= 0.8:
			modulate.a = clampf(_stuck_timer / 0.8, 0.0, 1.0)
		if _stuck_timer <= 0.0:
			queue_free()
			return

		# Missed arrow or javelin can be retrieved by player walking over it
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and is_instance_valid(player) and player is Node2D:
			var p2d: Node2D = player as Node2D
			if p2d.global_position.distance_to(global_position) <= 26.0:
				var inv: InventoryComponent = player.get("inventory") as InventoryComponent
				if inv != null:
					var return_id: String = "javelins" if projectile_type == "javelin" else "arrow"
					inv.add_item(return_id, 1)
					SignalBus.notification_posted.emit("Retrieved %s." % ("javelin" if projectile_type == "javelin" else "arrow"))
				queue_free()
				return
		return

	var step: float = speed * delta
	global_position += direction * step
	_distance_travelled += step

	var progress: float = clampf(_distance_travelled / maxf(1.0, max_range), 0.0, 1.0)
	var arc_apex: float = 24.0 * clampf(max_range / 300.0, 0.4, 1.2)
	_current_altitude = maxf(0.0, (1.0 - progress) * 12.0 + sin(progress * PI) * arc_apex)

	# Smooth ballistic flight direction (tangent of ground velocity + vertical altitude change)
	var d_alt: float = -12.0 / max_range + (PI / max_range) * arc_apex * cos(progress * PI)
	var screen_vec: Vector2 = direction + Vector2(0.0, -d_alt * 0.6)
	if screen_vec.length_squared() > 0.01:
		_flight_dir = screen_vec.normalized()

	queue_redraw()

	# Check combatant hits
	var tip_world: Vector2 = global_position + Vector2(0.0, -_current_altitude)
	for node in get_tree().get_nodes_in_group("combatant"):
		if node == shooter or not (node is Node2D):
			continue
		var n2d: Node2D = node as Node2D
		if not n2d.is_visible_in_tree():
			continue
		var target_center: Vector2 = n2d.global_position + Vector2(0.0, -14.0)
		var hit_radius: float = 28.0 if projectile_type == "javelin" else 22.0
		if tip_world.distance_to(target_center) <= hit_radius:
			SignalBus.arrow_impacted.emit(tip_world, "flesh")
			SignalBus.damage_requested.emit(node, damage, damage_type, shooter)
			queue_free()
			return

	if _distance_travelled >= max_range:
		_is_stuck = true
		_current_altitude = 0.0
		SignalBus.arrow_impacted.emit(global_position, "ground")
		# Natural landing angle into the ground along shot direction
		var land_vec: Vector2 = direction + Vector2(0.0, 0.55 if projectile_type == "javelin" else 0.45)
		_flight_dir = land_vec.normalized()
		queue_redraw()


func _draw() -> void:
	var tip: Vector2 = Vector2(0.0, -_current_altitude)
	var is_jav: bool = (projectile_type == "javelin")
	var proj_len: float = JAVELIN_LENGTH if is_jav else ARROW_LENGTH
	var tail: Vector2 = tip - _flight_dir * proj_len

	# 1. Ground shadow while airborne
	if not _is_stuck and _current_altitude > 1.5:
		var shadow_alpha: float = clampf(0.35 * (1.0 - _current_altitude / 55.0), 0.06, 0.35)
		var s_tail: Vector2 = -direction * (proj_len * 0.45)
		var s_tip: Vector2 = direction * (proj_len * 0.35)
		draw_line(s_tail, s_tip, Color(0.0, 0.0, 0.0, shadow_alpha), 2.8 if is_jav else 1.8)

	if is_jav:
		# Massive throwing spear (~4x arrow size)
		# A. Sturdy ash wood spear shaft
		draw_line(tail, tip, Color(0.12, 0.09, 0.06), 3.8) # Dark ink outline
		draw_line(tail + _flight_dir * 1.5, tip - _flight_dir * 10.0, Color(0.68, 0.50, 0.30), 2.6)

		# B. Leather center cord grip wrap
		var mid_p: Vector2 = tail + _flight_dir * (proj_len * 0.48)
		draw_line(mid_p - _flight_dir * 5.0, mid_p + _flight_dir * 5.0, Color(0.35, 0.22, 0.12), 3.2)

		# C. Forged iron socketed leaf spearhead
		var head_base: Vector2 = tip - _flight_dir * 12.0
		draw_line(head_base, tip, Color(0.12, 0.14, 0.18), 4.8) # Outline
		draw_line(head_base, tip, Color(0.72, 0.76, 0.84), 3.4)
		draw_line(head_base + _flight_dir * 2.0, tip, Color(0.92, 0.95, 1.0), 1.6) # Highlight ridge
		draw_circle(tip, 1.6, Color(0.95, 0.96, 1.0))
	else:
		# Standard 16px hunting arrow
		# Wooden arrow shaft
		draw_line(tail, tip, Color(0.85, 0.72, 0.48), 2.0)
		# Metallic arrowhead
		draw_line(tip - _flight_dir * 3.5, tip, Color(0.68, 0.72, 0.78), 2.8)
		draw_circle(tip, 1.8, Color(0.82, 0.85, 0.90))
		# White fletching
		var perp: Vector2 = Vector2(-_flight_dir.y, _flight_dir.x) * 2.4
		var f_pos: Vector2 = tail + _flight_dir * 2.0
		draw_line(f_pos - perp, f_pos + perp, Color(0.95, 0.95, 0.98, 0.90), 1.6)



