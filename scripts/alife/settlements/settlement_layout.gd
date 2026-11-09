class_name SettlementLayout
extends RefCounted

const Streets = preload("res://scripts/alife/settlements/city_street_plan.gd")

static func describe(settlement: AlifeSettlement) -> Dictionary:
	var half: int = settlement.footprint / 2
	var origin: Vector2i = settlement.tile - Vector2i(half, half)
	var size: int = settlement.footprint
	if settlement.street_plan > 0:
		# The seed builder validates a one-tile border around the core.
		origin -= Vector2i.ONE
		size += 2
	var structures: Dictionary = {}
	var roofs: Array[Rect2i] = []
	var streets: Dictionary = {}
	if settlement.status == AlifeSettlement.Status.RUINS:
		_build_ruins(structures, origin, size)
	elif settlement.status != AlifeSettlement.Status.RAZED:
		if settlement.street_plan == 0:
			_build_occupied(structures, roofs, settlement, origin)
		else:
			streets = Streets.build_core(structures, roofs, origin, size, settlement.street_plan)
	return {
		"settlement_id": settlement.settlement_id, "poi_id": "merchant_outpost", "name": settlement.name,
		"tile_pos": settlement.tile, "is_ruin": false,
		"origin": origin, "size": size,
		"structures": structures, "roofs": roofs, "streets": streets
	}


static func describe_district(settlement: AlifeSettlement, chunk: Vector2i, connections: Array[Vector2i]) -> Dictionary:
	var origin: Vector2i = Config.chunk_origin(chunk)
	var center_chunk: Vector2i = Config.tile_to_chunk(settlement.tile)
	var direction: Vector2i = chunk - center_chunk
	var crossing: Vector2i = settlement.tile - Config.chunk_origin(center_chunk)
	var structures: Dictionary = {}
	var roofs: Array[Rect2i] = []
	var streets: Dictionary = {}
	var wall: String = "wall" if settlement.fort_level >= 2 else "wood_wall"
	if settlement.status == AlifeSettlement.Status.RUINS:
		_build_ruins(structures, origin + Vector2i(2, 2), 12)
	elif settlement.status != AlifeSettlement.Status.RAZED and settlement.street_plan > 0:
		streets = Streets.build_district(structures, roofs, origin, crossing, direction, connections, settlement.fort_level, settlement.street_plan)
	elif settlement.status != AlifeSettlement.Status.RAZED:
		for offset: int in range(Config.CHUNK_SIZE):
			_put(structures, origin + Vector2i(crossing.x, offset), "stone_floor")
			_put(structures, origin + Vector2i(offset, crossing.y), "stone_floor")
		# Use separate blocks on opposite sides of the main street.
		var north: int = 1
		var south: int = Config.CHUNK_SIZE - 5
		var west: int = 1
		var east: int = Config.CHUNK_SIZE - 6
		if direction == Vector2i.UP or (direction.x != 0 and direction.y != 0):
			_build_district_room(structures, roofs, origin + Vector2i(west, north), wall, "bed", false)
			_build_district_room(structures, roofs, origin + Vector2i(east, north), wall, "bed", false)
			_build_district_room(structures, roofs, origin + Vector2i(west, south), wall, "bed", true)
			_build_district_room(structures, roofs, origin + Vector2i(east, south), wall, "bed", true)
		elif direction == Vector2i.LEFT:
			_build_district_room(structures, roofs, origin + Vector2i(west, north), wall, "workbench", false)
			_build_district_room(structures, roofs, origin + Vector2i(east, north), wall, "storage", false)
			_build_district_room(structures, roofs, origin + Vector2i(west, south), wall, "bed", true)
			_build_district_room(structures, roofs, origin + Vector2i(east, south), wall, "workbench", true)
		elif direction == Vector2i.DOWN:
			_build_district_room(structures, roofs, origin + Vector2i(west, north), wall, "bed", false)
			_build_district_room(structures, roofs, origin + Vector2i(east, north), wall, "bed", false)
			_build_district_room(structures, roofs, origin + Vector2i(west, south), wall, "storage", true)
			_build_district_room(structures, roofs, origin + Vector2i(east, south), wall, "workbench", true)
		else:
			for x: int in range(crossing.x - 3, crossing.x + 4):
				for y: int in range(crossing.y - 3, crossing.y + 4):
					_put(structures, origin + Vector2i(x, y), "stone_floor")
			_build_district_room(structures, roofs, origin + Vector2i(west, north), wall, "storage", false)
			_build_district_room(structures, roofs, origin + Vector2i(east, south), wall, "workbench", true)
			_put(structures, origin + crossing + Vector2i(-2, -2), "storage")
			_put(structures, origin + crossing + Vector2i(2, 2), "workbench")
			_put(structures, origin + crossing + Vector2i(2, -2), "campfire")
		if settlement.fort_level >= 2:
			_build_district_rampart(structures, origin, crossing, direction, connections)
	return {
		"settlement_id": settlement.settlement_id, "poi_id": "merchant_outpost", "district": true,
		"settlement_tile": settlement.tile, "name": settlement.name,
		"tile_pos": origin + crossing, "origin": origin, "size": Config.CHUNK_SIZE,
		"structures": structures, "roofs": roofs, "streets": streets,
	}


