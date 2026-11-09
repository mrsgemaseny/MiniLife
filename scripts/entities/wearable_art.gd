class_name WearableArt
extends RefCounted

const SLOTS: Array[String] = ["feet", "legs", "clothing", "chest", "head"]
static var _textures: Dictionary = {}
static var _regions: Dictionary = {}
const DIRECTIONAL: Dictionary = {
	"gambeson": ["clothing", 0], "quality_clothing": ["clothing", 1], "arming_doublet": ["clothing", 2], "wool_shirt": ["clothing", 3],
	"leather_armor": ["armor_basic", 0], "simple_chainmail": ["pawn_bodies_metal_v1", 0], "iron_chainmail": ["pawn_bodies_metal_v1", 0],
	"bronze_cuirass": ["pawn_bodies_metal_v1", 2], "iron_lamellar": ["armor_basic", 3],
	"iron_scale_armor": ["armor_advanced", 0], "iron_brigandine": ["armor_advanced", 1], "bronze_lamellar": ["armor_advanced", 2], "leather_lamellar": ["armor_advanced", 3],
	"iron_helmet": ["heads_basic", 0], "bronze_helmet": ["heads_basic", 1], "leather_helmet": ["heads_basic", 2],
	"steel_helmet": ["heads_matched_v3", 0], "iron_great_helm": ["heads_pot_helm_v1", 0], "wool_hood": ["heads_matched_v3", 2], "chainmail_coif": ["heads_matched_v3", 3],
	"boiled_leather_cuirass": ["torsos_matched_v3", 0], "iron_hauberk": ["pawn_bodies_metal_v1", 1], "iron_armor": ["pawn_bodies_metal_v1", 3],
	"iron_plate_armor": ["pawn_bodies_metal_v1", 4], "steel_cuirass": ["pawn_bodies_metal_v1", 5], "steel_plate_armor": ["pawn_bodies_metal_v1", 6], "steel_brigandine": ["torsos_matched_v3", 6],
	"wool_wraps": ["lower_matched_v3", 0], "leather_greaves": ["lower_matched_v3", 1], "bronze_greaves": ["lower_matched_v3", 2], "iron_greaves": ["lower_matched_v3", 3], "steel_greaves": ["lower_matched_v3", 4],
	"leather_boots": ["lower_matched_v3", 5], "bronze_boots": ["lower_matched_v3", 6], "iron_boots": ["lower_matched_v3", 7], "steel_boots": ["lower_matched_v3", 8]
}

static func texture_for(id: String) -> Texture2D:
	if not DIRECTIONAL.has(id):
		return null
	var path: String = "res://assets/sprites/characters/generated/" + str(DIRECTIONAL[id][0]) + ".png"
	if _textures.has(path):
		return _textures[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path) as Texture2D
	_textures[path] = texture
	return texture

static func region_for(id: String, facing: Vector2) -> Rect2:
	if _regions.is_empty():
		_regions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/characters/generated/wearable_regions_v3.json"))
	if not DIRECTIONAL.has(id):
		return Rect2()
	var entry: Array = DIRECTIONAL[id]
	var side: bool = absf(facing.x) > absf(facing.y)
	var col: int = (1 if facing.x > 0 else 3) if side else (2 if facing.y < 0 else 0)
	var frame: Array = _regions[str(entry[0])][int(entry[1])][col]
	return Rect2(float(frame[0]), float(frame[1]), float(frame[2]), float(frame[3]))

static func destination(slot: String, facing: Vector2) -> Rect2:
	var side: bool = absf(facing.x) > absf(facing.y)
	var width_scale: float = 0.72 if side else 1.0
	match slot:
		"head": return Rect2(-12.5, -47.0, 25.0, 23.0)
		"chest": return Rect2(-15.0 * width_scale, -29.0, 30.0 * width_scale, 29.0)
		"clothing": return Rect2(-15.5 * width_scale, -29.0, 31.0 * width_scale, 29.0)
		"legs": return Rect2(-10.0 * width_scale, -5.0, 20.0 * width_scale, 5.0)
		"feet": return Rect2(-10.0 * width_scale, -2.0, 20.0 * width_scale, 2.0)
	return Rect2()

static func draw_slot(canvas: Node2D, offset: Vector2, facing: Vector2, equipment: EquipmentComponent, slot: String) -> void:
	var id: String = equipment.get_item_id(slot)
	if id.is_empty():
		return
	var texture: Texture2D = texture_for(id)
	if texture == null:
		return
	var rect: Rect2 = destination(slot, facing)
	rect.position += offset
	var source: Rect2 = region_for(id, facing)
	canvas.draw_texture_rect_region(texture, rect, source)
