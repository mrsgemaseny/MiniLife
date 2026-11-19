extends Node

const TICKS: int = 144
const SEED_VALUE: int = 12345
const STEP_HOURS: float = WorldSimulation.GLOBAL_TICK_INTERVAL / Config.SECONDS_PER_GAME_HOUR
const LocalWarrants = preload("res://scripts/alife/factions/local_warrants.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var context: AlifeWorldContext = AlifeWorldContext.new()
	context.seed_world(SEED_VALUE, 8.0)
	WorldSeedBuilder.populate(context)
	context.authored_trade_only = WorldData.has_trade_layer()
	CaravanRouteManager.register_authored_routes(context)
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
	var report: Dictionary = {}
	for key: String in phases:
		report[key] = _summary(phases[key])
	var saved_at: int = Time.get_ticks_usec()
	var snapshot: String = JSON.stringify(context.to_dict(), "", true, true)
	var save_ms: float = float(Time.get_ticks_usec() - saved_at) / 1000.0
	print("ALIFE_TICK_PROFILE ", JSON.stringify({"ticks": TICKS, "agents": context.agents.all().size(),
		"sites": context.settlements.all().size(), "active_conflicts": context.conflicts.all().size(),
		"events": context.events.size(), "state_sha256": snapshot.sha256_text(), "snapshot_ms": save_ms, "phases_ms": report}))
	context.travel.shutdown()
	get_tree().quit()


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
