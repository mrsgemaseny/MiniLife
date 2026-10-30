class_name BlueprintPlacer
extends RefCounted


static func draw_ghost_preview(canvas: CanvasItem, tile_pos: Vector2i, valid: bool) -> void:
	if canvas == null:
		return
	var center: Vector2 = Config.world_to_iso(tile_pos)
	var poly: PackedVector2Array = IsoMath.diamond_polygon(center, float(Config.HALF_TILE.x), float(Config.HALF_TILE.y))
	var fill: Color = Color(0.2, 0.9, 0.45, 0.38) if valid else Color(0.95, 0.25, 0.25, 0.38)
	canvas.draw_colored_polygon(poly, fill)
	canvas.draw_polyline(poly, fill.lightened(0.25), 2.0, true)
