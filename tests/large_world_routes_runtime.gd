extends Node

# Fixture in the start cell, outside the start clearing (clearings never hold water).
const BASE: Vector2i = Vector2i(9700, 14300)

class TestTerrain extends TerrainGenerator:
	func get_biome_at(tile: Vector2i) -> String:
		var local: Vector2i = tile - BASE
		return "water" if local.x == 110 and local.y >= 90 and local.y <= 110 else "plains"

func _ready() -> void:
	var travel := AlifeTravel.new()
	travel.background_enabled = true
	travel._worker_solver = AlifeTravel.new()
	travel._worker_solver._prepare(42)
	travel._worker_solver._grid.terrain = TestTerrain.new(42)
	var start: int = Time.get_ticks_usec()
	assert(travel.request_path(42, BASE + Vector2i(100, 100), BASE + Vector2i(120, 100)).is_empty())
	var request_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	var route: Array[Vector2i] = []
	for frame: int in range(1800):
		await get_tree().process_frame
		travel.poll()
		route = travel.request_path(42, BASE + Vector2i(100, 100), BASE + Vector2i(120, 100))
		if not route.is_empty():
			break
	assert(not route.is_empty())
	assert(route.front() == BASE + Vector2i(100, 100) and route.back() == BASE + Vector2i(120, 100))
	for i: int in range(route.size()):
		assert(travel._worker_solver._grid.terrain.get_biome_at(route[i]) != "water")
		if i > 0:
			assert(Config.tile_distance(route[i - 1], route[i]) <= 1)
	travel.shutdown()
	print("LARGE_ROUTES_PASS: background detour, continuous walkable tiles, request_ms=", request_ms, " cells=", route.size())
	get_tree().quit()
