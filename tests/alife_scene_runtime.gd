extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	# All checks use the real game scene but never touch the user's save slots.
	var save_system: Node = main.get_node("Systems/SaveSystem")
	save_system.free()
	SaveSystem.instance = null
	GameManager.start_new_game(12345, "alife_readonly_verification")
	var world_system: WorldSystem = main.get_node("World") as WorldSystem
	check(WorldSimulation.world.settlements.all().size() > 10, "Game start populates settlements")
	var settlement: AlifeSettlement = null
	for entry: AlifeSettlement in WorldSimulation.world.settlements.all():
		if entry.population >= 250:
			settlement = entry
			break
	check(settlement != null, "Generated populated city")
	if settlement == null:
		get_tree().quit(1)
		return
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(settlement.tile + Vector2i(0, 2)))
	for frame: int in range(100):
		await get_tree().process_frame
	var chunk: Vector2i = Config.tile_to_chunk(settlement.tile)
	var info: Dictionary = world_system.get_chunk_pois().get(chunk, {})
	check(str(info.get("settlement_id", "")) == settlement.settlement_id, "Settlement is integrated into world POIs")
	check(not info.has("streets") and not info.has("structures"), "Local settlement chunk has no generated city layout")
	var lord: GlobalAgent = WorldSimulation.world.agents.find(settlement.settlement_id + "/resident/0000") as GlobalAgent
	check(lord != null, "Settlement leader remains in the global simulation")
	var live: Array = []
	for agent: GlobalAgent in WorldSimulation.world.agents.by_settlement(settlement.settlement_id):
		if WorldSimulation.world.agents.materialized.has(agent.agent_id):
			live.append(agent.agent_id)
	check(not live.is_empty() and live.size() <= AgentMaterializer.MAX_ACTIVE_RESIDENTS, "City residents materialize within the active NPC budget")
	var seen: Dictionary = {}
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if npc.has_meta("global_agent_id"):
			var id: String = str(npc.get_meta("global_agent_id"))
			check(not seen.has(id), "No duplicate agent scenes")
			seen[id] = true
	var vendor: NPCBase = null
	for agent: GlobalAgent in WorldSimulation.world.agents.by_settlement(settlement.settlement_id):
		if agent.role == "trader" and agent.caravan_id.is_empty() and WorldSimulation.world.agents.materialized.has(agent.agent_id):
			vendor = WorldSimulation.world.agents.materialized[agent.agent_id] as NPCBase
			break
	check(vendor != null, "City has a local vendor not assigned to an expedition")
	var donor: AlifeSettlement = null
	for neighbor: AlifeSettlement in WorldSimulation.world.settlements.get_connected(settlement.settlement_id):
		if not WorldSimulation.world.travel.path(WorldSimulation.world.world_seed, neighbor.tile, settlement.tile + Vector2i(2, 2)).is_empty():
			donor = neighbor
			break
	check(donor != null, "City has a reachable trade supplier")
	if vendor != null and donor != null:
		# Control one shipment's arrival while using the real dispatch and market services.
		WorldSimulation.set_process(false)
		donor.treasury = 20000
		donor.food = float(donor.population) * 10.0 + 400.0
		settlement.food = 0.0
		settlement.market_funds = 100000
		var shipment: CaravanRoute = CaravanRoute.new()
		shipment.route_id = "verification_supply"
		shipment.from_id = donor.settlement_id
		shipment.to_id = settlement.settlement_id
		shipment.at_id = donor.settlement_id
		WorldSimulation.world.routes.register(shipment)
		var dispatched: bool = false
		for frame: int in range(1800):
			WorldSimulation.world.travel.poll()
			dispatched = CaravanRouteManager.dispatch(WorldSimulation.world, shipment)
			if dispatched:
				break
			await get_tree().process_frame
		check(dispatched, "Real shipment waits for its background route, then reserves stock, crew and investment")
		if shipment.active:
			for id: String in [shipment.merchant_id] + shipment.guards:
				WorldSimulation.materializer.dematerialize(id)
				var crew: GlobalAgent = WorldSimulation.world.agents.find(id) as GlobalAgent
				crew.tile = crew.destination_tile
				crew.world_position.clear()
			check(CaravanRouteManager.arrive(WorldSimulation.world, shipment), "Arrived shipment replenishes the city market")
		var player: Player = main.get_node("World/Player") as Player
		player.inventory.silver = 10000
		var stock_before: float = settlement.food
		var wallet_before: int = CurrencyPolicy.total_value(player.inventory)
		var bread_before: int = player.inventory.count_of("bread")
		var trade_ui: TradeMenuUI = main.get_node("UILayer/TradeMenu") as TradeMenuUI
		trade_ui._on_trade_session_requested(vendor)
		var market: Dictionary = {}
		SignalBus.alife_market_queried.emit(vendor, market)
		var parameters: Dictionary = trade_ui._trade_parameters()
		var quote: Dictionary = MarketPricing.quote("bread", market, true, parameters.skill, parameters.memory)
		var row: int = trade_ui._trader_stock.find("bread")
		check(row >= 0 and trade_ui._stock_list.get_item_text(row).contains("%d silver" % int(quote["price"])), "Visible trade menu displays the service quote")
		SignalBus.trade_transaction_requested.emit(vendor, "bread", 1, true)
		check(player.inventory.count_of("bread") == bread_before + 1 and settlement.food == stock_before - 1.0, "Actual trade signal transfers one delivered item")
		check(CurrencyPolicy.total_value(player.inventory) == wallet_before - int(quote["silver_value"]), "Actual trade charges the displayed amount")
		trade_ui.close_trade()
	var local_residents: Array[String] = []
	for id: String in live:
		var reference: Variant = WorldSimulation.world.agents.materialized.get(id)
		if is_instance_valid(reference) and Config.tile_to_chunk(Config.iso_to_world(reference.global_position)) == chunk:
			local_residents.append(id)
	check(not local_residents.is_empty(), "Core chunk has at least one resident to unload")
	var resident_id: String = local_residents[0] if not local_residents.is_empty() else ""
	if not resident_id.is_empty():
		var resident: NPCBase = WorldSimulation.world.agents.materialized[resident_id] as NPCBase
		resident.stats.health = 51.0
		resident.inventory.gold = 37
		var bundle: Dictionary = {"world": {}, "player": {}, "meta": {}}
		SignalBus.save_data_requested.emit(bundle)
		check(bundle.world.has("alife") and bundle.world.has("fog"), "Shared save bundle keeps both simulation and terrain")
		var snapshot: AlifeWorldContext = preload("res://scripts/alife/agent_save_delta.gd").new().decode(JSON.parse_string(JSON.stringify(bundle.world.alife)), Config.TERRAIN_GEOGRAPHY_SIZE)
		check(snapshot != null and preload("res://scripts/alife/save_reference_validator.gd").validate(snapshot).is_empty(),
			"Real gameplay snapshot passes the same reference checks as slot loading")
		check(snapshot != null and (snapshot.agents.find(resident_id) as GlobalAgent).health == 51.0, "Save captures live resident health")
		check(snapshot != null and int((snapshot.agents.find(resident_id) as GlobalAgent).inventory.get("gold", 0)) == 37, "Save captures live inventory")
		check(snapshot != null and (snapshot.settlements.find(settlement.settlement_id) as AlifeSettlement).food == settlement.food, "Shared save captures stock after delivery and player purchase")
	world_system._unload_chunk(chunk)
	await get_tree().process_frame
	for id: String in local_residents:
		check(not WorldSimulation.world.agents.materialized.has(id), "Unload removes residents in the departing chunk")
	world_system._load_chunk(chunk)
	check(not world_system.get_chunk_pois().get(chunk, {}).has("structures"), "Reload does not regenerate city structures")
	if not resident_id.is_empty():
		var agent: GlobalAgent = WorldSimulation.world.agents.find(resident_id) as GlobalAgent
		var resident: NPCBase = WorldSimulation.materializer.materialize(agent)
		check(resident != null and resident.stats.health == 51.0 and resident.inventory.gold == 37, "Reload restores resident state")
	_check_local_political_rumor(settlement)
	_check_daily_routine(settlement, live)
	_check_killing_witness(settlement, live)
	SettlementStatus.transition(WorldSimulation.world, settlement, AlifeSettlement.Status.RUINS)
	WorldSimulation.materializer.reconcile_dead()
	WorldSimulation._publish_events()
	await get_tree().process_frame
	await get_tree().process_frame
	check(settlement.population == 0 and settlement.status == AlifeSettlement.Status.RUINS, "Destroyed settlement has no living population")
	check(not world_system.get_chunk_pois().get(chunk, {}).has("structures"), "Settlement status change does not generate city structures")
	world_system.update_visibility(Config.world_to_iso(settlement.tile))
	var map_snapshot: Dictionary = {}
	SignalBus.alife_political_map_queried.emit(map_snapshot)
	var observed: Array = map_snapshot.get("settlements", [])
	var territory: Array = map_snapshot.get("territory", [])
	var city_chunk: Vector2i = Config.tile_to_chunk(settlement.tile)
	check(territory.any(func(entry: Dictionary) -> bool: return entry["chunk"] == [city_chunk.x, city_chunk.y]), "Political atlas includes visible settlement territory")
	check(not observed.is_empty() and observed.size() < WorldSimulation.world.settlements.all().size(), "Political atlas shows observations without revealing the world")
	var coords: Array = [settlement.tile.x, settlement.tile.y]
	var city_rows: Array = observed.filter(func(entry: Dictionary) -> bool: return entry["tile"] == coords)
	check(city_rows.size() == 1 and city_rows[0]["status"] == AlifeSettlement.Status.RUINS, "Political atlas records observed ruins")
	var atlas: WorldMapUI = main.get_node("UILayer/WorldMapUI")
	atlas._refresh_political_layer()
	check(atlas._political_settlements == observed, "Political layer uses the observed settlement snapshot")
	world_system.update_visibility(Config.world_to_iso(Vector2i(2, 2)))
	settlement.status = AlifeSettlement.Status.NORMAL
	map_snapshot.clear()
	SignalBus.alife_political_map_queried.emit(map_snapshot)
	check(map_snapshot.get("settlements", []) == observed, "Political atlas does not reveal changes outside current vision")
	check(map_snapshot.get("territory", []) == territory, "Territory also remains at its last observed state")
	_check_observed_army(world_system, settlement.tile)
	_check_rural_claim(world_system, settlement)
	_check_refugee_camp_view(world_system, settlement.tile)
	print("ALIFE SCENE TESTS: ", "PASS" if failures == 0 else "FAIL", " residents=", live.size(), " failures=", failures)
	WorldSimulation._initialized = false
	GameManager._state = GameManager.State.BOOT
	get_tree().quit(0 if failures == 0 else 1)

