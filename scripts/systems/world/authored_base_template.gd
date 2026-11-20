class_name AuthoredBaseTemplate
extends RefCounted

const FORMAT: String = "pixel_architect_v1"
const CELL_SIZE: int = 1000
const TILES_PER_CHUNK: int = 16
const TOKENS: Array[String] = [
	"brick", "dirt", "door", "grass", "pillar", "stone_floor", "stone_wall",
	"water", "wheat", "wood_floor", "wood_wall",
]

var source_path: String = ""
var block_count: int = 0
var bounds: Rect2i = Rect2i()
var _chunks: Dictionary[Vector2i, Dictionary] = {}


static func load_from(path: String) -> AuthoredBaseTemplate:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("AuthoredBaseTemplate: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("AuthoredBaseTemplate: invalid JSON object in %s" % path)
		return null
	var template := AuthoredBaseTemplate.new()
	if not template._ingest(parsed as Dictionary):
		return null
	template.source_path = path
	return template


func _ingest(doc: Dictionary) -> bool:
	var size: Array = doc.get("map_size", [])
	if doc.get("format", "") != FORMAT or size.size() != 2 \
			or int(size[0]) != CELL_SIZE or int(size[1]) != CELL_SIZE:
		push_error("AuthoredBaseTemplate: unsupported map format or size")
		return false
	var blocks_value: Variant = doc.get("blocks")
	if not (blocks_value is Dictionary):
		push_error("AuthoredBaseTemplate: blocks missing")
		return false
	var blocks: Dictionary = blocks_value as Dictionary
	if int(doc.get("total_blocks", -1)) != blocks.size():
		push_error("AuthoredBaseTemplate: total_blocks mismatch")
		return false
	var low := Vector2i(CELL_SIZE, CELL_SIZE)
	var high := Vector2i(-1, -1)
	for key: String in blocks:
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			push_error("AuthoredBaseTemplate: invalid tile coordinate %s" % key)
			return false
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var token: String = str(blocks[key])
		if tile.x < 0 or tile.y < 0 or tile.x >= CELL_SIZE or tile.y >= CELL_SIZE or not TOKENS.has(token):
			push_error("AuthoredBaseTemplate: invalid tile %s or token %s" % [key, token])
			return false
		var chunk := Vector2i(tile.x / TILES_PER_CHUNK, tile.y / TILES_PER_CHUNK)
		if not _chunks.has(chunk):
			_chunks[chunk] = {}
		_chunks[chunk][tile] = token
		low = low.min(tile)
		high = high.max(tile)
		block_count += 1
	if block_count > 0:
		bounds = Rect2i(low, high - low + Vector2i.ONE)
	return true


func block_at(tile: Vector2i) -> String:
	if not bounds.has_point(tile):
		return ""
	var chunk := Vector2i(tile.x / TILES_PER_CHUNK, tile.y / TILES_PER_CHUNK)
	return str(_chunks.get(chunk, {}).get(tile, ""))


func chunk_blocks(chunk: Vector2i) -> Dictionary:
	return _chunks.get(chunk, {})
