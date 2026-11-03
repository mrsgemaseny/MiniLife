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


func get_nearby_containers(center_tile: Vector2i, max_tile_dist: int = 4) -> Array[InventoryComponent]:
	var list: Array[InventoryComponent] = []
	for key in _containers:
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() == 2:
			var tpos: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
			if Config.tile_distance(center_tile, tpos) <= max_tile_dist:
				var c_inv: InventoryComponent = _containers[key] as InventoryComponent
				if c_inv != null:
					list.append(c_inv)
	return list


func count_item_in_radius(center_tile: Vector2i, item_id: String, max_tile_dist: int = 4) -> int:
	var total: int = 0
	var containers: Array[InventoryComponent] = get_nearby_containers(center_tile, max_tile_dist)
	for cinv in containers:
		total += cinv.get_item_count(item_id)
	return total


func remove_item_from_radius(center_tile: Vector2i, item_id: String, amount: int, max_tile_dist: int = 4) -> int:
	var needed: int = amount
	var containers: Array[InventoryComponent] = get_nearby_containers(center_tile, max_tile_dist)
	for cinv in containers:
		if needed <= 0:
			break
		var available: int = cinv.get_item_count(item_id)
		if available > 0:
			var to_take: int = mini(available, needed)
			cinv.remove_item(item_id, to_take)
			needed -= to_take
	return amount - needed


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for key in _containers:
		var inv: InventoryComponent = _containers[key] as InventoryComponent
		if inv != null:
			out[key] = {
				"title": str(_titles_by_container.get(key, "Storage Chest")),
				"gold": int(_gold_by_container.get(key, 0)),
				"inventory": inv.to_dict()
			}
	return out


func from_dict(data: Dictionary) -> void:
	_containers.clear()
	_gold_by_container.clear()
	_titles_by_container.clear()
	for key in data:
		var entry: Dictionary = data[key] as Dictionary
		if entry != null:
			_titles_by_container[key] = str(entry.get("title", "Storage Chest"))
			_gold_by_container[key] = int(entry.get("gold", 0))
			var inv: InventoryComponent = InventoryComponent.new()
			inv.max_slots = 18
			inv.max_weight = 250.0
			inv.from_dict(entry.get("inventory", {}))
			_containers[key] = inv