func _check_local_political_rumor(local: AlifeSettlement) -> void:
	var context: AlifeWorldContext = WorldSimulation.world
	var previous: Dictionary = context.narrative.get("political_intel", {}).duplicate(true)
	var remote: AlifeSettlement
	for candidate: AlifeSettlement in context.settlements.all():
		if Config.tile_distance(local.tile, candidate.tile) > 60:
			remote = candidate
			break
	check(remote != null, "Political rumor fixture has a remote settlement")
	if remote == null:
		return
	var known: Dictionary = {}
	WorldSimulation._observe_political_settlement(remote, known)
	context.narrative["political_intel"] = known
	var rumor: Dictionary = {
		"event_id": context.next_event_id, "event_type": "settlement_captured",
		"origin_tile": [remote.tile.x, remote.tile.y], "created_hour": context.simulated_hour + 1.0,
		"received_at": {},
	}
	context.rumors.append(rumor)
	var snapshot: Dictionary = {}
	SignalBus.alife_political_map_queried.emit(snapshot)
	check(not known[remote.settlement_id].has("rumor"), "Undelivered rumors stay hidden")
	rumor["received_at"][local.settlement_id] = {"content": "Travelers say the city has changed hands."}
	SignalBus.alife_political_map_queried.emit(snapshot)
	var report: Dictionary = known[remote.settlement_id].get("rumor", {})
	check(report.get("content") == rumor["received_at"][local.settlement_id]["content"], "Atlas records the local version of a delivered rumor")
	check(known[remote.settlement_id]["faction"] != "", "Rumor preserves the last observed owner")
	context.rumors.erase(rumor)
	context.narrative["political_intel"] = previous

