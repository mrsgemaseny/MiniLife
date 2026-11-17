class_name AlifeTravel
extends RefCounted

# Dense prefix of a long route, in tiles.
const LEAD_DISTANCE: float = 200.0
const PATH_CACHE_LIMIT: int = 1024
# Off-screen agents walk at the pace of a materialized NPC (NPCBase: 0.42 x BASE_MOVE_SPEED),
# converted to tiles per game hour, so an agent keeps its speed when it enters or leaves the
# player's bubble. About 94 tiles per game hour.
const WALK_TILES_PER_HOUR: float = Config.BASE_MOVE_SPEED * 0.42 / float(Config.TILE_SIZE.x) * Config.SECONDS_PER_GAME_HOUR

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
# Vector4i(from, to) -> Array[Vector2i]; cleared when the seed changes.
var _path_cache: Dictionary = {}

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
	_path_cache.clear()
	_grid = AlifeRouteGrid.new()
	_grid.setup(seed_value)

# Routes depend only on terrain, which is a pure function of the seed, so solved paths are
# reused. Caravans re-request the same city-to-city route on every dispatch attempt.
func path(seed_value: int, from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	_prepare(seed_value)
	var key := Vector4i(from_tile.x, from_tile.y, to_tile.x, to_tile.y)
	if _path_cache.has(key):
		return (_path_cache[key] as Array[Vector2i]).duplicate()
	var result: Array[Vector2i] = _solve(from_tile, to_tile)
	if _path_cache.size() >= PATH_CACHE_LIMIT:
		_path_cache.erase(_path_cache.keys()[0])
	_path_cache[key] = result.duplicate()
	return result


func _solve(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	if _grid.blocked(from_tile) or _grid.blocked(to_tile):
		return []
	if not _grid.prepare_window(from_tile, to_tile):
		return _long_path(from_tile, to_tile)
	var direct: Array[Vector2i] = _grid.line(from_tile, to_tile)
	if not direct.is_empty():
		return direct
	return _local_path(from_tile, to_tile)


# Long trips: a dense first leg (so ambushes and escorts see real tiles near the agent),
# then sparse waypoints through dry border crossings. advance() walks it by distance;
# the materializer snaps an agent to walkable ground when it enters the player's bubble.
func _long_path(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = _grid.macro_path(GlobalLandscapeMap.cell_for_tile(from_tile), GlobalLandscapeMap.cell_for_tile(to_tile))
	if cells.is_empty():
		return []
	var waypoints: Array[Vector2i] = []
	for i: int in range(cells.size() - 1):
		var gate: Vector2i = _grid.crossing(cells[i], cells[i + 1])
		if gate.x < 0:
			return []
		waypoints.append(gate)
	waypoints.append(to_tile)
	var first: Vector2i = waypoints[0]
	var lead: Vector2 = Vector2(first - from_tile)
	var reach: float = minf(LEAD_DISTANCE, lead.length())
	var result: Array[Vector2i] = [from_tile]
	var lead_target: Vector2i = from_tile + Vector2i((lead.normalized() * reach).round())
	for radius: int in range(6):
		var candidate: Vector2i = lead_target + Vector2i(radius * 2, 0)
		if not _grid.blocked(candidate) and _grid.prepare_window(from_tile, candidate):
			var leg: Array[Vector2i] = _grid.line(from_tile, candidate)
			if leg.is_empty():
				leg = _local_path(from_tile, candidate)
			if not leg.is_empty():
				result = leg
				break
	for point: Vector2i in waypoints:
		if point != result.back():
			result.append(point)
	return result


func _local_path(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
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

func advance(seed_value: int, agent: GlobalAgent, hours: float, speed: float = WALK_TILES_PER_HOUR) -> bool:
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
	# Walk the polyline by distance. Adjacent entries cost one step (as on the dense grid),
	# sparse waypoints cost their real length and may be reached partially.
	var budget: float = maxf(1.0, hours * speed)
	var position := Vector2(route[0])
	var index: int = 0
	while index < route.size() - 1 and budget > 0.0:
		var next := Vector2(route[index + 1])
		var length: float = position.distance_to(next)
		var cost: float = 1.0 if length <= 1.5 else length
		if cost <= budget:
			budget -= cost
			position = next
			index += 1
		elif length > 1.5:
			position = position.move_toward(next, budget)
			budget = 0.0
		else:
			break
	agent.tile = Vector2i(position.round())
	var remaining: Array[Vector2i] = [agent.tile]
	for i: int in range(index + 1, route.size()):
		if route[i] != agent.tile:
			remaining.append(route[i])
	_agent_routes[key] = {"destination": agent.destination_tile, "position": agent.tile, "route": remaining}
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
		if not is_finite(number) or number != floorf(number) or number < 0.0 or number >= float(maxi(WorldLayout.size_tiles().x, WorldLayout.size_tiles().y)):
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
