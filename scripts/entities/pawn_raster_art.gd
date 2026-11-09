class_name RasterPawnArt
extends RefCounted

const APPROVED_PATH: String = "res://assets/sprites/characters/generated/pawn_approved_steel_v1.png"
const MINIMAL: Texture2D = preload("res://assets/sprites/characters/generated/pawn_minimal_v1.png")
const BASE: Texture2D = preload("res://assets/sprites/characters/generated/pawn_simple.png")
const BASE_REGIONS: Array[Rect2] = [Rect2(97,46,249,434), Rect2(534,46,250,434), Rect2(984,46,250,434), Rect2(1434,46,249,434)]
static var _approved: Texture2D
static var _frames: Array = []

static func view_index(facing: Vector2) -> int:
	return (1 if facing.x > 0 else 3) if absf(facing.x) > absf(facing.y) else (2 if facing.y < 0 else 0)

static func approved_frame(facing: Vector2) -> Rect2:
	if _frames.is_empty():
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/characters/generated/wearable_regions_v3.json"))
		_frames = manifest["pawn_approved_steel_v1"][0]
	var frame: Array = _frames[view_index(facing)]
	return Rect2(frame[0], frame[1], frame[2], frame[3])

static func approved_texture() -> Texture2D:
	if _approved == null:
		_approved = load(APPROVED_PATH) as Texture2D
	return _approved

static func draw_pawn(canvas: Node2D, offset: Vector2, facing: Vector2, equipment: EquipmentComponent) -> void:
	var chest: String = equipment.get_item_id("chest") if equipment != null else ""
	var head: String = equipment.get_item_id("head") if equipment != null else ""
	var view: int = view_index(facing)
	var steel_set: bool = chest == "steel_plate_armor" and head == "steel_helmet"
	var starter: bool = chest.is_empty() and head.is_empty()
	if starter and equipment != null:
		for slot: String in ["clothing", "legs", "feet"]:
			if not equipment.get_item_id(slot).is_empty():
				starter = false
				break
	if steel_set or starter:
		# Each view shares the same baseline and scale within the atlas.
		var cell_width: float = MINIMAL.get_width() / 4.0
		var source: Rect2 = Rect2(view * cell_width, 450.0 if steel_set else 10.0, cell_width, 423.0)
		var size: Vector2 = source.size * (48.0 / source.size.y)
		var destination: Rect2 = Rect2(offset + Vector2(-size.x * 0.5, -size.y), size)
		canvas.draw_texture_rect_region(MINIMAL, destination, source)
		return
	var region: Rect2 = BASE_REGIONS[view]
	var side: bool = absf(facing.x) > absf(facing.y)
	var width: float = 20.0 if side else 27.0
	var body: Rect2 = Rect2(region.position + Vector2(0,262), region.size - Vector2(0,262))
	canvas.draw_texture_rect_region(BASE, Rect2(offset+Vector2(-width*0.5,-28),Vector2(width,28)),body)
	if equipment != null:
		for slot: String in ["legs", "feet", "clothing", "chest"]:
			WearableArt.draw_slot(canvas,offset,facing,equipment,slot)
	if equipment != null and WearableArt.texture_for(head) != null:
		WearableArt.draw_slot(canvas,offset,facing,equipment,"head")
	else:
		canvas.draw_texture_rect_region(BASE,Rect2(offset+Vector2(-10,-45),Vector2(20,21)),Rect2(region.position,Vector2(region.size.x,262)))
