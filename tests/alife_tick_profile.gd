extends Node

const TICKS: int = 144
const SEED_VALUE: int = 12345
const STEP_HOURS: float = WorldSimulation.GLOBAL_TICK_INTERVAL / Config.SECONDS_PER_GAME_HOUR
const WORKER_WINDOW_SECONDS: float = 0.15
const LocalWarrants = preload("res://scripts/alife/factions/local_warrants.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--game-loop" in OS.get_cmdline_user_args():
		await _run_game_loop()
		return
	var context: AlifeWorldContext = AlifeWorldContext.new()
	context.seed_world(SEED_VALUE, 8.0)
	WorldSeedBuilder.populate(context)
	context.authored_trade_only = WorldData.has_trade_layer()
	CaravanRouteManager.register_authored_routes(context)
	var background_routes: bool = "--background-routes" in OS.get_cmdline_user_args()
	context.travel.background_enabled = background_routes
	if "--frame-budget" in OS.get_cmdline_user_args():
		await _run_frame_budget(context)
		return
	var economy: EconomyTick = EconomyTick.new()
	var factions: FactionTick = FactionTick.new()
	var agents: AgentTick = AgentTick.new()
	var conflicts: ConflictTick = ConflictTick.new()
	var caravans: CaravanTick = CaravanTick.new()
	var rumors: RumorTick = RumorTick.new()
	var phases: Dictionary = {"simulation": [], "economy": [], "factions": [], "agents": [],
		"conflicts": [], "caravans": [], "rumors_and_warrants": []}
	for index: int in range(TICKS):
		context.simulated_hour += STEP_HOURS
		var first: int = Time.get_ticks_usec()
		var start: int = first
		economy.tick(context, STEP_HOURS, true)
		start = _sample(phases["economy"], start)
		factions.tick(context, STEP_HOURS)
		start = _sample(phases["factions"], start)
		agents.tick(context, STEP_HOURS)
		start = _sample(phases["agents"], start)
		conflicts.tick(context, STEP_HOURS)
		start = _sample(phases["conflicts"], start)
		caravans.tick(context)
		start = _sample(phases["caravans"], start)
		rumors.tick(context)
		LocalWarrants.tick(context)
		_sample(phases["rumors_and_warrants"], start)
		_sample(phases["simulation"], first)
		context.tick_count += 1
		if (index + 1) % 48 == 0:
			print("ALIFE_TICK_PROFILE_PROGRESS %d/%d" % [index + 1, TICKS])
		if background_routes:
			await _poll_routes(context.travel)
	var report: Dictionary = {}
	for key: String in phases:
		report[key] = _summary(phases[key])
	var saved_at: int = Time.get_ticks_usec()
	var snapshot: String = JSON.stringify(context.to_dict(), "", true, true)
	var save_ms: float = float(Time.get_ticks_usec() - saved_at) / 1000.0
	print("ALIFE_TICK_PROFILE ", JSON.stringify({"ticks": TICKS, "agents": context.agents.all().size(),
		"background_routes": background_routes,
		"sites": context.settlements.all().size(), "active_conflicts": context.conflicts.all().size(),
		"events": context.events.size(), "state_sha256": snapshot.sha256_text(), "snapshot_ms": save_ms, "phases_ms": report}))
	context.travel.shutdown()
	get_tree().quit()


func _run_game_loop() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.set_process(false)
	WorldSimulation.set_process(false)
	GameManager.start_new_game(SEED_VALUE, "alife_profile_readonly")
	WorldSimulation.alife_enabled = true
	for frame: int in range(45):
		await get_tree().process_frame
	if GlobalLandscapeMap.cell_for_tile(GameManager.get_player_tile()) != Vector2i(9, 14):
		push_error("Game-loop profile did not spawn in cell (9, 14)")
		get_tree().quit(1)
		return
	await _run_frame_budget(WorldSimulation.world, true)


func _run_frame_budget(context: AlifeWorldContext, game_loop: bool = false) -> void:
	if not game_loop:
		WorldSimulation.world = context
		WorldSimulation._valden_economy_enabled = true
	var frame_samples: Array = []
	var phases: Dictionary = {"start": [], "agents": [], "finish": [], "combined": []}
	var busy_steps: int = 0
	for index: int in range(TICKS):
		if game_loop and index == TICKS / 2:
			var village: AlifeSettlement = context.settlements.find(EconomyTick.VALDEN_VILLAGE_ID) as AlifeSettlement
			SignalBus.player_teleport_requested.emit(Config.world_to_iso(village.tile + Vector2i.LEFT))
			for frame: int in range(45):
				await get_tree().process_frame
			if GlobalLandscapeMap.cell_for_tile(GameManager.get_player_tile()) != EconomyTick.VALDEN_VILLAGE_CELL:
				push_error("Game-loop profile did not reach Valden")
				get_tree().quit(1)
				return
		var target: float = context.simulated_hour + STEP_HOURS + 0.0000001
		if game_loop:
			GameManager._day = floori(target / 24.0) + 1
			GameManager._hour = fposmod(target, 24.0)
		var frames: int = 0
		while context.tick_count <= index:
			var phase: String = "combined"
			if WorldSimulation._pending_tick_hours > 0.0:
				phase = "agents" if WorldSimulation.agent_tick.has_pending() else "finish"
			var start: int = Time.get_ticks_usec()
			if game_loop:
				WorldSimulation._process(get_process_delta_time())
			else:
				context.travel.poll()
				WorldSimulation._process_global_tick(target, STEP_HOURS)
			_sample(frame_samples, start)
			if phase == "combined" and WorldSimulation._pending_tick_hours > 0.0:
				phase = "start"
			phases[phase].append(frame_samples.back())
			frames += 1
			if frames > 1000:
				push_error("Frame-budget profile stalled at strategic step %d" % index)
				context.travel.shutdown()
				get_tree().quit(1)
				return
			await get_tree().process_frame
		if frames > 1:
			busy_steps += 1
		if (index + 1) % 48 == 0:
			print("ALIFE_TICK_PROFILE_PROGRESS %d/%d" % [index + 1, TICKS])
		if context.travel.background_enabled:
			await _poll_routes(context.travel, game_loop)
	var snapshot: String = JSON.stringify(context.to_dict(), "", true, true)
	var report: Dictionary = {}
	for phase: String in phases:
		if not phases[phase].is_empty():
			report[phase] = _summary(phases[phase])
	print("ALIFE_FRAME_PROFILE ", JSON.stringify({"ticks": context.tick_count, "agents": context.agents.all().size(),
		"background_routes": context.travel.background_enabled, "game_loop": game_loop,
		"frames": frame_samples.size(), "sliced_steps": busy_steps,
		"strategic_frame_ms": _summary(frame_samples), "phases_ms": report, "state_sha256": snapshot.sha256_text()}))
	context.travel.shutdown()
	get_tree().quit()


func _poll_routes(travel: AlifeTravel, game_loop: bool = false) -> void:
	# Give the route worker time to run between the synthetic strategic steps.
	var interval: SceneTreeTimer = get_tree().create_timer(WORKER_WINDOW_SECONDS)
	while interval.time_left > 0.0:
		if game_loop:
			WorldSimulation._process(get_process_delta_time())
		else:
			travel.poll()
		await get_tree().process_frame


func _sample(samples: Array, start: int) -> int:
	var end: int = Time.get_ticks_usec()
	samples.append(float(end - start) / 1000.0)
	return end


func _summary(samples: Array) -> Dictionary:
	var total: float = 0.0
	var running: Array = []
	for sample: float in samples:
		total += sample
		if sample > 1.0:
			running.append(sample)
	samples.sort()
	return {"total": total, "p95": samples[ceili(samples.size() * 0.95) - 1], "max": samples.back(),
		"nontrivial_samples": running.size(), "over_16_7ms": samples.filter(func(sample: float) -> bool: return sample > 16.7).size()}
