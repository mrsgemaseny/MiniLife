extends RefCounted

enum Surface { GRAVEL, COBBLE, FLAGSTONE, FORUM }

static func build_core(structures: Dictionary, roofs: Array[Rect2i], origin: Vector2i, size: int, plan: int) -> Dictionary:
	if plan >= 3:
		return _build_civic_center(structures, roofs, origin, size)
	var paving: Dictionary = {}
	var middle: int = size / 2
	var plaza := Rect2i(origin + Vector2i(0, middle - 2), Vector2i(size, 4))
	_pave(paving, Rect2i(origin + Vector2i(middle - 1, 0), Vector2i(2, size)), Surface.COBBLE)
	_pave(paving, plaza, Surface.FLAGSTONE)
	var east: int = middle + 1
	var wing: int = middle - 1
	_house(structures, roofs, Rect2i(origin, Vector2i(wing, middle - 1)), "wall", "storage", false)
	_house(structures, roofs, Rect2i(origin + Vector2i(east, 0), Vector2i(wing, middle - 2)), "wall", "bed", false)
	_house(structures, roofs, Rect2i(origin + Vector2i(0, middle + 2), Vector2i(wing, middle - 2)), "wall", "workbench", true)
	_house(structures, roofs, Rect2i(origin + Vector2i(east, middle + 2), Vector2i(wing, middle - 2)), "wood_wall", "bed", true)
	_put(structures, plaza.position + Vector2i(0, 1), "torch")
	_put(structures, plaza.position + Vector2i(size - 1, 2), "torch")
	_put(structures, origin + Vector2i(size - 2, middle + 1), "well")
	var styles: Dictionary = {}
	if plan >= 2:
		styles[origin] = "basilica"
		styles[origin + Vector2i(east, 0)] = "temple"
		styles[origin + Vector2i(0, middle + 2)] = "insula"
		styles[origin + Vector2i(east, middle + 2)] = "villa"
		_pave(paving, Rect2i(plaza.position + Vector2i(0, 1), Vector2i(size, 2)), Surface.COBBLE)
	return {
		"paving": paving,
		"styles": styles,
		"props": {
			origin + Vector2i(1, middle - 1): "market_stall",
			origin + Vector2i(3, middle + 1): "grain_sacks",
			origin + Vector2i(size - 4, middle - 2): "sealed_barrels",
		},
	}


static func build_district(structures: Dictionary, roofs: Array[Rect2i], origin: Vector2i, crossing: Vector2i, direction: Vector2i, connections: Array[Vector2i], fort_level: int, plan: int) -> Dictionary:
	var paving: Dictionary = {}
	var props: Dictionary = {}
	var styles: Dictionary = {}
	var ramparts: Dictionary = {}
	var size: int = Config.CHUNK_SIZE
	var main_surface: int = Surface.COBBLE if direction.x == 0 or direction.y == 0 else Surface.GRAVEL
	_pave(paving, Rect2i(origin + Vector2i(crossing.x - 1, 0), Vector2i(2, size)), main_surface)
	_pave(paving, Rect2i(origin + Vector2i(0, crossing.y - 1), Vector2i(size, 2)), main_surface)
	for side: int in range(4):
		var east: bool = side % 2 == 1
		var south: bool = side >= 2
		var left: int = crossing.x + 1 if east else 1
		var right: int = size - 1 if east else crossing.x - 1
		var top: int = crossing.y + 2 if south else 1
		var bottom: int = size - 1 if south else crossing.y - 2
		var lot := Rect2i(origin + Vector2i(left, top), Vector2i(right - left, bottom - top))
		var frontage_y: int = top - 1 if south else bottom
		_pave(paving, Rect2i(origin + Vector2i(left, frontage_y), Vector2i(lot.size.x, 1)), Surface.GRAVEL)
		if plan >= 3 and direction == Vector2i.LEFT:
			_build_smithy_lot(structures, roofs, paving, props, styles, lot, side, south)
			continue
		if plan >= 2:
			_build_roman_lot(structures, roofs, paving, props, styles, lot, direction, side, south)
			continue
		var workshop: bool = direction == Vector2i.LEFT and side % 2 == 0
		var market: bool = direction == Vector2i.RIGHT and side == 1
		var yard: bool = (direction == Vector2i.RIGHT and side == 2) or (direction == Vector2i.DOWN and side == 3)
		if yard:
			_pave(paving, lot, Surface.GRAVEL)
			props[lot.get_center()] = "market_stall" if direction.x > 0 else "cargo_handcart"
			props[lot.position] = "cargo_crates" if direction.x > 0 else "firewood_stack"
			continue
		var width: int = mini(lot.size.x, 6 if workshop or market else 4 + side % 2)
		var height: int = mini(lot.size.y, 5 if workshop or side in [0, 3] else 4)
		var room := Rect2i(lot.position + Vector2i(0, 0 if south else lot.size.y - height), Vector2i(width, height))
		_house(structures, roofs, room, "wall" if workshop or market else "wood_wall",
			"workbench" if workshop else ("storage" if market else "bed"), south)
		var furnishing_tile := origin + Vector2i(left, frontage_y)
		if side % 2 == 0:
			_put(structures, furnishing_tile, "torch")
		else:
			props[furnishing_tile] = "sealed_barrels" if market else "rain_barrel"
	if fort_level >= 2:
		for normal: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if normal in connections:
				continue
			var gate: bool = normal == (direction.sign() if plan >= 2 else direction)
			for index: int in range(size):
				var edge: int = 0 if normal.x + normal.y < 0 else size - 1
				var tile := Vector2i(index, edge) if normal.y != 0 else Vector2i(edge, index)
				var axis: int = crossing.x if normal.y != 0 else crossing.y
				if not gate or index not in [axis - 1, axis]:
					_put(structures, origin + tile, "wall")
					if plan >= 3:
						var world_tile: Vector2i = origin + tile
						var tower: bool = index in [0, size - 1] or (gate and index in [axis - 2, axis + 1])
						ramparts[world_tile] = tower or ramparts.get(world_tile, false)
	return {"paving": paving, "props": props, "styles": styles, "ramparts": ramparts}


