extends Node

const VILLAGE_ID: String = EconomyTick.VALDEN_VILLAGE_ID
const CASTLE_ID: String = EconomyTick.VALDEN_CASTLE_ID
const ROUTE_ID: String = WorldSimulation.VALDEN_GRAIN_ROUTE_ID
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--route-seeds" in OS.get_cmdline_user_args():
		_check_seed_paths()
		get_tree().quit(0 if failures == 0 else 1)
		return
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var slot: String = "__valden_caravan_" + Crypto.new().generate_random_bytes(16).hex_encode()
	GameManager.start_new_game(12345, slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	await _check_convoy(save_system, slot)
	save_system.delete_slot(slot)
	if failures == 0:
		print("VALDEN_GRAIN_CARAVAN_OK")
	get_tree().quit(0 if failures == 0 else 1)

func _check_seed_paths() -> void:
	var seeds: Array[int] = [Config.DEFAULT_WORLD_SEED, 12345, 1, 42, 9999, 20261119]
	for seed_value: int in seeds:
		var graph: WorldGraph = WorldGraph.for_seed(seed_value)
		var village: Vector2i = graph.site_for_cell(Vector2i(7, 14))["tile"]
		var castle: Vector2i = (graph.site_for_cell(Vector2i(7, 13))["tile"] as Vector2i) + CaravanRouteManager.MARKET_APPROACH
		var travel: AlifeTravel = AlifeTravel.new()
		var forward: Array[Vector2i] = travel.path(seed_value, village, castle, true)
		var reverse: Array[Vector2i] = travel.path(seed_value, castle, village, true)
		reverse.reverse()
		_check(not forward.is_empty() and forward == reverse, "No reversible connected route for seed %d" % seed_value)
	if failures == 0:
		print("VALDEN_GRAIN_CARAVAN_ROUTE_SEEDS_OK")

func _check_convoy(save_system: SaveSystem, slot: String) -> void:
	var start_tile: Vector2i = GameManager.get_player_tile()
	var departures: Array[Dictionary] = []
	var arrivals: Array[Dictionary] = []
	SignalBus.alife_event_published.connect(func(event: Dictionary) -> void:
		if str(event["data"].get("route_id", "")) != ROUTE_ID:
			return
		if event["event_type"] == "caravan_departed":
			departures.append(event["data"])
		elif event["event_type"] == "caravan_arrived":
			arrivals.append(event["data"])
	)
	await _advance_to(2, 8.0)
	_check(_settlement(CASTLE_ID).famine and _route() == null, "Dispatch should wait until the first visit to the elder")
	if not _check(save_system.save_slot(slot), "Could not save the post-introduction fixture"):
		return
	var path: String = SaveSystem._slot_dir(slot) + "world.json"
	var data: Dictionary = SaveSystem._read_json(path)
	data["frontier_introduction"]["stage"] = FrontierIntroduction.Stage.ARRIVED
	if not _check(SaveSystem._write_json(path, data) and save_system.load_slot(slot), "The completed introduction fixture did not load"):
		return

	var village: AlifeSettlement = _settlement(VILLAGE_ID)
	var castle: AlifeSettlement = _settlement(CASTLE_ID)
	var before_grain: float = float(village.stockpile["wheat"])
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(village.tile + Vector2i.LEFT))
	await _advance_to(2, 8.5)
	if not _check(_route() != null, "Famine did not open the Valden route"):
		return
	var castle_approach: Vector2i = castle.tile + CaravanRouteManager.MARKET_APPROACH
	await _wait_for_path(village.tile, castle_approach)
	await _advance_to(2, 9.0)
	var route: CaravanRoute = _route()
	if not _check(route.active and int(route.cargo.get("wheat", 0)) >= 320 and route.guards.size() == 4,
			"Scheduled departure did not load real wheat and hire four guards"):
		return
	_check(not WorldSimulation.alife_enabled and departures.size() == 1 and arrivals.is_empty() and float(village.stockpile["wheat"]) < before_grain,
		"Departure did not debit wheat exactly once in normal gameplay")
	var initial_cargo: Dictionary = route.cargo.duplicate()
	var initial_funds: int = castle.market_funds
	var crew_id: String = route.merchant_id
	var guard_ids: Array = route.guards.duplicate()
	var merchant: GlobalAgent = _merchant(route)
	var departure_tile: Vector2i = merchant.tile
	var saved_path: Dictionary = WorldSimulation.world.travel.saved_routes().get(crew_id, {})
	_check(_is_contiguous(saved_path.get("route", [])) and merchant.destination_tile == castle_approach,
		"The merchant path must be contiguous from Valden to the castle")
	await get_tree().create_timer(4.0).timeout
	var entity: NPCBase = WorldSimulation.world.agents.materialized.get(crew_id) as NPCBase
	var pack: CaravanPackAnimal = WorldSimulation.pack_materializer.get_entity(ROUTE_ID)
	_check(is_instance_valid(entity) and is_instance_valid(pack) and Config.tile_distance(departure_tile, merchant.tile) >= 2.0,
		"The convoy did not walk out as visible NPCs with a pack animal")
	for id: String in guard_ids:
		_check(is_instance_valid(WorldSimulation.world.agents.materialized.get(id)), "A recruited guard did not appear with the convoy")

	SignalBus.player_teleport_requested.emit(Config.world_to_iso(start_tile))
	await _advance_to(2, 11.0)
	_check(not WorldSimulation.world.agents.materialized.has(crew_id) and WorldSimulation.pack_materializer.get_entity(ROUTE_ID) == null
		and route.active and Config.tile_distance(departure_tile, merchant.tile) > 50 and route.cargo == initial_cargo, "The convoy did not continue when its chunks unloaded")
	var saved_location: Vector2i = merchant.tile
	if not _check(save_system.save_slot(slot) and save_system.load_slot(slot), "The journey could not be reloaded"):
		return
	route = _route()
	if not _check(route != null and route.active and route.cargo == initial_cargo and route.guards == guard_ids
			and route.merchant_id == crew_id and _merchant(route).tile == saved_location and _settlement(CASTLE_ID).famine,
			"The save changed the crew, position, cargo or hunger mid-trip"):
		return

	for hour: int in range(15):
		if not route.active:
			break
		await _advance_hours(1.0)
	if not _check(route.successful_trips == 1 and arrivals.size() == 1 and departures.size() == 1,
			"The same expedition did not deliver exactly once after loading: %s" % str(route.success_history)):
		return
	await _advance_hours(0.5)
	castle = _settlement(CASTLE_ID)
	_check(castle.food > 0.0 and not castle.famine and castle.market_funds == initial_funds - CaravanRouteManager.cargo_value(initial_cargo) - CaravanRouteManager.TRIP_MARGIN,
		"The castle did not buy and mill the wheat")
	await _advance_hours(1.0)
	await _wait_for_path(castle_approach, _settlement(VILLAGE_ID).tile)
	await _advance_hours(0.5)
	if not _check(route.is_returning() and route.cargo.is_empty() and route.merchant_id == crew_id
			and not EscortContracts.can_offer(WorldSimulation.world, route), "The empty return is not using the same convoy"):
		return
	var funds_after_delivery: int = castle.market_funds
	for hour: int in range(15):
		if not route.active:
			break
		await _advance_hours(1.0)
	_check(not route.active and route.at_id == VILLAGE_ID and route.successful_trips == 1
		and departures.size() == 1 and arrivals.size() == 1 and castle.market_funds == funds_after_delivery, "The empty return booked a sale or did not reach the village")