func _check_daily_routine(settlement: AlifeSettlement, live: Array) -> void:
	var context: AlifeWorldContext = WorldSimulation.world
	var subject: NPCBase
	for id: String in live:
		var reference: Variant = context.agents.materialized.get(id)
		if is_instance_valid(reference):
			subject = reference as NPCBase
			break
	check(subject != null, "Daily routine fixture has a live NPC")
	if subject == null:
		return
	var route: Array[Vector2i] = PathfindingService.compute_local_route(Vector2i.ZERO, Vector2i(2, 0),
		func(tile: Vector2i) -> bool: return tile != Vector2i(1, 0))
	check(route.size() == 4 and route.back() == Vector2i(2, 0) and not route.has(Vector2i(1, 0)), "Routine path detours around a wall")
	var old_position: Vector2 = subject.global_position
	var old_tier: int = subject.sim_tier
	var start: Vector2i = settlement.tile
	var target: Vector2i = start + Vector2i.DOWN
	subject.global_position = Config.world_to_iso(start)
	subject.sim_tier = SimulationBubble.Tier.REDUCED
	for step: int in range(16):
		subject._follow_routine(target, 0.2)
	check(subject.global_position.distance_to(Config.world_to_iso(target)) < 2.0, "Live NPC follows a routine across paving")
	subject.global_position = old_position
	subject.sim_tier = old_tier as SimulationBubble.Tier

