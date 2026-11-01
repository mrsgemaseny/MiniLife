class_name BlueprintPlacer
extends RefCounted


static func draw_ghost_preview(canvas: CanvasItem, tile_pos: Vector2i, valid: bool, smooth_center: Vector2 = Vector2.ZERO, pulse_phase: float = 0.0, structure_id: String = "") -> void:
	if canvas == null:
		return
	var center: Vector2 = smooth_center if smooth_center != Vector2.ZERO else Config.world_to_iso(tile_pos)
	var pulse: float = 1.0 + sin(pulse_phase) * 0.05
	var hw: float = float(Config.HALF_TILE.x) * 0.88 * pulse
	var hh: float = float(Config.HALF_TILE.y) * 0.88 * pulse
	var poly: PackedVector2Array = IsoMath.diamond_polygon(center, hw, hh)
	var alpha_pulse: float = 0.34 + sin(pulse_phase) * 0.08
	var fill: Color = Color(0.22, 0.92, 0.48, alpha_pulse) if valid else Color(0.95, 0.25, 0.25, alpha_pulse)
	var wire_col: Color = fill.lightened(0.32)
	wire_col.a = 0.90
	canvas.draw_colored_polygon(poly, fill)
	canvas.draw_polyline(poly, wire_col, 2.0, true)

	# 3D Isometric Blueprint Box Wireframe
	var def: Dictionary = DataRegistry.get_structure(structure_id) if structure_id != "" else {}
	var h_px: float = float(def.get("height_px", 16.0))
	if h_px > 6.0:
		var top_poly: PackedVector2Array = IsoMath.diamond_polygon(center + Vector2(0.0, -h_px), hw, hh)
		var top_fill: Color = fill
		top_fill.a *= 0.65
		canvas.draw_colored_polygon(top_poly, top_fill)
		canvas.draw_polyline(top_poly, wire_col, 1.6, true)
		for i in range(4):
			canvas.draw_line(poly[i], top_poly[i], wire_col, 1.4)
