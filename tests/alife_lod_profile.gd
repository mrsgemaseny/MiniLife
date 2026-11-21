extends Node

const TICKS: int = 36
const STEP_HOURS: float = Config.LOD_MID_INTERVAL / Config.SECONDS_PER_GAME_HOUR

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(12345, 6.0)
	WorldSeedBuilder.populate(world)
	var agent_count: int = world.agents.all().size()
	var systems: Array = [EconomyTick.new(), FactionTick.new(), AgentTick.new(), ConflictTick.new(), CaravanTick.new(), RumorTick.new()]
	var names: Array[String] = ["economy", "factions", "agents", "conflicts", "caravans", "rumors"]
	var samples: Dictionary = {}
	for name: String in names:
		samples[name] = []
	var routes: Array = world.routes.all()
	var indexed_started: int = Time.get_ticks_usec()
	var indexed_count: int = 0
	for route: CaravanRoute in routes:
		indexed_count += world.agents.by_settlement(route.from_id).size()
	var indexed_ms: float = float(Time.get_ticks_usec() - indexed_started) / 1000.0
	var scan_started: int = Time.get_ticks_usec()
	var scanned_count: int = 0
	for route: CaravanRoute in routes:
		scanned_count += world.agents.matching("settlement_id", route.from_id).size()
	var scan_ms: float = float(Time.get_ticks_usec() - scan_started) / 1000.0
	assert(indexed_count == scanned_count)
	print("ALIFE_SETTLEMENT_LOOKUP indexed_ms=%.2f scan_ms=%.2f routes=%d" % [indexed_ms, scan_ms, routes.size()])
	var list_started: int = Time.get_ticks_usec()
	var global_agents: Array = world.agents.get_all_global()
	var list_ms: float = float(Time.get_ticks_usec() - list_started) / 1000.0
	var goals_started: int = Time.get_ticks_usec()
	for agent: GlobalAgent in global_agents:
		AgentGoalEvaluator.evaluate(agent, world, {})
	var goals_ms: float = float(Time.get_ticks_usec() - goals_started) / 1000.0
	print("ALIFE_AGENT_SCAN list_ms=%.2f goals_ms=%.2f" % [list_ms, goals_ms])
	var far_ticks: int = 0
	world.travel.background_enabled = true
	for tick_index: int in range(TICKS):
		world.travel.poll()
		world.simulated_hour += STEP_HOURS
		for index: int in range(systems.size()):
			var started: int = Time.get_ticks_usec()
			if index == 4 or index == 5:
				systems[index].tick(world)
			elif index == 2:
				(systems[index] as AgentTick).tick_staggered(world, STEP_HOURS)
			else:
				systems[index].tick(world, STEP_HOURS)
			(samples[names[index]] as Array).append(float(Time.get_ticks_usec() - started) / 1000.0)
		if (systems[2] as AgentTick)._stagger_phase == 0:
			far_ticks += 1
		world.tick_count += 1
		if tick_index % 6 == 5:
			print("tick=%d caravan_ms=%.2f routes=%d active=%d path_queued=%d path_ready=%d" % [tick_index + 1, (samples["caravans"] as Array).back(), world.routes.all().size(), world.routes.all().filter(func(route: CaravanRoute) -> bool: return route.active).size(), world.travel._requests.size(), world.travel._completed.size()])
	world.travel.shutdown()
	assert(agent_count >= 12000)
	assert(far_ticks == 6, "Far agents must update every 30 simulated seconds")
	print("ALIFE_LOD_PROFILE agents=%d ticks=%d far_ticks=%d" % [agent_count, TICKS, far_ticks])
	for name: String in names:
		var values: Array = samples[name]
		values.sort()
		var total: float = 0.0
		for value: float in values:
			total += value
		print("%s mean_ms=%.2f p95_ms=%.2f max_ms=%.2f" % [name, total / values.size(), values[int(ceil(values.size() * 0.95)) - 1], values.back()])
	get_tree().quit(0)
