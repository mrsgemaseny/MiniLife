extends RefCounted
const ART = preload("res://scripts/entities/pawn_flat_art.gd")

static func draw_pawn(canvas: Node2D, offset: Vector2, facing: Vector2, equipment: EquipmentComponent, clothing_tint: Color = Color.WHITE, head_lift: float = 0.0) -> void:
	ART.draw_pawn(canvas, offset, facing, equipment, clothing_tint, head_lift)