func _check_facility_assignments(settlement: AlifeSettlement, live: Array) -> void:
	if live.size() < 2:
		return
	var context: AlifeWorldContext = WorldSimulation.world
	var previous: Dictionary = context.narrative.get("routine_facilities", {})
	context.narrative["routine_facilities"] = {}
	var facilities: Dictionary = {}
	SignalBus.settlement_facilities_queried.emit(settlement.settlement_id, facilities)
	var assigned: Array[Vector2i] = []
	for index: int in range(2):
		var agent: GlobalAgent = context.agents.find(str(live[index])) as GlobalAgent
		var old_goal: String = agent.current_goal
		var old_tile: Vector2i = agent.tile
		agent.current_goal = "sleep"
		agent.tile = settlement.tile
		var activity: Dictionary = {}
		var target: Vector2i = WorldSimulation.materializer._routine_destination(agent, activity)
		check(activity.get("kind") == "bed", "Assigned bed includes pose metadata")
		check(facilities.values().any(func(row: Dictionary) -> bool:
			return row["kind"] == "bed" and row["approach"] == [target.x, target.y]), "Sleeping resident uses an actual bed approach")
		assigned.append(target)
		agent.current_goal = old_goal
		agent.tile = old_tile
	check(assigned[0] != assigned[1], "Residents receive distinct available bed slots")
	var leases: Dictionary = context.narrative.get("routine_facilities", {}).get(settlement.settlement_id, {})
	check(leases.get("bed", {}).size() == 2, "Bed reservations are part of saveable world state")
	var worker: GlobalAgent = context.agents.find(str(live[0])) as GlobalAgent
	var old_role: String = worker.role
	var old_goal: String = worker.current_goal
	worker.role = "worker"
	worker.current_goal = "work"
	var work_activity: Dictionary = {}
	var work_target: Vector2i = WorldSimulation.materializer._routine_destination(worker, work_activity)
	check(facilities.values().any(func(row: Dictionary) -> bool:
		return row["kind"] == "workbench" and row["approach"] == [work_target.x, work_target.y]), "Worker uses a real workbench approach")
	var subject: NPCBase = context.agents.materialized.get(worker.agent_id) as NPCBase
	if is_instance_valid(subject):
		var old_position: Vector2 = subject.global_position
		var old_activity: Dictionary = subject.get_meta("alife_routine_activity", {})
		subject.set_meta("alife_routine_activity", work_activity)
		subject.global_position = Config.world_to_iso(work_target)
		subject._update_routine_pose("work", work_target, 0.2)
		subject._update_routine_pose("work", work_target, 0.2)
		check(subject._routine_pose == "workbench" and subject._routine_pose_time > 0.0, "Workbench action animates after arrival")
		subject._update_routine_pose("idle", work_target, 0.2)
		check(subject._routine_pose.is_empty(), "Changing goals ends the work pose")
		subject.set_meta("alife_routine_activity", old_activity)
		subject.global_position = old_position
	worker.role = old_role
	worker.current_goal = old_goal
	context.narrative["routine_facilities"] = previous

