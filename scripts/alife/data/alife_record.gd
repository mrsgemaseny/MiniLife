class_name AlifeRecord
extends RefCounted

# Serialization is explicit: no engine instance IDs or Node references enter saves.
func _fields() -> Array[String]:
	return []

func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for field: String in _fields():
		var value: Variant = get(field)
		if value is Vector2i:
			result[field] = [value.x, value.y]
		elif value is Color:
			result[field] = value.to_html()
		elif value is Dictionary or value is Array:
			result[field] = value.duplicate(true)
		else:
			result[field] = value
	return result

func restore(data: Dictionary) -> void:
	for field: String in _fields():
		if not data.has(field):
			continue
		var current: Variant = get(field)
		var value: Variant = data[field]
		if current is Vector2i:
			if value is Array and value.size() == 2:
				set(field, Vector2i(int(value[0]), int(value[1])))
		elif current is Color:
			set(field, Color.from_string(str(value), current))
		elif current is int and (value is int or value is float):
			set(field, int(value))
		elif current is float and (value is int or value is float):
			set(field, float(value))
		elif typeof(current) == typeof(value):
			set(field, value.duplicate(true) if value is Array or value is Dictionary else value)
