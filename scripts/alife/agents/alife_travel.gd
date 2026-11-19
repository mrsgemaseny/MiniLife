class_name AlifeTravel
extends RefCounted

# Dense prefix of a long route, in tiles.
const LEAD_DISTANCE: float = 200.0
const PATH_CACHE_LIMIT: int = 1024
const CONNECTED_WINDOW: int = 1600
# Off-screen agents walk at the pace of a materialized NPC (NPCBase: 0.42 x BASE_MOVE_SPEED),
# converted to tiles per game hour, so an agent keeps its speed when it enters or leaves the
# player's bubble. About 94 tiles per game hour.
const WALK_TILES_PER_HOUR: float = Config.BASE_MOVE_SPEED * 0.42 / float(Config.TILE_SIZE.x) * Config.SECONDS_PER_GAME_HOUR

var _grid: AlifeRouteGrid
var _seed: int = 0
var _generator_version: int
var _agent_routes: Dictionary = {}
var background_enabled: bool = false
var _worker_solver: AlifeTravel
var _task_id: int = -1
var _task_key: String = ""
var _task_result: Array[Vector2i] = []
var _requests: Dictionary = {}
var _completed: Dictionary = {}
# Cleared when the seed changes. Connected paths use a canonical direction.
var _path_cache: Dictionary = {}


func _init(generator_version: int = TerrainGenerator.GENERATOR_VERSION) -> void:
	_generator_version = generator_version


func request_path(seed_value: int, from_tile: Vector2i, to_tile: Vector2i, connected: bool = false,
		corridor: Array[Vector2i] = []) -> Array[Vector2i]:
	if not background_enabled:
		return path(seed_value, from_tile, to_tile, connected, corridor)
	poll()
	var key: String = _request_key(seed_value, from_tile, to_tile, connected, corridor)
	if _completed.has(key):
		return _completed[key].duplicate()
	if key != _task_key:
		_requests[key] = {"seed": seed_value, "from": from_tile, "to": to_tile, "connected": connected, "corridor": corridor.duplicate()}
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
			_worker_solver = AlifeTravel.new(_generator_version)
		_task_id = WorkerThreadPool.add_task(func() -> void:
			_task_result = _worker_solver.path(int(request["seed"]), request["from"], request["to"], request["connected"], request["corridor"])
		, false, "A-Life route")

func is_path_pending(seed_value: int, from_tile: Vector2i, to_tile: Vector2i, connected: bool = false,
		corridor: Array[Vector2i] = []) -> bool:
	var key: String = _request_key(seed_value, from_tile, to_tile, connected, corridor)
	return key == _task_key or _requests.has(key)

func _request_key(seed_value: int, from_tile: Vector2i, to_tile: Vector2i, connected: bool, corridor: Array[Vector2i]) -> String:
	return "%d:%s:%s:%d:%s" % [seed_value, from_tile, to_tile, int(connected), str(corridor)]

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
	_grid.setup(seed_value, _generator_version)

# Terrain and camp placement are deterministic, so the same settlement route can be reused.
func path(seed_value: int, from_tile: Vector2i, to_tile: Vector2i, connected: bool = false,
		corridor: Array[Vector2i] = []) -> Array[Vector2i]:
	_prepare(seed_value)
	var dense: bool = connected or not corridor.is_empty()
	var reverse: bool = dense and to_tile < from_tile
	var start: Vector2i = to_tile if reverse else from_tile
	var finish: Vector2i = from_tile if reverse else to_tile
	var cells: Array[Vector2i] = corridor.duplicate()
	if reverse:
		cells.reverse()
	var endpoints := Vector4i(start.x, start.y, finish.x, finish.y)
	var key: Variant = [endpoints, cells] if dense else endpoints
	if not _path_cache.has(key):
		if _path_cache.size() >= PATH_CACHE_LIMIT:
			_path_cache.erase(_path_cache.keys()[0])
		_path_cache[key] = _solve(start, finish, dense, cells)
	var result: Array[Vector2i] = (_path_cache[key] as Array[Vector2i]).duplicate()
	if reverse:
		result.reverse()
	return result


func _solve(from_tile: Vector2i, to_tile: Vector2i, connected: bool, corridor: Array[Vector2i]) -> Array[Vector2i]:
	_grid.avoid_bandit_camps = connected
	_grid.restrict_to([])
	if not corridor.is_empty():
		return _trade_path(from_tile, to_tile, corridor)
	return _solve_leg(from_tile, to_tile, connected)


func _trade_path(from_tile: Vector2i, to_tile: Vector2i, corridor: Array[Vector2i]) -> Array[Vector2i]:
	var first: int = corridor.find(GlobalLandscapeMap.cell_for_tile(from_tile))
	var last: int = corridor.find(GlobalLandscapeMap.cell_for_tile(to_tile))
	if first < 0 or last < first:
		return []
	return _trade_leg(from_tile, to_tile, corridor, first, last, {})