func _check_killing_witness(settlement: AlifeSettlement, live: Array) -> void:
	var context: AlifeWorldContext = WorldSimulation.world
	var witness: NPCBase
	for id: String in live:
		var reference: Variant = context.agents.materialized.get(id)
		if is_instance_valid(reference):
			witness = reference as NPCBase
			break
	check(witness != null, "Witness fixture has a live NPC")
	if witness == null:
		return
	var witness_id: String = str(witness.get_meta("global_agent_id"))
	var record: GlobalAgent = context.agents.find(witness_id) as GlobalAgent
	var old_position: Vector2 = witness.global_position
	witness.global_position = Config.world_to_iso(settlement.tile)
	var victim: GlobalAgent = GlobalAgent.new()
	victim.agent_id = "verification_victim"
	victim.faction_id = record.faction_id
	victim.settlement_id = record.settlement_id
	victim.tile = settlement.tile + Vector2i.RIGHT
	var old_opinion: int = witness.memory.personal_opinion_of_player
	WorldSimulation._record_killing_witnesses(victim)
	WorldSimulation._record_killing_witnesses(victim)
	check(record.grudges.filter(func(row: Dictionary) -> bool: return row.get("victim") == victim.agent_id).size() == 1, "Witness records a victim only once")
	check(witness.memory.personal_opinion_of_player == maxi(-100, old_opinion - 35), "Witness opinion changes once")
	var restored: GlobalAgent = GlobalAgent.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	check(restored.grudges.any(func(row: Dictionary) -> bool: return row.get("victim") == victim.agent_id)
		and int(restored.memory_state.get("personal_opinion_of_player", 0)) == record.relation_to_player,
		"Grudge and opinion survive serialization")
	var anonymous: GlobalAgent = GlobalAgent.new()
	anonymous.agent_id = "verification_body"
	anonymous.settlement_id = record.settlement_id
	anonymous.faction_id = record.faction_id
	var opinion: int = witness.memory.personal_opinion_of_player
	var morale: float = record.morale
	WorldSimulation._spawn_resident_body(witness, anonymous)
	WorldSimulation._discover_resident_bodies()
	WorldSimulation._discover_resident_bodies()
	check(record.memories.filter(func(row: Dictionary) -> bool: return row.get("subject_id") == anonymous.agent_id).size() == 1,
		"Discovery remembers each body only once")
	check(is_equal_approx(record.morale, maxf(0.0, morale - 0.1)) and witness._body_notice_time > 0.0,
		"Body discovery reduces morale and stops the witness")
	check(witness.memory.personal_opinion_of_player == opinion, "An unwitnessed death does not accuse the player")
	RumorTick.new().tick(context)
	var delivered: Array[String] = []
	var capture: Callable = func(_source: String, content: String) -> void:
		if content.contains("the traveler killed a resident"):
			delivered.append(content)
	SignalBus.local_rumor_heard.connect(capture)
	SignalBus.alife_resident_spoken_to.emit(witness_id)
	SignalBus.alife_resident_spoken_to.emit(witness_id)
	SignalBus.local_rumor_heard.disconnect(capture)
	check(delivered.size() == 1, "The resident shares local testimony with the player only once")
	var warrants = preload("res://scripts/alife/factions/local_warrants.gd")
	var original_hour: float = context.simulated_hour
	warrants.tick(context)
	check(not warrants.is_active(context, settlement), "Warrant requires time to file testimony")
	context.simulated_hour += 1.0
	warrants.tick(context)
	check(warrants.is_active(context, settlement), "Living witness creates a local warrant")
	var market: Dictionary = {}
	SignalBus.alife_market_queried.emit(witness, market)
	check(bool(market.get("closed", false)) and market.has("close_reason"), "A local warrant closes market access")
	context.simulated_hour += 72.0
	warrants.tick(context)
	check(not warrants.is_active(context, settlement), "Local warrant expires")
	context.simulated_hour = original_hour
	context.reputation["local_warrants"][settlement.settlement_id] = {
		"issuer": settlement.owner_faction, "until_hour": original_hour + 72.0, "offenses": 2,
	}
	var role: String = record.role
	record.role = "elder"
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	var wallet_before: int = CurrencyPolicy.total_value(player.inventory)
	var treasury_before: int = settlement.treasury
	var amnesty: Dictionary = {}
	SignalBus.local_amnesty_requested.emit(witness, 120, amnesty)
	check(not bool(amnesty.get("ok", false)) and CurrencyPolicy.total_value(player.inventory) == wallet_before,
		"Changed amnesty quote cannot debit the wallet")
	amnesty.clear()
	SignalBus.local_amnesty_requested.emit(witness, 200, amnesty)
	check(bool(amnesty.get("ok", false)) and not warrants.is_active(context, settlement), "Paying amnesty lifts the local warrant")
	check(CurrencyPolicy.total_value(player.inventory) == wallet_before - 200 and settlement.treasury == treasury_before + 200,
		"Amnesty transfers the exact quoted amount to the settlement")
	amnesty.clear()
	SignalBus.local_amnesty_requested.emit(witness, 200, amnesty)
	check(not bool(amnesty.get("ok", false)) and settlement.treasury == treasury_before + 200, "Amnesty cannot be paid twice")
	record.role = role
	witness.global_position = old_position