static func _build_district_rampart(structures: Dictionary, origin: Vector2i, crossing: Vector2i, outward: Vector2i, connections: Array[Vector2i]) -> void:
	var edge: int = Config.CHUNK_SIZE - 1
	for normal: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if normal in connections:
			continue
		for offset: int in range(Config.CHUNK_SIZE):
			var tile: Vector2i = Vector2i(offset, 0 if normal.y < 0 else edge)
			if normal.x != 0:
				tile = Vector2i(0 if normal.x < 0 else edge, offset)
			if normal == outward and (tile.x == crossing.x or tile.y == crossing.y):
				continue
			_put(structures, origin + tile, "wall")


static func _build_occupied(structures: Dictionary, roofs: Array[Rect2i], settlement: AlifeSettlement, origin: Vector2i) -> void:
	var size: int = settlement.footprint
	var wall: String = "wall" if settlement.fort_level >= 2 else "wood_wall"
	var paving: String = "stone_floor" if settlement.fort_level > 0 else "floor"
	for y: int in range(size):
		_put(structures, origin + Vector2i(size / 2, y), paving)
	for x: int in range(size):
		_put(structures, origin + Vector2i(x, size / 2), paving)

	# Two homes face the central street. Shops face the cross street from the south.
	_build_room(structures, roofs, origin, wall, "bed", Vector2i(1, 3))
	_build_room(structures, roofs, origin + Vector2i(size - 3, 0), wall, "bed", Vector2i(1, 3))
	_build_room(structures, roofs, origin + Vector2i(0, size - 4), wall, "workbench", Vector2i(2, 2))
	_build_room(structures, roofs, origin + Vector2i(size - 3, size - 4), wall, "storage", Vector2i(0, 2))
	_put(structures, settlement.tile + Vector2i(-1, 0), "campfire")
	if settlement.fort_level >= 2:
		for y: int in range(3, size - 3):
			if y == size / 2:
				continue
			_put(structures, origin + Vector2i(0, y), wall)
			_put(structures, origin + Vector2i(size - 1, y), wall)


static func _build_room(structures: Dictionary, roofs: Array[Rect2i], corner: Vector2i, wall: String, fixture: String, entrance: Vector2i) -> void:
	roofs.append(Rect2i(corner, Vector2i(3, 4)))
	for x: int in range(3):
		for y: int in range(4):
			var offset := Vector2i(x, y)
			var id: String = wall
			if offset == entrance:
				id = "door"
			elif offset == Vector2i.ONE:
				id = fixture
			elif offset == Vector2i(1, 2):
				id = "floor"
			_put(structures, corner + offset, id)


static func _build_district_room(structures: Dictionary, roofs: Array[Rect2i], corner: Vector2i, wall: String, fixture: String, north_entrance: bool) -> void:
	roofs.append(Rect2i(corner, Vector2i(5, 4)))
	var entrance_y: int = 0 if north_entrance else 3
	var furniture_y: int = 2 if north_entrance else 1
	for x: int in range(5):
		for y: int in range(4):
			var id: String = "floor"
			if x == 0 or x == 4 or y == 0 or y == 3:
				id = "door" if x == 2 and y == entrance_y else wall
			elif y == furniture_y and (x == 1 or x == 3):
				id = fixture
			_put(structures, corner + Vector2i(x, y), id)


static func _build_ruins(structures: Dictionary, origin: Vector2i, size: int) -> void:
	for corner: Vector2i in [Vector2i.ZERO, Vector2i(size - 3, 0), Vector2i(0, size - 3), Vector2i(size - 3, size - 3)]:
		_put(structures, origin + corner, "wall")
		_put(structures, origin + corner + Vector2i.RIGHT, "wall")
		_put(structures, origin + corner + Vector2i.DOWN, "wall")


static func _put(structures: Dictionary, tile: Vector2i, structure_id: String) -> void:
	structures[Config.vec2i_to_key(tile)] = structure_id
