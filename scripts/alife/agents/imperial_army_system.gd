class_name ImperialArmySystem
extends RefCounted

const SAVE_KEY: String = "imperial_armies"
const COMMANDER: String = "imperial_commander"
const SOLDIER: String = "imperial_soldier"
const COLUMN_SIZE: int = 5
const INITIAL_MORALE: float = 0.85
const CLEARANCE: int = 7

var _routes: Dictionary[String, Array] = {}
var _anchors: Dictionary[Vector2i, Array] = {}
var _march_paths: AlifeTravel


func initialize(world: AlifeWorldContext, hour: float) -> void:
	_march_paths = AlifeTravel.new(world.generator_version)
	var authored: Dictionary[String, Dictionary] = WorldData.imperial_armies()
	var state: Dictionary = world.narrative.get(SAVE_KEY, {})
	for id: String in authored:
		var definition: Dictionary = authored[id]
		if definition["status"] != "roaming" or not WorldData.landscape().is_land(definition["position"]):
			continue
		var cells: Array[Vector2i] = [definition["position"]]
		var waypoints: Array = definition["route"]
		# WorldStudio draws origin -> waypoints -> current position. Start at the
		# current position, then retrace and patrol that corridor in both directions.
		for index: int in range(waypoints.size() - 1, -1, -1):
			if cells.back() != waypoints[index]:
				cells.append(waypoints[index])
		var origin: Vector2i = definition["origin"]
		if origin.x >= 0 and cells.back() != origin:
			cells.append(origin)
		_routes[id] = cells
		if state.has(id):
			var saved: Dictionary = state[id]
			if int(saved["waypoint"]) >= cells.size():
				saved["waypoint"] = maxi(0, cells.size() - 1)
				_set_destination(world, id, cells[int(saved["waypoint"])])
			continue
		var start: Array = _anchors_for(world, cells[0])
		if start.size() != COLUMN_SIZE:
			continue
		var waypoint: int = mini(1, cells.size() - 1)
		for slot: int in range(COLUMN_SIZE):
			var unit: GlobalAgent = GlobalAgent.new()
			unit.agent_id = unit_id(id, slot)
			unit.role = COMMANDER if slot == 0 else SOLDIER
			unit.definition_id = "imperial_column_member"
			unit.display_name = "Имперский командир" if slot == 0 else "Имперский солдат"
			unit.tile = start[slot]
			unit.home_tile = unit.tile
			unit.destination_tile = unit.tile
			unit.morale = INITIAL_MORALE
			unit.max_health = 150.0 if slot == 0 else 120.0
			unit.health = unit.max_health
			unit.equipment_tier = 3
			world.agents.register(unit)
		state[id] = {"waypoint": waypoint, "direction": 1, "hour": hour}
		_set_destination(world, id, cells[waypoint])
	if not state.is_empty():
		world.narrative[SAVE_KEY] = state


func update(world: AlifeWorldContext, player_tile: Vector2i, hour: float) -> void:
	if _march_paths == null:
		return
	# Military path requests must not make scheduled trade departures wait.
	_march_paths.background_enabled = world.travel.background_enabled
	_march_paths.poll()
	var state: Dictionary = world.narrative.get(SAVE_KEY, {})
	for id: String in _routes:
		if not state.has(id):
			continue
		var column: Array[GlobalAgent] = living_units(world, id)
		if column.is_empty():
			continue
		var row: Dictionary = state[id]
		var delta_hours: float = hour - float(row["hour"])
		if delta_hours < 0.0:
			row["hour"] = hour
			continue
		var commander: GlobalAgent = world.agents.find(unit_id(id, 0)) as GlobalAgent
		var speed: float = speed_multiplier(commander)
		var interval: float = 1.0 / (AlifeTravel.WALK_TILES_PER_HOUR * speed)
		var tier: int = SimulationBubble.compute_lod_tier(player_tile, column[0].tile)
		if tier != SimulationBubble.Tier.FULL:
			interval = SimulationBubble.get_tick_interval(tier) / Config.SECONDS_PER_GAME_HOUR
		if delta_hours + 0.000001 < interval:
			continue
		var elapsed: float = minf(delta_hours, Config.LOD_FAR_INTERVAL / Config.SECONDS_PER_GAME_HOUR)
		row["hour"] = minf(hour, float(row["hour"]) + elapsed)
		var arrived: bool = true
		for unit: GlobalAgent in column:
			if unit != commander:
				unit.morale = (0.35 + 0.6 * command_strength(commander)) * (0.7 + 0.3 * unit.health / unit.max_health)
			if unit.tile != unit.destination_tile:
				var is_local: bool = world.agents.materialized.has(unit.agent_id)
				if not world.travel.has_march_path(unit, not is_local):
					var cells: Array[Vector2i] = corridor(world, unit)
					if not cells.is_empty():
						var route: Array[Vector2i] = _march_paths.request_path(world.world_seed, unit.tile, unit.destination_tile, true, cells)
						if not route.is_empty():
							world.travel.assign_path(world.world_seed, unit, route)
				if not is_local and world.travel.has_march_path(unit, true):
					world.travel.advance(world.world_seed, unit, elapsed, AlifeTravel.WALK_TILES_PER_HOUR * speed, true)
				arrived = arrived and unit.tile == unit.destination_tile
		var ordered: Array = _routes[id]
		if arrived and ordered.size() > 1:
			var direction: int = int(row["direction"])
			var waypoint: int = int(row["waypoint"]) + direction
			if waypoint < 0 or waypoint >= ordered.size():
				direction = -direction
				waypoint += direction * 2
			if _set_destination(world, id, ordered[waypoint]):
				row["direction"] = direction
				row["waypoint"] = waypoint


