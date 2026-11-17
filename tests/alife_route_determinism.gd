extends Node

# A-Life routes must not depend on request history: a world loaded from a save starts with
# empty caches and has to reproduce the routes of an uninterrupted world exactly.
func _ready() -> void:
	var world := AlifeWorldContext.new()
	world.seed_world(12345, 0.0)
	WorldSeedBuilder.populate(world)
	var pairs: Array = []
	for settlement: AlifeSettlement in world.settlements.all():
		for target_id: String in settlement.connections:
			var target: AlifeSettlement = world.settlements.find(target_id) as AlifeSettlement
			pairs.append([settlement.tile, target.tile + Vector2i(2, 2)])
			pairs.append([settlement.tile + Vector2i(30, 7), settlement.tile + Vector2i(-25, 40)])
	pairs = pairs.slice(0, 80)
	var forward := AlifeTravel.new()
	var solved: Dictionary = {}
	for pair: Array in pairs:
		solved[pair] = forward.path(12345, pair[0], pair[1])
	var backward := AlifeTravel.new()
	var reversed_pairs: Array = pairs.duplicate()
	reversed_pairs.reverse()
	var mismatches: int = 0
	var empty: int = 0
	for pair: Array in reversed_pairs:
		var route: Array[Vector2i] = backward.path(12345, pair[0], pair[1])
		if route != solved[pair]:
			mismatches += 1
		if route.is_empty():
			empty += 1
	var ok: bool = mismatches == 0 and empty == 0
	print("ALIFE_ROUTE_DETERMINISM: ", "PASS" if ok else "FAIL", " pairs=", pairs.size(), " mismatches=", mismatches, " empty=", empty)
	get_tree().quit(0 if ok else 1)
