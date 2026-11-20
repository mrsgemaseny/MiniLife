class_name BaseTemplateCatalog
extends RefCounted

const ASSIGNMENT_PATH: String = "res://data/base_assignment.json"
const SOURCE_ROOT: String = "res://future/bases Minilife/"
const POINT_TYPES: Array[String] = ["castle", "city", "fortress", "village", "hamlet", "independent", "bandit_camp"]

var _by_type: Dictionary[String, Array] = {}


static func load_default() -> BaseTemplateCatalog:
	var catalog := BaseTemplateCatalog.new()
	if not catalog.load_from(ASSIGNMENT_PATH):
		return null
	return catalog


func load_from(path: String) -> bool:
	_by_type.clear()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("BaseTemplateCatalog: cannot open %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("BaseTemplateCatalog: invalid JSON")
		return false
	var doc: Dictionary = parsed as Dictionary
	if int(doc.get("schema_version", -1)) != 1 or not doc.get("templates") is Array:
		push_error("BaseTemplateCatalog: unsupported schema")
		return false
	var seen: Dictionary[String, bool] = {}
	for entry: Variant in doc["templates"]:
		if not (entry is Dictionary):
			return false
		var item: Dictionary = entry as Dictionary
		var relative: String = str(item.get("file", ""))
		if relative.is_empty() or relative.begins_with("/") or relative.contains("..") or seen.has(relative) \
				or not PackedBaseTemplate.has_source(relative):
			push_error("BaseTemplateCatalog: invalid template path %s" % relative)
			return false
		seen[relative] = true
		var types: Variant = item.get("point_types")
		if not (types is Array) or (types as Array).is_empty():
			return false
		for kind: Variant in types:
			if not kind is String or not POINT_TYPES.has(kind):
				push_error("BaseTemplateCatalog: invalid point type %s" % str(kind))
				return false
			var point_type: String = kind
			if not _by_type.has(point_type):
				_by_type[point_type] = []
			_by_type[point_type].append(SOURCE_ROOT + relative)
	return true


func candidates(point_type: String) -> Array:
	return _by_type.get(point_type, []).duplicate()


func choose(point_type: String, seed_value: int, cell: Vector2i) -> String:
	var options: Array = _by_type.get(point_type, [])
	if options.is_empty():
		return ""
	var index: int = int(RngService.hash_coords(seed_value, cell.x, cell.y, 0xBA5E) % options.size())
	return str(options[index])