func shutdown() -> void:
	if _march_paths != null:
		_march_paths.shutdown()


func _set_destination(world: AlifeWorldContext, id: String, cell: Vector2i) -> bool:
	var anchors: Array = _anchors_for(world, cell)
	if anchors.size() != COLUMN_SIZE:
		return false
	for slot: int in range(COLUMN_SIZE):
		var unit: GlobalAgent = world.agents.find(unit_id(id, slot)) as GlobalAgent
		if unit != null and unit.alive:
			unit.destination_tile = anchors[slot]
	return true


func _anchors_for(world: AlifeWorldContext, cell: Vector2i) -> Array:
	if not _anchors.has(cell):
		_anchors[cell] = world.travel.march_anchors(world.world_seed, cell, COLUMN_SIZE)
	return _anchors[cell]


func active_unit_ids(world: AlifeWorldContext) -> Array[String]:
	var ids: Array[String] = []
	var state: Dictionary = world.narrative.get(SAVE_KEY, {})
	for id: String in _routes:
		if state.has(id):
			for slot: int in range(COLUMN_SIZE):
				ids.append(unit_id(id, slot))
	return ids


func active_army_ids() -> Array[String]:
	return _routes.keys()


func avoidance_zones(world: AlifeWorldContext) -> Array[Rect2i]:
	var zones: Array[Rect2i] = []
	for id: String in _routes:
		for unit: GlobalAgent in living_units(world, id):
			zones.append(Rect2i(unit.tile, Vector2i.ONE).grow(CLEARANCE))
	return zones


static func living_units(world: AlifeWorldContext, id: String) -> Array[GlobalAgent]:
	var result: Array[GlobalAgent] = []
	for slot: int in range(COLUMN_SIZE):
		var unit: GlobalAgent = world.agents.find(unit_id(id, slot)) as GlobalAgent
		if unit != null and unit.alive:
			result.append(unit)
	return result


static func unit_id(id: String, slot: int) -> String:
	return "%s/unit/%d" % [id, slot]


static func is_member(unit: GlobalAgent) -> bool:
	return unit.role == COMMANDER or unit.role == SOLDIER


static func command_strength(commander: GlobalAgent) -> float:
	if commander == null or not commander.alive:
		return 0.0
	return clampf(commander.health / maxf(1.0, commander.max_health) * commander.morale, 0.0, 1.0)


static func speed_multiplier(commander: GlobalAgent) -> float:
	return lerpf(0.55, 1.0, command_strength(commander))


static func corridor(world: AlifeWorldContext, unit: GlobalAgent) -> Array[Vector2i]:
	return world.travel.march_corridor(world.world_seed, unit.tile, unit.destination_tile)


static func unit_speed(world: AlifeWorldContext, unit: GlobalAgent) -> float:
	var id: String = unit.agent_id.get_slice("/unit/", 0)
	return speed_multiplier(world.agents.find(unit_id(id, 0)) as GlobalAgent)
