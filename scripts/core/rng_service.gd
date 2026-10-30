class_name RngService
extends RefCounted


static func hash_coords(world_seed: int, x: int, y: int, salt: int = 0) -> int:
	var h: int = world_seed ^ (x * 374761393) ^ (y * 668265263) ^ (salt * 2147483647)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


static func make_tile_rng(world_seed: int, tile_pos: Vector2i, salt: int = 0) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash_coords(world_seed, tile_pos.x, tile_pos.y, salt)
	return rng


static func make_chunk_rng(world_seed: int, chunk_pos: Vector2i, salt: int = 0) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash_coords(world_seed, chunk_pos.x, chunk_pos.y, salt ^ 0x9E3779B9)
	return rng


static func weighted_pick(rng: RandomNumberGenerator, items: Array, weight_key: String = "weight") -> Dictionary:
	if items.is_empty():
		return {}
	var total: float = 0.0
	for entry in items:
		if entry is Dictionary:
			total += maxf(float(entry.get(weight_key, 1.0)), 0.001)
	if total <= 0.0:
		return items[0] if items[0] is Dictionary else {}
	var roll: float = rng.randf() * total
	var accum: float = 0.0
	for entry in items:
		if entry is Dictionary:
			accum += maxf(float(entry.get(weight_key, 1.0)), 0.001)
			if roll <= accum:
				return entry
	return items.back() if items.back() is Dictionary else {}