func _check_observed_army(world_system: WorldSystem, tile: Vector2i) -> void:
	var context: AlifeWorldContext = WorldSimulation.world
	var army: AlifeConflict = AlifeConflict.new()
	army.conflict_id = "verification_army"
	army.phase = "marching"
	army.attacker_id = "guards"
	var soldier: GlobalAgent = GlobalAgent.new()
	soldier.agent_id = "verification_soldier"
	soldier.tile = tile
	soldier.deployment_id = army.conflict_id
	army.attacker_agents.append(soldier.agent_id)
	context.conflicts.register(army)
	context.agents.register(soldier)
	var snapshot: Dictionary = {}
	SignalBus.alife_political_map_queried.emit(snapshot)
	var tracks: Dictionary = context.narrative.get("political_armies", {})
	check(not tracks.has(army.conflict_id), "Atlas does not plot an unseen army")
	world_system.update_visibility(Config.world_to_iso(tile))
	soldier.tile += Vector2i.RIGHT
	SignalBus.alife_political_map_queried.emit(snapshot)
	var points: Array = tracks.get(army.conflict_id, {}).get("points", [])
	check(points.size() == 2 and points.back()["joined"], "Two adjacent visible samples form an observed route")
	world_system.update_visibility(Config.world_to_iso(Vector2i(2, 2)))
	soldier.tile += Vector2i.RIGHT
	SignalBus.alife_political_map_queried.emit(snapshot)
	check(points.size() == 2, "Movement outside vision adds no sample")
	world_system.update_visibility(Config.world_to_iso(tile))
	check(points.size() == 3 and not points.back()["joined"], "Reacquisition leaves a gap in the route")
	context.conflicts.remove(army.conflict_id)
	context.agents.remove(soldier.agent_id)

