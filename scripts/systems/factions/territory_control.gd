class_name TerritoryControl
extends RefCounted

# Tracks faction control over chunk coordinates.

var chunk_owners: Dictionary = {} # Vector2i -> faction_id

func get_chunk_owner(chunk_coord: Vector2i) -> String:
	if chunk_owners.has(chunk_coord):
		return str(chunk_owners[chunk_coord])
	var dist: int = maxi(abs(chunk_coord.x), abs(chunk_coord.y))
	if dist <= 1:
		return "settlers"
	if (chunk_coord.x + chunk_coord.y) % 3 == 0:
		return "raiders"
	return "traders_guild"

func set_chunk_owner(chunk_coord: Vector2i, faction_id: String) -> void:
	chunk_owners[chunk_coord] = faction_id
