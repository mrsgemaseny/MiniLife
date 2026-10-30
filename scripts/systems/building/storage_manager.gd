class_name StorageManager
extends RefCounted

var _containers: Dictionary = {}


func get_or_create_container(tile_pos: Vector2i) -> InventoryComponent:
	var key: String = Config.vec2i_to_key(tile_pos)
	if not _containers.has(key):
		var inv: InventoryComponent = InventoryComponent.new()
		inv.max_slots = 18
		inv.max_weight = 250.0
		_containers[key] = inv
	return _containers[key]


func remove_container(tile_pos: Vector2i) -> void:
	_containers.erase(Config.vec2i_to_key(tile_pos))