func _check_refugee_camp_view(world_system: WorldSystem, tile: Vector2i) -> void:
	var context: AlifeWorldContext = WorldSimulation.world
	world_system.update_visibility(Config.world_to_iso(tile))
	context.narrative["refugee_camps"] = {
		"verification_camp": {"tile": [tile.x, tile.y], "members": ["verification_traveler"]},
	}
	WorldSimulation._sync_refugee_camp_views()
	var view: Node2D = WorldSimulation._refugee_camp_views.get("verification_camp")
	check(is_instance_valid(view) and view.global_position == Config.world_to_iso(tile), "Visible camp materializes in the main scene")
	if is_instance_valid(view):
		var player: Player = get_tree().get_first_node_in_group("player") as Player
		var old_position: Vector2 = player.global_position
		player.global_position = view.global_position
		player.inventory.add_item("bread", 2)
		view.interact(player)
		var food: String = str(view.get("_offered_item"))
		var before: int = player.inventory.count_of(food)
		check(not food.is_empty() and not context.narrative["refugee_camps"]["verification_camp"].has("food"), "First interaction only quotes food aid")
		view.interact(player)
		check(player.inventory.count_of(food) == before - 1 and float(context.narrative["refugee_camps"]["verification_camp"].get("food", 0.0)) > 0.0,
			"Confirming aid transfers one food item")
		player.global_position = old_position
	context.narrative["refugee_camps"] = {}
	WorldSimulation._sync_refugee_camp_views()
	check(not WorldSimulation._refugee_camp_views.has("verification_camp"), "Disbanded camp removes its scene")

func _check_rural_claim(world_system: WorldSystem, settlement: AlifeSettlement) -> void:
	var claim: Vector2i = Vector2i(-1, -1)
	for chunk: Vector2i in WorldSimulation._territorial_claims:
		if WorldSimulation._settlement_chunks.has(chunk) or WorldSimulation._territorial_claims[chunk] != settlement.settlement_id:
			continue
		var tile: Vector2i = Config.chunk_origin(chunk) + Vector2i(8, 8)
		if Config.tile_distance(tile, settlement.tile) <= 55:
			claim = chunk
			break
	check(claim.x >= 0, "Settlement has a connected rural claim outside its districts")
	if claim.x < 0:
		return
	var sample: Vector2i = Config.chunk_origin(claim) + Vector2i(8, 8)
	var key: String = Config.vec2i_to_key(claim)
	var context: AlifeWorldContext = WorldSimulation.world
	settlement.owner_faction = "guards"
	world_system.update_visibility(Config.world_to_iso(Vector2i(2, 2)))
	world_system.update_visibility(Config.world_to_iso(sample))
	var observed: Dictionary = context.narrative["political_territory"].get(key, {})
	check(not observed.is_empty() and not observed["district"], "Observed countryside is colored separately from districts")
	world_system.update_visibility(Config.world_to_iso(Vector2i(2, 2)))
	settlement.status = AlifeSettlement.Status.RUINS
	settlement.owner_faction = ""
	var snapshot: Dictionary = {}
	SignalBus.alife_political_map_queried.emit(snapshot)
	check(context.narrative["political_territory"].has(key), "Unobserved collapse leaves the prior claim on the map")
	world_system.update_visibility(Config.world_to_iso(sample))
	check(not context.narrative["political_territory"].has(key), "Reobserving released land removes its faction claim")
