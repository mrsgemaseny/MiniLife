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

	var prev_pos: Vector2 = global_position
	var step: float = speed * delta
	global_position += direction * step
	_distance_travelled += step

	var progress: float = clampf(_distance_travelled / maxf(1.0, max_range), 0.0, 1.0)
	# Flat trajectory: subtle ballistic arc (3.5px for arrows, 5.0px for javelins)
	var arc_apex: float = 3.5 if projectile_type == "arrow" else 5.0
	_current_altitude = maxf(0.0, 12.0 * (1.0 - progress * progress * 0.95) + sin(progress * PI) * arc_apex)

	# Ballistic flight direction tangent (almost straight forward, slight descent at tail end)
	var d_alt: float = -20.0 * progress / max_range + (PI / max_range) * arc_apex * cos(progress * PI)
	var screen_vec: Vector2 = direction + Vector2(0.0, -d_alt * 0.25)
	if screen_vec.length_squared() > 0.01:
		_flight_dir = screen_vec.normalized()

	queue_redraw()

	var prev_tip: Vector2 = prev_pos + Vector2(0.0, -_current_altitude)
	var current_tip: Vector2 = global_position + Vector2(0.0, -_current_altitude)

	# Check combatant hits with continuous collision segment and point-blank detection
	var hit_radius: float = 34.0 if projectile_type == "javelin" else 26.0
	var closest_hit_node: Node2D = null
	var closest_dist: float = 99999.0

	for node in get_tree().get_nodes_in_group("combatant"):
		if node == shooter or not (node is Node2D):
			continue
		if shooter is EnemyBase and node is EnemyBase and (shooter as EnemyBase).faction_id == (node as EnemyBase).faction_id:
			continue
		var n2d: Node2D = node as Node2D
		if not n2d.is_visible_in_tree():
			continue
		if n2d.has_method("is_alive") and not bool(n2d.call("is_alive")):
			continue

		# Target hit-center (wolf/beast torso at -10px, humanoid at -14px)
		var center_y: float = -10.0 if (n2d.is_in_group("enemy") or n2d.is_in_group("animal") or n2d.is_in_group("fauna")) else -14.0
		var target_center: Vector2 = n2d.global_position + Vector2(0.0, center_y)

		# 1. Point-blank guarantee: if target is within 55px of shooter along firing direction, guarantee hit!
		if shooter != null and is_instance_valid(shooter) and shooter is Node2D:
			var s2d: Node2D = shooter as Node2D
			var to_target: Vector2 = target_center - (s2d.global_position + Vector2(0.0, -12.0))
			var dist_to_shooter: float = to_target.length()
			if dist_to_shooter <= 55.0:
				var forward_dot: float = to_target.normalized().dot(direction)
				if forward_dot > 0.30 and _distance_travelled <= 58.0:
					if dist_to_shooter < closest_dist:
						closest_dist = dist_to_shooter
						closest_hit_node = n2d
						continue

		# 2. Continuous ray segment check
		var seg_dist: float = _dist_to_segment(target_center, prev_tip, current_tip)
		if seg_dist <= hit_radius:
			var d_proj: float = prev_tip.distance_to(target_center)
			if d_proj < closest_dist:
				closest_dist = d_proj
				closest_hit_node = n2d

	if closest_hit_node != null:
		SignalBus.arrow_impacted.emit(current_tip, "flesh")
		SignalBus.projectile_hit_confirmed.emit(closest_hit_node, damage, damage_type, shooter if is_instance_valid(shooter) else null)
		queue_free()
		return

	if _distance_travelled >= max_range:
		_is_stuck = true
		_current_altitude = 0.0
		SignalBus.arrow_impacted.emit(global_position, "ground")
		# Natural landing angle into the ground along shot direction
		var land_vec: Vector2 = direction + Vector2(0.0, 0.40 if projectile_type == "javelin" else 0.30)
		_flight_dir = land_vec.normalized()
		queue_redraw()


func _draw() -> void:
	var tip: Vector2 = Vector2(0.0, -_current_altitude)
	var is_jav: bool = (projectile_type == "javelin")
	var proj_len: float = JAVELIN_LENGTH if is_jav else ARROW_LENGTH
	var tail: Vector2 = tip - _flight_dir * proj_len

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


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)