static func _build_civic_center(structures: Dictionary, roofs: Array[Rect2i], origin: Vector2i, size: int) -> Dictionary:
	var paving: Dictionary = {}
	var middle: int = size / 2
	var palace := Rect2i(origin, Vector2i(middle - 1, middle - 1))
	var hall := Rect2i(origin + Vector2i(middle + 1, 1), palace.size - Vector2i(0, 1))
	var forum := Rect2i(origin + Vector2i(0, middle - 1), Vector2i(size, size - middle + 1))
	_pave(paving, Rect2i(origin, Vector2i(size, size)), Surface.FLAGSTONE)
	_pave(paving, forum.grow(-1), Surface.FORUM)
	_house(structures, roofs, palace, "wall", "storage", false)
	_put(structures, palace.position + Vector2i(palace.size.x - 2, 1), "bed")
	_house(structures, roofs, hall, "wall", "workbench", false)
	_put(structures, origin + Vector2i(2, size - 2), "well")
	_put(structures, origin + Vector2i(size - 2, middle + 2), "forge")
	for tile: Vector2i in [Vector2i(0, middle), Vector2i(size - 1, middle), Vector2i(1, size - 1), Vector2i(size - 2, size - 1)]:
		_put(structures, origin + tile, "torch")
	return {
		"paving": paving,
		"lord_home": palace.position + Vector2i(palace.size.x - 2, 2),
		"forum_inlay": forum.get_center(),
		"styles": {palace.position: "lord_house", hall.position: "basilica"},
		"props": {
			origin + Vector2i(size - 3, size - 3): "market_stall",
			origin + Vector2i(size - 2, size - 2): "grain_sacks",
			origin + Vector2i(size - 2, middle + 1): "anvil_stump",
			origin + Vector2i(1, size - 3): "sealed_barrels",
		},
	}


static func _build_smithy_lot(structures: Dictionary, roofs: Array[Rect2i], paving: Dictionary, props: Dictionary, styles: Dictionary, lot: Rect2i, side: int, south: bool) -> void:
	_pave(paving, lot, Surface.COBBLE)
	var street_edge: int = lot.position.y - 1 if south else lot.end.y
	_pave(paving, Rect2i(lot.position.x, street_edge, lot.size.x, 1), Surface.COBBLE)
	if side in [1, 2]:
		props[lot.get_center()] = "masonry_blocks" if side == 1 else "cargo_handcart"
		props[lot.position + Vector2i(1, 1)] = "iron_stack"
		props[lot.end - Vector2i(2, 2)] = "charcoal_bucket"
		return
	var smithy := Rect2i(lot.position, Vector2i(lot.size.x, lot.size.y - 1))
	smithy.position.y += 1 if south else 0
	_house(structures, roofs, smithy, "wall", "forge", south)
	styles[smithy.position] = "smithy"
	var frontage: int = lot.position.y if south else lot.end.y - 1
	props[Vector2i(lot.position.x, frontage)] = "anvil_stump"
	props[Vector2i(lot.end.x - 1, frontage)] = "charcoal_bucket"


