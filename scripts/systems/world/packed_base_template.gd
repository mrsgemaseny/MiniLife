class_name PackedBaseTemplate
extends RefCounted

const MANIFEST_PATH: String = "res://data/base_tiles/manifest.json"
const PACKED_ROOT: String = "res://data/base_tiles/"
const SOURCE_ROOT: String = "res://future/bases Minilife/"
const MAX_CACHED_CHUNKS: int = 64

static var _manifest: Dictionary = {}

var source_path: String = ""
var block_count: int = 0
var bounds: Rect2i = Rect2i()
var _index: Dictionary = {}
var _tokens: Array = []
var _file: FileAccess = null
var _cache: Dictionary[Vector2i, Dictionary] = {}
var _cache_order: Array[Vector2i] = []


static func load_from_source(source: String) -> PackedBaseTemplate:
	if not source.begins_with(SOURCE_ROOT):
		push_error("PackedBaseTemplate: invalid source %s" % source)
		return null
	if not _ensure_manifest():
		return null
	var relative: String = source.trim_prefix(SOURCE_ROOT)
	for entry: Variant in _manifest.get("templates", []):
		if not (entry is Dictionary) or str(entry.get("source", "")) != relative:
			continue
		var template := PackedBaseTemplate.new()
		var b: Array = entry.get("bounds", [])
		if b.size() != 4:
			return null
		template.source_path = source
		template.block_count = int(entry.get("block_count", 0))
		template.bounds = Rect2i(int(b[0]), int(b[1]), int(b[2]) - int(b[0]) + 1, int(b[3]) - int(b[1]) + 1)
		template._index = entry.get("chunks", {})
		template._tokens = _manifest.get("tokens", [])
		template._file = FileAccess.open(PACKED_ROOT + str(entry.get("packed_file", "")), FileAccess.READ)
		if template._file == null:
			push_error("PackedBaseTemplate: compiled tile file missing for %s" % relative)
			return null
		return template
	push_error("PackedBaseTemplate: source not in manifest: %s" % relative)
	return null


static func has_source(relative: String) -> bool:
	if not _ensure_manifest():
		return false
	for entry: Variant in _manifest.get("templates", []):
		if entry is Dictionary and str(entry.get("source", "")) == relative:
			return true
	return false


static func _ensure_manifest() -> bool:
	if not _manifest.is_empty():
		return true
	var manifest_file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if manifest_file == null:
		push_error("PackedBaseTemplate: compiled manifest missing")
		return false
	var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
	if not (parsed is Dictionary) or int((parsed as Dictionary).get("schema_version", -1)) != 1:
		push_error("PackedBaseTemplate: unsupported manifest")
		return false
	_manifest = parsed as Dictionary
	return true


func block_at(tile: Vector2i) -> String:
	if not bounds.has_point(tile):
		return ""
	var chunk := Vector2i(tile.x / 16, tile.y / 16)
	return str(chunk_blocks(chunk).get(tile, ""))


func chunk_blocks(chunk: Vector2i) -> Dictionary:
	if _cache.has(chunk):
		return _cache[chunk]
	var key: String = "%d,%d" % [chunk.x, chunk.y]
	if not _index.has(key):
		return {}
	var span: Array = _index[key]
	var offset: int = int(span[0])
	var count: int = int(span[1])
	_file.seek(offset)
	var bytes: PackedByteArray = _file.get_buffer(count * 3)
	if bytes.size() != count * 3:
		push_error("PackedBaseTemplate: truncated chunk %s in %s" % [key, source_path])
		return {}
	var blocks: Dictionary = {}
	for index: int in range(count):
		var x: int = int(bytes[index * 3])
		var y: int = int(bytes[index * 3 + 1])
		var token_id: int = int(bytes[index * 3 + 2])
		if x >= 16 or y >= 16 or token_id >= _tokens.size():
			push_error("PackedBaseTemplate: invalid packed tile in %s" % source_path)
			return {}
		blocks[chunk * 16 + Vector2i(x, y)] = _tokens[token_id]
	_cache[chunk] = blocks
	_cache_order.append(chunk)
	if _cache_order.size() > MAX_CACHED_CHUNKS:
		_cache.erase(_cache_order.pop_front())
	return blocks