func _trade_leg(from_tile: Vector2i, to_tile: Vector2i, corridor: Array[Vector2i], index: int, last: int,
		dead_ends: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	if dead_ends.has(from_tile):
		return []
	var cell: Vector2i = corridor[index]
	if index == last:
		_grid.restrict_to([cell])
		var finish: Array[Vector2i] = _solve_leg(from_tile, to_tile, true)
		if finish.is_empty():
			dead_ends[from_tile] = true
		return finish
	var neighbor: Vector2i = corridor[index + 1]
	var step: Vector2i = neighbor - cell
	if absi(step.x) + absi(step.y) != 1:
		return []
	# A dry crossing can lead into an isolated part of the next cell.
	for exit: Vector2i in _grid.road_exits(cell, neighbor):
		_grid.restrict_to([cell])
		var leg: Array[Vector2i] = _solve_leg(from_tile, exit, true)
		if leg.is_empty():
			continue
		var onward: Array[Vector2i] = _trade_leg(exit + step, to_tile, corridor, index + 1, last, dead_ends)
		if not onward.is_empty():
			leg.append_array(onward)
			return leg
	dead_ends[from_tile] = true
	return []


func _solve_leg(from_tile: Vector2i, to_tile: Vector2i, connected: bool) -> Array[Vector2i]:
	if _grid.blocked(from_tile) or _grid.blocked(to_tile):
		return []
	if not _grid.prepare_window(from_tile, to_tile, CONNECTED_WINDOW if connected else AlifeRouteGrid.MAX_WINDOW):
		return [] if connected else _long_path(from_tile, to_tile)
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

func assign_path(seed_value: int, agent: GlobalAgent, route: Array[Vector2i]) -> void:
	_prepare(seed_value)
	_agent_routes[agent.agent_id] = {"destination": agent.destination_tile, "position": agent.tile, "route": route}

func steering_target(seed_value: int, agent: GlobalAgent, corridor: Array[Vector2i] = []) -> Vector2i:
	var cached: Dictionary = _agent_routes.get(agent.agent_id, {})
	if cached.get("destination") != agent.destination_tile or ((cached["route"] as Array).size() <= 1 and agent.tile != agent.destination_tile):
		var replacement: Array[Vector2i] = request_path(seed_value, agent.tile, agent.destination_tile, true, corridor)
		if replacement.is_empty():
			return agent.tile
		assign_path(seed_value, agent, replacement)
		cached = _agent_routes[agent.agent_id]
	var route: Array[Vector2i] = cached["route"]
	if route.size() <= 1:
		return agent.destination_tile
	var closest: int = 0
	var distance: float = INF
	for index: int in range(mini(12, route.size())):
		var candidate: float = Vector2(agent.tile).distance_squared_to(Vector2(route[index]))
		if candidate < distance:
			distance = candidate
			closest = index
	var target_index: int = mini(closest + 3, route.size() - 1)
	if cached["position"] != agent.tile:
		var remaining: Array[Vector2i] = [agent.tile]
		remaining.append_array(route.slice(closest + int(distance == 0.0)))
		assign_path(_seed, agent, remaining)
	return route[target_index]

func discard_saved_trade_paths_through_camps(ids: Array) -> void:
	if _grid == null:
		return
	for id: String in ids:
		var cached: Dictionary = _agent_routes.get(id, {})
		var route: Array = cached.get("route", [])
		if route.is_empty():
			continue
		var departure_area: Rect2i = _grid.bandit_camp_area(route[0])
		var first_exit: int = -1
		for index: int in range(route.size()):
			var point: Vector2i = route[index]
			if departure_area.has_point(point):
				continue
			if departure_area.has_area():
				first_exit = index
			departure_area = Rect2i()
			if _grid.bandit_camp_area(point).has_point(point):
				# Finish leaving the camp if this convoy was already inside it at save time.
				if first_exit > 0:
					cached["route"] = route.slice(0, first_exit + 1)
				else:
					_agent_routes.erase(id)
				break

func remaining_steps(agent: GlobalAgent) -> int:
	var cached: Dictionary = _agent_routes.get(agent.agent_id, {})
	if cached.get("destination") != agent.destination_tile:
		return -1
	return maxi(0, (cached["route"] as Array).size() - 1)

func route_ahead(agent: GlobalAgent, limit: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cached: Dictionary = _agent_routes.get(agent.agent_id, {})
	if cached.get("destination") == agent.destination_tile and cached.get("position") == agent.tile:
		result.assign((cached["route"] as Array).slice(0, limit))
	return result

func advance(seed_value: int, agent: GlobalAgent, hours: float, speed: float = WALK_TILES_PER_HOUR, connected: bool = false,
		corridor: Array[Vector2i] = []) -> bool:
	if agent.tile == agent.destination_tile:
		return true
	_prepare(seed_value)
	var key: String = agent.agent_id
	var cached: Dictionary = _agent_routes.get(key, {})
	var route: Array[Vector2i] = []
	if cached.get("destination") == agent.destination_tile and cached.get("position") == agent.tile \
			and (cached["route"] as Array).size() > 1:
		route.assign(cached.get("route", []))
	else:
		route = request_path(seed_value, agent.tile, agent.destination_tile, connected, corridor)
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
