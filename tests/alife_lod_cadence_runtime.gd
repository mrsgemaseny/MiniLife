extends Node

const STEP_HOURS: float = Config.LOD_MID_INTERVAL / Config.SECONDS_PER_GAME_HOUR

func _ready() -> void:
	call_deferred("_run")

func _fixture() -> AlifeWorldContext:
	var world: AlifeWorldContext = AlifeWorldContext.new()
	world.seed_world(12345, 6.0)
	for index: int in range(24):
		var agent: GlobalAgent = GlobalAgent.new()
		agent.agent_id = "lod_%02d" % index
		agent.faction_id = "guards"
		agent.role = "guard"
		agent.tile = Vector2i(10 + index, 10)
		agent.home_tile = agent.tile
		world.agents.register(agent)
	return world

func _advance(world: AlifeWorldContext, ticker: AgentTick, count: int) -> void:
	for index: int in range(count):
		world.simulated_hour += STEP_HOURS
		ticker.tick_staggered(world, STEP_HOURS)
		world.tick_count += 1

func _run() -> void:
	var uninterrupted: AlifeWorldContext = _fixture()
	var resumed: AlifeWorldContext = _fixture()
	var bucket_members: Dictionary = {}
	for slot: int in range(AgentTick.STAGGER_BUCKETS):
		for agent: GlobalAgent in uninterrupted.agents.get_global_lod_bucket(slot, AgentTick.STAGGER_BUCKETS):
			assert(not bucket_members.has(agent.agent_id), "Agent appears in two LOD buckets")
			bucket_members[agent.agent_id] = true
	assert(bucket_members.size() == 24, "Every agent belongs to a LOD bucket")
	var first: AgentTick = AgentTick.new()
	var second: AgentTick = AgentTick.new()
	_advance(uninterrupted, first, 3)
	_advance(resumed, second, 3)
	resumed = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(resumed.to_dict())))
	assert(resumed != null)
	var saved_phase: int = second._stagger_phase
	var saved_seen: int = second._stagger_seen
	second = AgentTick.new()
	second._stagger_phase = saved_phase
	second._stagger_seen = saved_seen
	_advance(uninterrupted, first, 9)
	_advance(resumed, second, 9)
	assert(first._stagger_phase == second._stagger_phase and first._stagger_seen == second._stagger_seen)
	assert(JSON.stringify(uninterrupted.agents.to_array()) == JSON.stringify(resumed.agents.to_array()), "Staggered A-Life differs after save continuation")
	for agent: GlobalAgent in resumed.agents.all():
		assert(agent.current_goal == "patrol_settlement" and agent.goal_progress > 0.0)
	print("ALIFE_LOD_CADENCE_PASS agents=%d ticks=12" % resumed.agents.all().size())
	get_tree().quit(0)
