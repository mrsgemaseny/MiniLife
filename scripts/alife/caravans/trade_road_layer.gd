class_name TradeRoadLayer
extends RefCounted

var _roads_by_cell: Dictionary[Vector2i, Array] = {}
var _queued: Dictionary[String, bool] = {}
var _pending: Dictionary[String, Dictionary] = {}


func reset(world: AlifeWorldContext) -> void:
	_roads_by_cell.clear()
	_queued.clear()
	_pending.clear()
	for key: String in WorldData.trade_route_keys():
		var endpoints: PackedStringArray = key.split("->")
		if endpoints[0] >= endpoints[1]:
			continue
		var start: AlifeSettlement = world.settlements.find(endpoints[0]) as AlifeSettlement
		var finish: AlifeSettlement = world.settlements.find(endpoints[1]) as AlifeSettlement
		if start == null or finish == null:
			continue
		var corridor: Array[Vector2i] = WorldData.trade_corridor(start.settlement_id, finish.settlement_id)
		var road: Dictionary = {"key": key, "from": CaravanRouteManager.market_tile(start),
			"to": CaravanRouteManager.market_tile(finish), "corridor": corridor}
		for cell: Vector2i in corridor:
			if not _roads_by_cell.has(cell):
				_roads_by_cell[cell] = []
			_roads_by_cell[cell].append(road)


func queue_chunk(chunk: Vector2i) -> void:
	var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(Config.chunk_origin(chunk) + Vector2i.ONE * (Config.CHUNK_SIZE / 2))
	for road: Dictionary in _roads_by_cell.get(cell, []):
		var key: String = road["key"]
		if not _queued.has(key):
			_pending[key] = road
			_queued[key] = true


func update(world: AlifeWorldContext) -> void:
	for key: String in _pending.keys():
		var road: Dictionary = _pending[key]
		var start: Vector2i = road["from"]
		var finish: Vector2i = road["to"]
		var corridor: Array[Vector2i] = road["corridor"]
		var path: Array[Vector2i] = world.travel.request_path(world.world_seed, start, finish, true, corridor)
		if path.is_empty() and world.travel.is_path_pending(world.world_seed, start, finish, true, corridor):
			continue
		_pending.erase(key)
		if not path.is_empty():
			SignalBus.trade_road_ready.emit(_surface(path))


func _surface(path: Array[Vector2i]) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [path[0]]
	for index: int in range(1, path.size()):
		var previous: Vector2i = path[index - 1]
		var current: Vector2i = path[index]
		if previous.x != current.x and previous.y != current.y:
			# The router already checks both side tiles of every diagonal step.
			tiles.append(Vector2i(current.x, previous.y))
		tiles.append(current)
	return tiles
