class_name AlifeRegistry
extends RefCounted

var _records: Dictionary = {}
var _id_field: String
var _factory: Callable
var _order_dirty: bool = true
var _ordered_cache: Array = []

func _init(id_field: String, factory: Callable) -> void:
	_id_field = id_field
	_factory = factory

func register(record: AlifeRecord) -> bool:
	var id: String = str(record.get(_id_field))
	if id.is_empty() or _records.has(id):
		return false
	_records[id] = record
	_order_dirty = true
	return true

func find(id: String) -> AlifeRecord:
	return _records.get(id) as AlifeRecord

func all() -> Array:
	if _order_dirty:
		var ids: Array = _records.keys()
		ids.sort()
		_ordered_cache.clear()
		for id: String in ids:
			_ordered_cache.append(_records[id])
		_order_dirty = false
	return _ordered_cache.duplicate()

func matching(field: String, value: Variant) -> Array:
	var result: Array = []
	for record: AlifeRecord in all():
		if record.get(field) == value:
			result.append(record)
	return result

func remove(id: String) -> void:
	_records.erase(id)
	_order_dirty = true

func clear() -> void:
	_records.clear()
	_ordered_cache.clear()
	_order_dirty = true

func to_array() -> Array:
	var result: Array = []
	var ids: Array = _records.keys()
	ids.sort()
	for id: String in ids:
		result.append((_records[id] as AlifeRecord).to_dict())
	return result

func restore(rows: Array) -> bool:
	var next: Dictionary = {}
	for row: Variant in rows:
		if not row is Dictionary:
			return false
		var record: AlifeRecord = _factory.call(row) as AlifeRecord
		if record == null:
			return false
		var id: String = str(record.get(_id_field))
		if id.is_empty() or next.has(id):
			return false
		next[id] = record
	_records = next
	_order_dirty = true
	return true