func _is_contiguous(tiles: Array) -> bool:
	if tiles.size() < 500:
		return false
	for index: int in range(1, tiles.size()):
		var before := Vector2i(int(tiles[index - 1][0]), int(tiles[index - 1][1]))
		var after := Vector2i(int(tiles[index][0]), int(tiles[index][1]))
		if Config.tile_distance(before, after) != 1:
			return false
	return true


func _wait_for_path(from_tile: Vector2i, to_tile: Vector2i) -> void:
	var timeout: int = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < timeout and WorldSimulation.world.travel.is_path_pending(WorldSimulation.world.world_seed, from_tile, to_tile, true):
		await get_tree().process_frame


func _advance_to(day: int, hour: float) -> void:
	GameManager.set_day_and_hour(day, hour)
	for frame: int in range(16):
		await get_tree().process_frame


func _advance_hours(hours: float) -> void:
	var target: float = WorldSimulation.world.simulated_hour + hours
	await _advance_to(floori(target / 24.0) + 1, fposmod(target, 24.0))


func _settlement(id: String) -> AlifeSettlement:
	return WorldSimulation.world.settlements.find(id) as AlifeSettlement


func _route() -> CaravanRoute:
	return WorldSimulation.world.routes.find(ROUTE_ID) as CaravanRoute


func _merchant(route: CaravanRoute) -> GlobalAgent:
	return WorldSimulation.world.agents.find(route.merchant_id) as GlobalAgent


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error("VALDEN_GRAIN_CARAVAN_FAILURE: " + message)
	return ok
