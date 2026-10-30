class_name IsoMath
extends RefCounted


static func tile_to_screen(tile_pos: Vector2i) -> Vector2:
	return Config.world_to_iso(tile_pos)


static func screen_to_tile(screen_pos: Vector2) -> Vector2i:
	return Config.iso_to_world(screen_pos)


static func diamond_polygon(center: Vector2, half_w: float = 32.0, half_h: float = 16.0) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -half_h),
		center + Vector2(half_w, 0.0),
		center + Vector2(0.0, half_h),
		center + Vector2(-half_w, 0.0)
	])


static func bresenham_line(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0: int = start.x
	var y0: int = start.y
	var x1: int = end.x
	var y1: int = end.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return points


static func tiles_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var r_sq: int = radius * radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy <= r_sq:
				result.append(center + Vector2i(dx, dy))
	return result


static func snap_direction_4(vec: Vector2) -> Vector2i:
	if vec == Vector2.ZERO:
		return Vector2i(0, 1)
	if absf(vec.x) >= absf(vec.y):
		return Vector2i(1, 0) if vec.x >= 0.0 else Vector2i(-1, 0)
	return Vector2i(0, 1) if vec.y >= 0.0 else Vector2i(0, -1)


static func direction_suffix(dir: Vector2i) -> String:
	if dir.x > 0:
		return "e"
	elif dir.x < 0:
		return "w"
	elif dir.y < 0:
		return "n"
	return "s"
