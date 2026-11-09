class_name AlifeTravel
extends RefCounted

var _grid: AlifeRouteGrid
var _seed: int = 0
var _agent_routes: Dictionary = {}
var background_enabled: bool = false
var _worker_solver: AlifeTravel
var _task_id: int = -1
var _task_key: String = ""
var _task_result: Array[Vector2i] = []
var _requests: Dictionary = {}
var _completed: Dictionary = {}

func request_path(seed_value: int, from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	if not background_enabled:
		return path(seed_value, from_tile, to_tile)
	poll()
	var key: String = "%d:%s:%s" % [seed_value, from_tile, to_tile]
	if _completed.has(key):
		return _completed[key].duplicate()
	if key != _task_key:
		_requests[key] = {"seed": seed_value, "from": from_tile, "to": to_tile}
	poll()
	return []

func poll() -> void:
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		if _completed.size() >= 128:
			_completed.erase(_completed.keys()[0])
		_completed[_task_key] = _task_result
		_task_key = ""
		_task_id = -1
	if _task_id < 0 and not _requests.is_empty():
		_task_key = str(_requests.keys()[0])
		var request: Dictionary = _requests[_task_key]
		_requests.erase(_task_key)
		if _worker_solver == null:
			_worker_solver = AlifeTravel.new()
		_task_id = WorkerThreadPool.add_task(func() -> void:
			_task_result = _worker_solver.path(int(request["seed"]), request["from"], request["to"])
		, false, "A-Life route")

func is_path_pending(seed_value: int, from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var key: String = "%d:%s:%s" % [seed_value, from_tile, to_tile]
	return key == _task_key or _requests.has(key)

func shutdown() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	_requests.clear()
	_task_key = ""

func _prepare(seed_value: int) -> void:
	if _grid != null and _seed == seed_value:
		if _grid._blocked.size() > 131072:
			_grid._blocked.clear()
		return
	_seed = seed_value
	_agent_routes.clear()
	_grid = AlifeRouteGrid.new()
	_grid.setup(seed_value)

func path(seed_value: int, from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	_prepare(seed_value)
	if _grid.blocked(from_tile) or _grid.blocked(to_tile):
		return []
	var direct: Array[Vector2i] = _grid.line(from_tile, to_tile)
	if not direct.is_empty():
		return direct
	var start: Vector2i = _grid.endpoint(from_tile)
	var finish: Vector2i = _grid.endpoint(to_tile)
	if start.x < 0 or finish.x < 0:
		return []
	var cells: Array[Vector2i] = _grid.cell_path(start, finish)
	if cells.is_empty():
		return []
	var result: Array[Vector2i] = [from_tile]
	for cell: Vector2i in cells:
		var segment: Array[Vector2i] = _grid.line(result.back(), _grid.tile_for(cell))
		if segment.is_empty():
			return []
		segment.remove_at(0)
		result.append_array(segment)
	var last: Array[Vector2i] = _grid.line(result.back(), to_tile)
	if last.is_empty():
		return []
	last.remove_at(0)
	result.append_array(last)
	return result

func advance(seed_value: int, agent: GlobalAgent, hours: float, speed: float = 8.0) -> bool:
	if agent.tile == agent.destination_tile:
		return true
	_prepare(seed_value)
	var key: String = agent.agent_id
	var cached: Dictionary = _agent_routes.get(key, {})
	var route: Array[Vector2i] = []
	if cached.get("destination") == agent.destination_tile and cached.get("position") == agent.tile:
		route.assign(cached.get("route", []))
	else:
		route = request_path(seed_value, agent.tile, agent.destination_tile)
	if route.is_empty():
		return false
	var step: int = mini(route.size() - 1, maxi(1, int(hours * speed)))
	agent.tile = route[step]
	_agent_routes[key] = {"destination": agent.destination_tile, "position": agent.tile, "route": route.slice(step)}
	agent.world_position.clear()
	return agent.tile == agent.destination_tile

func saved_routes() -> Dictionary:
	var result: Dictionary = {}
	for id: String in _agent_routes:
		var cached: Dictionary = _agent_routes[id]
		var points: Array = []
		for tile: Vector2i in cached["route"]:
			points.append([tile.x, tile.y])
		var destination: Vector2i = cached["destination"]
		var position: Vector2i = cached["position"]
		result[id] = {"destination": [destination.x, destination.y], "position": [position.x, position.y], "route": points}
	return result

static func valid_saved_routes(data: Dictionary) -> bool:
	for id: Variant in data:
		var cached: Variant = data[id]
		if not id is String or not cached is Dictionary or not cached.get("route") is Array:
			return false
		if not _valid_tile_pair(cached.get("destination")) or not _valid_tile_pair(cached.get("position")):
			return false
		for point: Variant in cached["route"]:
			if not _valid_tile_pair(point):
				return false
	return true

static func _valid_tile_pair(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for coordinate: Variant in value:
		if not (coordinate is int or coordinate is float):
			return false
		var number: float = float(coordinate)
		if not is_finite(number) or number != floorf(number) or number < 0.0 or number >= Config.WORLD_SIZE_TILES:
			return false
	return true

func restore_routes(seed_value: int, data: Dictionary) -> void:
	if data.is_empty():
		return
	_prepare(seed_value)
	for id: String in data:
		var cached: Dictionary = data[id]
		var points: Array[Vector2i] = []
		for point: Array in cached["route"]:
			points.append(Vector2i(int(point[0]), int(point[1])))
		_agent_routes[id] = {"destination": Vector2i(int(cached["destination"][0]), int(cached["destination"][1])),
			"position": Vector2i(int(cached["position"][0]), int(cached["position"][1])), "route": points}
