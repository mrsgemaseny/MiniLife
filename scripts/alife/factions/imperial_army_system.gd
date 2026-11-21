class_name ImperialArmySystem
extends RefCounted

static func tick(world: AlifeWorldContext, hours: float) -> void:
	if hours <= 0.0:
		return
	var armies: Dictionary = world.narrative.get("authored_armies", {})
	for army_id: String in armies:
		var track: Dictionary = armies[army_id]
		if str(track.get("status", "")) != "roaming":
			continue
		var route: Array = track.get("route", [])
		var position: Array = track.get("position", [])
		var commander: Dictionary = DataRegistry.get_entry("imperial_commanders", army_id)
		if route.size() < 2 or position.size() != 2 or commander.is_empty():
			continue
		var index: int = int(track.get("route_index", -1))
		if index < 0 or index >= route.size():
			index = _nearest_waypoint(route, position)
			track["route_index"] = index
			track["route_direction"] = -1 if index == route.size() - 1 else 1
		var archetype: String = str(track.get("commander_archetype", commander["archetype"]))
		var hours_per_cell: float = maxf(0.1, float(commander["hours_per_cell"]))
		var morale_change: float = float(commander["morale_per_hour"])
		match archetype:
			"BROKEN":
				hours_per_cell = maxf(hours_per_cell, 14.0)
				morale_change = minf(morale_change, -0.025)
			"SEEKING":
				hours_per_cell = maxf(hours_per_cell, 10.0)
			"DISCIPLINED":
				hours_per_cell = minf(hours_per_cell, 6.0)
				morale_change = maxf(morale_change, 0.015)
		track["morale"] = clampf(float(track.get("morale", commander["initial_morale"])) + morale_change * hours, 0.0, 100.0)
		var progress: float = float(track.get("travel_progress", 0.0)) + hours / hours_per_cell
		var direction: int = int(track.get("route_direction", 1))
		var steps: int = mini(floori(progress + 0.000001), 128)
		for _step: int in steps:
			var next_index: int = index + direction
			if next_index < 0 or next_index >= route.size():
				direction *= -1
				next_index = index + direction
			index = next_index
			track["position"] = (route[index] as Array).duplicate()
			SignalBus.imperial_army_moved.emit(army_id, Vector2i(int(track["position"][0]), int(track["position"][1])))
		track["route_index"] = index
		track["route_direction"] = direction
		track["travel_progress"] = maxf(0.0, progress - float(steps))
		armies[army_id] = track
	world.narrative["authored_armies"] = armies

static func _nearest_waypoint(route: Array, position: Array) -> int:
	var current := Vector2i(int(position[0]), int(position[1]))
	var closest: int = 0
	var best_distance: int = 2147483647
	for index: int in route.size():
		var point: Array = route[index]
		var distance: int = absi(current.x - int(point[0])) + absi(current.y - int(point[1]))
		if distance < best_distance:
			best_distance = distance
			closest = index
	return closest
