class_name DefenseNetwork
extends RefCounted

var _wall_tiles: Dictionary = {}
var _trap_tiles: Dictionary = {}


func register_structure(structure_id: String, tile_pos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	if structure_id == "wall" or structure_id == "door":
		_wall_tiles[key] = structure_id
	elif structure_id.ends_with("trap"):
		_trap_tiles[key] = structure_id


func unregister_tile(tile_pos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	_wall_tiles.erase(key)
	_trap_tiles.erase(key)


func get_defense_score() -> int:
	return _wall_tiles.size() * 5 + _trap_tiles.size() * 12
