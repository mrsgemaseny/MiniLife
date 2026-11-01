class_name StorageManager
extends RefCounted

var _containers: Dictionary = {}
var _gold_by_container: Dictionary = {}
var _titles_by_container: Dictionary = {}


func get_or_create_container(tile_pos: Vector2i) -> InventoryComponent:
	var key: String = Config.vec2i_to_key(tile_pos)
	if not _containers.has(key):
		var inv: InventoryComponent = InventoryComponent.new()
		inv.max_slots = 18
		inv.max_weight = 250.0
		_containers[key] = inv
	return _containers[key]


func remove_container(tile_pos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	_containers.erase(key)
	_gold_by_container.erase(key)
	_titles_by_container.erase(key)


func get_container_gold(tile_pos: Vector2i) -> int:
	var key: String = Config.vec2i_to_key(tile_pos)
	return int(_gold_by_container.get(key, 0))


func set_container_gold(tile_pos: Vector2i, amount: int) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	_gold_by_container[key] = maxi(0, amount)


func get_container_title(tile_pos: Vector2i) -> String:
	var key: String = Config.vec2i_to_key(tile_pos)
	return str(_titles_by_container.get(key, "Storage Chest"))


func set_container_title(tile_pos: Vector2i, title: String) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	_titles_by_container[key] = title


func populate_chest_loot(tile_pos: Vector2i, title: String, gold: int, items: Dictionary) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	if _containers.has(key):
		return
	set_container_title(tile_pos, title)
	set_container_gold(tile_pos, gold)
	var inv: InventoryComponent = get_or_create_container(tile_pos)
	for item_id in items:
		var cnt: int = int(items[item_id])
		inv.add_item(str(item_id), cnt)