static func _build_roman_lot(structures: Dictionary, roofs: Array[Rect2i], paving: Dictionary, props: Dictionary, styles: Dictionary, lot: Rect2i, district: Vector2i, side: int, south: bool) -> void:
	var district_type: int = posmod(district.x + district.y * 3, 5)
	var front_y: int = lot.position.y - 1 if south else lot.end.y
	var frontage := Vector2i(lot.position.x, front_y)
	if side == 0 or side == 3:
		_put(structures, frontage, "torch")
	if side == 2 and district_type in [1, 3]:
		_pave(paving, lot, Surface.FLAGSTONE)
		props[lot.get_center()] = "market_stall" if district_type == 1 else "cargo_handcart"
		props[lot.position + Vector2i(1, 0)] = "sealed_barrels"
		props[lot.end - Vector2i(2, 2)] = "grain_sacks"
		return
	if district_type == 0 and side in [0, 3]:
		# Bath block: long hall with an open stone forecourt.
		var bath := Rect2i(lot.position, lot.size - Vector2i(0, 1))
		bath.position.y += 1 if south else 0
		_pave(paving, lot, Surface.FLAGSTONE)
		_house(structures, roofs, bath, "wall", "well", south)
		styles[bath.position] = "thermae"
		props[frontage + Vector2i(1, 0)] = "rain_barrel"
		return
	if district_type == 2 and lot.size.x >= 5 and lot.size.y >= 5:
		# Domus: the entrance leads through an uncovered atrium to the main rooms.
		var rear := Rect2i(lot.position, Vector2i(lot.size.x, 3))
		if south:
			rear.position.y = lot.end.y - rear.size.y
		_pave(paving, lot, Surface.FLAGSTONE)
		_house(structures, roofs, rear, "wall", "bed", south)
		styles[rear.position] = "villa"
		if lot.size.x >= 6 and lot.size.y >= 6:
			var wing := Rect2i(lot.position, Vector2i(3, 3))
			wing.position.y = lot.position.y if south else lot.end.y - wing.size.y
			_house(structures, roofs, wing, "wood_wall", "storage", south)
			styles[wing.position] = "villa"
		var patio_y: int = lot.position.y if south else lot.end.y - 1
		if lot.size.x < 6 or lot.size.y < 6:
			props[Vector2i(lot.position.x, patio_y)] = "seedling_pots"
		props[Vector2i(lot.end.x - 1, patio_y)] = "seedling_pots"
		return
	if district_type == 3 and lot.size.x >= 6:
		# Attached shopfronts share the same street and have separate doors.
		for x: int in [lot.position.x, lot.end.x - 3]:
			var shop := Rect2i(Vector2i(x, lot.position.y if south else lot.end.y - 4), Vector2i(3, 4))
			_house(structures, roofs, shop, "wall", "workbench", south)
			styles[shop.position] = "shop"
		return
	var size := Vector2i(mini(lot.size.x, 4 + (side + district_type) % 3), mini(lot.size.y, 4 + (side + district_type) % 2))
	var corner := Vector2i(lot.position.x if side % 2 == 0 else lot.end.x - size.x, lot.position.y if south else lot.end.y - size.y)
	var room := Rect2i(corner, size)
	var stone: bool = district_type != 4 or side == 0
	_house(structures, roofs, room, "wall" if stone else "wood_wall", "storage" if district_type == 1 else "bed", south)
	styles[corner] = "insula" if stone else "timber"
	if side == 1:
		props[frontage] = "apple_basket" if district_type == 1 else "firewood_stack"


static func _house(structures: Dictionary, roofs: Array[Rect2i], room: Rect2i, wall: String, fixture: String, north_door: bool) -> void:
	roofs.append(room)
	var door_y: int = 0 if north_door else room.size.y - 1
	var fixture_y: int = room.size.y - 2 if north_door else 1
	for x: int in range(room.size.x):
		for y: int in range(room.size.y):
			var id: String = "stone_floor" if wall == "wall" else "floor"
			if x == 0 or x == room.size.x - 1 or y == 0 or y == room.size.y - 1:
				id = "door" if y == door_y and x == room.size.x / 2 else wall
			elif y == fixture_y and x == 1:
				id = fixture
			_put(structures, room.position + Vector2i(x, y), id)


static func _pave(paving: Dictionary, area: Rect2i, surface: int) -> void:
	for x: int in range(area.position.x, area.end.x):
		for y: int in range(area.position.y, area.end.y):
			paving[Vector2i(x, y)] = surface


static func _put(structures: Dictionary, tile: Vector2i, id: String) -> void:
	structures[Config.vec2i_to_key(tile)] = id
