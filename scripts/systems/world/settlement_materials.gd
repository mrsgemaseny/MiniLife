extends RefCounted

const ATLAS: Texture2D = preload("res://assets/sprites/world/settlement_materials/city_materials.png")
enum Kind {
	MEADOW, GRAVEL, COBBLE, FLAGSTONE,
	TERRACOTTA, SLATE, SHINGLES, SOOTED_TILE,
	ASHLAR, PLASTER, OAK, MOSAIC,
	EARTH, DRY_MEADOW, RUBBLE, OCHRE_TILE,
}


static func draw_surface(canvas: CanvasItem, bounds: Rect2, material: int, tint: Color) -> void:
	canvas.draw_texture_rect_region(ATLAS, bounds, _region(material), tint)


static func draw_ground(canvas: CanvasItem, tile: Vector2i, material: int, period: int, tint: Color, offset_px: Vector2 = Vector2.ZERO) -> void:
	var patch: Rect2 = _region(material)
	var step: Vector2 = patch.size / float(period)
	var offset := Vector2(posmod(tile.x, period), posmod(tile.y, period))
	var sample := Rect2(patch.position + offset * step, step)
	var bounds := Rect2(Config.world_to_iso(tile) - Vector2(Config.HALF_TILE) + offset_px, Vector2(Config.TILE_SIZE))
	canvas.draw_texture_rect_region(ATLAS, bounds, sample, tint, false, false)


static func _region(material: int) -> Rect2:
	var cell: Vector2 = ATLAS.get_size() * 0.25
	return Rect2(Vector2(material % 4, floori(float(material) / 4.0)) * cell, cell).grow(-2)
