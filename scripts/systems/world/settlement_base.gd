class_name SettlementBase
extends RefCounted

const FORMAT: String = "pixel_architect_v1"
const SURFACES: Array[String] = ["grass", "dirt", "water"]
const SERVICE_KINDS: Array[String] = ["storage", "forge"]
const STRUCTURES: Dictionary[String, String] = {
	"wood_floor": "floor",
	"stone_floor": "stone_floor",
	"wood_wall": "wood_wall",
	"stone_wall": "wall",
	"pillar": "wall",
	"brick": "wall",
	"door": "door",
}

var anchor: Vector2i
var bounds: Rect2i
var first_generator_version: int
var _blocks: Dictionary[Vector2i, String] = {}
var _facilities: Dictionary[Vector2i, Dictionary] = {}
var _quarter_turns: int = 0


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
	layout.anchor = _coordinate(doc.get("anchor"), size) if entry == Vector2i(-1, -1) else entry
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
	var entry_block: String = layout.block_at(layout.anchor)
	if entry_block.is_empty() or not is_walkable(entry_block):
		return null
	var facilities: Variant = doc.get("facilities", {})
	if not facilities is Dictionary:
		return null
	for key: String in facilities:
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return null
		var tile: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
		var row: Variant = facilities[key]
		if not area.has_point(tile) or tile == layout.anchor or layout._facilities.has(tile) \
				or layout.block_at(tile) not in ["wood_floor", "stone_floor"] or not row is Dictionary or row.get("kind") not in SERVICE_KINDS:
			return null
		var door: Vector2i = _coordinate(row.get("door"), size)
		if layout.block_at(door) != "door" or Config.tile_distance(door, tile) > 42:
			return null
		var fixture: Dictionary = {"kind": row["kind"], "door": door}
		fixture.make_read_only()
		layout._facilities[tile] = fixture
	layout._facilities.make_read_only()
	layout._blocks.make_read_only()
	return layout


static func _coordinate(raw: Variant, size: int) -> Vector2i:
	if not raw is Array or raw.size() != 2:
		return Vector2i(-1, -1)
	for axis: Variant in raw:
		if not (axis is int or axis is float) or axis < 0 or axis >= size or not is_finite(float(axis)) or floorf(axis) != axis:
			return Vector2i(-1, -1)
	return Vector2i(int(raw[0]), int(raw[1]))


func block_at(local_tile: Vector2i) -> String:
	return _blocks.get(_source_tile(local_tile), "")


func facility_at(local_tile: Vector2i) -> Dictionary:
	if _facilities.is_empty():
		return {}
	var fixture: Dictionary = _facilities.get(_source_tile(local_tile), {})
	if fixture.is_empty() or _quarter_turns == 0:
		return fixture
	var door: Vector2i = fixture["door"]
	return {"kind": fixture["kind"], "door": anchor + _turn(door - anchor, _quarter_turns)}


func _source_tile(local_tile: Vector2i) -> Vector2i:
	return local_tile if _quarter_turns == 0 else anchor + _turn(local_tile - anchor, 4 - _quarter_turns)


func rotated(quarter_turns: int) -> SettlementBase:
	var turns: int = posmod(quarter_turns, 4)
	if turns == 0:
		return self
	var layout := SettlementBase.new()
	layout.anchor = anchor
	layout.first_generator_version = first_generator_version
	layout._blocks = _blocks
	layout._facilities = _facilities
	layout._quarter_turns = posmod(_quarter_turns + turns, 4)
	var first: Vector2i = bounds.position - anchor
	var last: Vector2i = bounds.end - Vector2i.ONE - anchor
	var lower: Vector2i = _turn(first, turns)
	var upper: Vector2i = lower
	for corner: Vector2i in [Vector2i(first.x, last.y), Vector2i(last.x, first.y), last]:
		var result: Vector2i = _turn(corner, turns)
		lower = lower.min(result)
		upper = upper.max(result)
	layout.bounds = Rect2i(anchor + lower, upper - lower + Vector2i.ONE)
	return layout


static func _turn(offset: Vector2i, turns: int) -> Vector2i:
	match turns:
		1: return Vector2i(-offset.y, offset.x)
		2: return -offset
		3: return Vector2i(offset.y, -offset.x)
		_: return offset


static func structure_for(block: String) -> String:
	return STRUCTURES.get(block, "")


static func biome_for(block: String) -> String:
	return "water" if block == "water" else "plains"


static func is_walkable(block: String) -> bool:
	return block != "water" and structure_for(block) not in ["wall", "wood_wall"]
