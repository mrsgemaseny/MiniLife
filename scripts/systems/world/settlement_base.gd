class_name SettlementBase
extends RefCounted

const FORMAT: String = "pixel_architect_v1"
const SURFACES: Array[String] = ["grass", "dirt", "water"]
const STRUCTURES: Dictionary[String, String] = {
	"wood_floor": "floor",
	"stone_floor": "stone_floor",
	"wood_wall": "wood_wall",
	"stone_wall": "wall",
	"pillar": "wall",
	"door": "door",
}

var anchor: Vector2i
var bounds: Rect2i
var first_generator_version: int
var _blocks: Dictionary[Vector2i, String] = {}


static func load_from(path: String, entry: Vector2i, version: int) -> SettlementBase:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var doc: Variant = JSON.parse_string(file.get_as_text())
	if not doc is Dictionary or doc.get("format") != FORMAT:
		return null
	var size: int = GlobalLandscapeMap.CELL_TILES
	var source_size: Variant = doc.get("map_size")
	if not source_size is Array or source_size.size() != 2 or source_size[0] != size or source_size[1] != size \
			or not doc.get("blocks") is Dictionary:
		return null
	var raw_blocks: Dictionary = doc["blocks"]
	if raw_blocks.is_empty() or doc.get("total_blocks") != raw_blocks.size():
		return null
	var layout := SettlementBase.new()
	layout.anchor = entry
	layout.first_generator_version = version
	var area := Rect2i(0, 0, size, size)
	var lower := Vector2i(size, size)
	var upper := Vector2i.ZERO
	for key: String in raw_blocks:
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return null
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var block: Variant = raw_blocks[key]
		if not area.has_point(tile) or layout._blocks.has(tile) \
				or not block is String or (block not in SURFACES and not STRUCTURES.has(block)):
			return null
		layout._blocks[tile] = block
		lower = lower.min(tile)
		upper = upper.max(tile)
	layout.bounds = Rect2i(lower, upper - lower + Vector2i.ONE)
	var entry_block: String = layout.block_at(entry)
	if entry_block.is_empty() or not is_walkable(entry_block):
		return null
	layout._blocks.make_read_only()
	return layout


func block_at(local_tile: Vector2i) -> String:
	return _blocks.get(local_tile, "")


static func structure_for(block: String) -> String:
	return STRUCTURES.get(block, "")


static func biome_for(block: String) -> String:
	return "water" if block == "water" else "plains"


static func is_walkable(block: String) -> bool:
	return block not in ["water", "wood_wall", "stone_wall", "pillar"]
