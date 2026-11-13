extends Node

const GLOBAL_TICK_INTERVAL: float = 5.0
const MAX_CATCHUP_DAYS: int = 7
var world: AlifeWorldContext = AlifeWorldContext.new()
var economy_tick: EconomyTick = EconomyTick.new()
var faction_tick: FactionTick = FactionTick.new()
var agent_tick: AgentTick = AgentTick.new()
var rumor_tick: RumorTick = RumorTick.new()
var conflict_tick: ConflictTick = ConflictTick.new()
var caravan_tick: CaravanTick = CaravanTick.new()
var materializer: AgentMaterializer = AgentMaterializer.new()
var pack_materializer: CaravanPackMaterializer = CaravanPackMaterializer.new()
var cargo_ui: CaravanCargoUI
var _cargo_busy: bool = false
var _encounter_views: Dictionary = {}
var _escort_reward_check: bool = false
var _settlement_chunks: Dictionary = {}
var _territorial_claims: Dictionary = {}
var _last_published_event: int = 0
var _last_published_rumor: int = 0
var _initialized: bool = false
var _restored: bool = false
var last_load_error: String = ""
var _unreadable_save: Variant = null
var _trading: bool = false

func _ready() -> void:
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.save_data_requested.connect(_on_save_requested)
	SignalBus.save_data_loaded.connect(_on_save_loaded)
	SignalBus.alife_entity_layer_ready.connect(_on_entity_layer_ready)
	SignalBus.alife_settlement_queried.connect(_on_settlement_queried)
	SignalBus.alife_political_map_queried.connect(_on_political_map_queried)
	SignalBus.fog_batch_updated.connect(_on_political_visibility_changed)
	SignalBus.chunk_loaded.connect(func(chunk: Vector2i) -> void:
		materializer.loaded_chunks[chunk] = true
	)
	SignalBus.chunk_unloaded.connect(materializer.unload_chunk)
	SignalBus.player_tile_changed.connect(func(tile: Vector2i) -> void: materializer.player_tile = tile)
	SignalBus.entity_died.connect(_on_entity_died)
	SignalBus.alife_combat_target_queried.connect(_on_combat_target_queried)
	SignalBus.alife_market_queried.connect(_on_market_queried)
	SignalBus.alife_trade_requested.connect(_on_trade_requested)
	SignalBus.local_amnesty_requested.connect(_on_local_amnesty_requested)
	SignalBus.refugee_aid_requested.connect(_on_refugee_aid_requested)
	SignalBus.alife_cargo_open_requested.connect(_on_cargo_open_requested)
	SignalBus.alife_cargo_queried.connect(_on_cargo_queried)
	SignalBus.alife_cargo_take_requested.connect(_on_cargo_take_requested)
	SignalBus.agent_materialized.connect(_on_agent_materialized)
	SignalBus.alife_resident_spoken_to.connect(_on_resident_spoken_to)
	SignalBus.alife_escort_accept_requested.connect(_on_escort_accept_requested)
	cargo_ui = CaravanCargoUI.new()
	add_child(cargo_ui)

func _exit_tree() -> void:
	world.travel.shutdown()

var _body_scan_elapsed: float = 0.0
var _refugee_camp_views: Dictionary = {}

func _process(_delta: float) -> void:
	if not _initialized or GameManager.is_paused() or GameManager.is_dead():
		return
	world.travel.background_enabled = true
	world.travel.poll()
	materializer.update(_delta)
	_body_scan_elapsed += _delta
	if _body_scan_elapsed >= 1.0:
		_body_scan_elapsed = 0.0
		_discover_resident_bodies()
		_sync_refugee_camp_views()
	_materialize_encounters()
	pack_materializer.update(materializer.loaded_chunks, materializer.player_tile)
	_sync_caravan_hostile_visibility()
	var clock_hour: float = float(GameManager.get_day() - 1) * 24.0 + GameManager.get_hour()
	EscortContracts.observe(world, materializer.player_tile, clock_hour)
	if _escort_reward_check:
		_claim_escort_rewards()
	_publish_events()
	var target: float = float(GameManager.get_day() - 1) * 24.0 + GameManager.get_hour()
	var step: float = GLOBAL_TICK_INTERVAL / Config.SECONDS_PER_GAME_HOUR
	# Limit work per frame; preserve pending game time rather than dropping ticks.
	var count: int = 0
	while target - world.simulated_hour >= step and count < 8:
		_run_global_tick(step)
		count += 1

const LocalWarrants = preload("res://scripts/alife/factions/local_warrants.gd")

func _run_global_tick(hours: float, silent: bool = false) -> void:
	world.simulated_hour += hours
	economy_tick.tick(world, hours)
	faction_tick.tick(world, hours)
	agent_tick.tick(world, hours)
	conflict_tick.tick(world, hours)
	caravan_tick.tick(world)
	rumor_tick.tick(world)
	LocalWarrants.tick(world)
	materializer.reconcile_dead()
	world.tick_count += 1
	if not silent:
		_sample_observed_armies()
		_publish_events()
		SignalBus.world_tick_completed.emit()
		_publish_markets()

var _agent_save_delta: AlifeAgentSaveDelta = preload("res://scripts/alife/agent_save_delta.gd").new()

func _on_game_started(seed_value: int, _slot: String, is_new: bool) -> void:
	for view: Variant in _refugee_camp_views.values():
		if is_instance_valid(view):
			view.queue_free()
	_refugee_camp_views.clear()
	for body: Node in get_tree().get_nodes_in_group("corpses"):
		if body is CorpseEntity and not body.resident_id.is_empty():
			body.queue_free()
	world.travel.shutdown()
	if not is_new and not last_load_error.is_empty():
		return
	if is_new:
		last_load_error = ""
		_unreadable_save = null
	if is_new or not _restored:
		world = AlifeWorldContext.new()
		world.seed_world(seed_value, float(GameManager.get_day() - 1) * 24.0 + GameManager.get_hour())
		WorldSeedBuilder.populate(world)
		_agent_save_delta.capture(world, Config.TERRAIN_GEOGRAPHY_SIZE)
		agent_tick = AgentTick.new()
	materializer.reset(world)
	_encounter_views.clear()
	_escort_reward_check = true
	pack_materializer.reset(world)
	if cargo_ui != null:
		cargo_ui.close_panel()
	_index_settlements()
	if is_new:
		_assign_district_homes()
	_last_published_event = world.next_event_id - 1
	_last_published_rumor = world.next_event_id - 1
	_initialized = true
	_restored = false
	_publish_markets()

func _on_save_requested(bundle: Dictionary) -> void:
	if not _initialized:
		if _unreadable_save != null:
			var preserved: Dictionary = bundle.get("world", {})
			preserved["alife"] = _unreadable_save
			bundle["world"] = preserved
		return
	var saved_world: Dictionary = bundle.get("world", {})
	materializer.sync_all()
	pack_materializer.sync_all()
	var snapshot: Dictionary = _agent_save_delta.encode(world)
	snapshot["agent_tick_elapsed"] = agent_tick._elapsed
	saved_world["alife"] = snapshot
	bundle["world"] = saved_world

func _on_save_loaded(bundle: Dictionary) -> void:
	var saved_world: Dictionary = bundle.get("world", {})
	_restored = false
	_initialized = false
	last_load_error = ""
	_unreadable_save = null
	if not saved_world.has("alife"):
		return
	_unreadable_save = saved_world["alife"]
	if not saved_world["alife"] is Dictionary:
		last_load_error = "Invalid A-Life save payload; original data has been preserved."
		SignalBus.notification_posted.emit(last_load_error)
		return
	var data: Dictionary = saved_world["alife"]
	var codec: AlifeAgentSaveDelta = preload("res://scripts/alife/agent_save_delta.gd").new()
	var restored: AlifeWorldContext = codec.decode(data, int(saved_world.get("terrain_geography_size", 256)))
	if restored == null:
		last_load_error = "Unsupported or invalid A-Life save; simulation is disabled and original data has been preserved."
		SignalBus.notification_posted.emit(last_load_error)
		return
	var reference_error: String = preload("res://scripts/alife/save_reference_validator.gd").validate(restored)
	if not reference_error.is_empty():
		restored.travel.shutdown()
		last_load_error = "Invalid A-Life references. Original save preserved. " + reference_error
		SignalBus.notification_posted.emit(last_load_error)
		return
	_unreadable_save = null
	world.travel.shutdown()
	world = restored
	_agent_save_delta = codec
	agent_tick = AgentTick.new()
	agent_tick._elapsed = float(data.get("agent_tick_elapsed", 0.0))
	_restored = true

func _on_entity_layer_ready(layer: Node2D) -> void:
	materializer.parent = layer
	pack_materializer.parent = layer

func _index_settlements() -> void:
	_settlement_chunks.clear()
	for settlement: AlifeSettlement in world.settlements.all():
		_settlement_chunks[Config.tile_to_chunk(settlement.tile)] = settlement.settlement_id
	var terrain: TerrainGenerator = TerrainGenerator.new(world.world_seed)
	for settlement: AlifeSettlement in world.settlements.all():
		if settlement.settlement_type not in ["city", "fortress"]:
			continue
		var center: Vector2i = Config.tile_to_chunk(settlement.tile)
		for direction: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var chunk: Vector2i = center + direction
			if _settlement_chunks.has(chunk) or not _district_has_land(terrain, chunk):
				continue
			var connector: Vector2i = settlement.tile + direction
			var dry_entrance: bool = true
			while Config.tile_to_chunk(connector) == center:
				if terrain.get_biome_at(connector) in ["water", "mountains"]:
					dry_entrance = false
					break
				if settlement.street_plan > 0:
					var lane: Vector2i = Vector2i.LEFT if direction.y != 0 else Vector2i.UP
					if terrain.get_biome_at(connector + lane) in ["water", "mountains"]:
						dry_entrance = false
						break
				connector += direction
			if not dry_entrance:
				continue
			if not PoiGenerator.get_fixed_ruin_for_chunk(world.world_seed, chunk).is_empty():
				continue
			_settlement_chunks[chunk] = settlement.settlement_id
		for offset: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var chunk: Vector2i = center + offset
			if _settlement_chunks.has(chunk):
				continue
			if _settlement_chunks.get(center + Vector2i(offset.x, 0)) != settlement.settlement_id:
				continue
			if _settlement_chunks.get(center + Vector2i(0, offset.y)) != settlement.settlement_id:
				continue
			if not _district_has_land(terrain, chunk) or not PoiGenerator.get_fixed_ruin_for_chunk(world.world_seed, chunk).is_empty():
				continue
			_settlement_chunks[chunk] = settlement.settlement_id

	# Grow from the dry inner districts, so every outer district has a route to the center.
	for settlement: AlifeSettlement in world.settlements.all():
		if settlement.street_plan < 2:
			continue
		var center: Vector2i = Config.tile_to_chunk(settlement.tile)
		var frontier: Array[Vector2i] = []
		for offset_x: int in range(-1, 2):
			for offset_y: int in range(-1, 2):
				var chunk: Vector2i = center + Vector2i(offset_x, offset_y)
				if chunk != center and _settlement_chunks.get(chunk) == settlement.settlement_id:
					frontier.append(chunk)
		var index: int = 0
		var limit: int = 33 if settlement.settlement_type == "city" else 25
		while index < frontier.size() and frontier.size() + 1 < limit:
			var source: Vector2i = frontier[index]
			index += 1
			for normal: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
				var chunk: Vector2i = source + normal
				var offset: Vector2i = (chunk - center).abs()
				if maxi(offset.x, offset.y) > 3 or offset.x + offset.y > 5:
					continue
				if _settlement_chunks.has(chunk) or not _district_has_land(terrain, chunk):
					continue
				if not PoiGenerator.get_fixed_ruin_for_chunk(world.world_seed, chunk).is_empty():
					continue
				_settlement_chunks[chunk] = settlement.settlement_id
				frontier.append(chunk)
				if frontier.size() + 1 == limit:
					break

	_territorial_claims = preload("res://scripts/alife/settlements/territorial_claims.gd").build(world.settlements.all(), _settlement_chunks, terrain)

func _district_has_land(terrain: TerrainGenerator, chunk: Vector2i) -> bool:
	var origin: Vector2i = Config.chunk_origin(chunk)
	for x: int in range(Config.CHUNK_SIZE):
		for y: int in range(Config.CHUNK_SIZE):
			var tile: Vector2i = origin + Vector2i(x, y)
			if not terrain.is_in_world(tile) or terrain.get_biome_at(tile) in ["water", "mountains"]:
				return false
	return true

func _assign_district_homes() -> void:
	var homes: Dictionary = {}
	for chunk: Vector2i in _settlement_chunks:
		var id: String = _settlement_chunks[chunk]
		var settlement: AlifeSettlement = world.settlements.find(id) as AlifeSettlement
		var center: Vector2i = Config.tile_to_chunk(settlement.tile)
		if chunk == center:
			if settlement.street_plan >= 3:
				var lord: GlobalAgent = world.agents.find(id + "/resident/0000") as GlobalAgent
				var layout: Dictionary = SettlementLayout.describe(settlement)
				if lord != null and layout.streets.has("lord_home"):
					lord.home_tile = layout.streets.lord_home
			continue
		var direction: Vector2i = chunk - center
		var crossing: Vector2i = settlement.tile + direction * Config.CHUNK_SIZE
		if not homes.has(id):
			homes[id] = []
		var along_street: Vector2i = Vector2i.RIGHT if direction.y != 0 else Vector2i.DOWN
		for step: int in range(-3, 4):
			homes[id].append(crossing + along_street * step)
	for id: String in homes:
		var places: Array = homes[id]
		var index: int = 0
		for agent: GlobalAgent in world.agents.by_settlement(id):
			if agent.unique or agent.role != "civilian":
				continue
			index += 1
			if index % 3 != 0:
				var home: Vector2i = places[index % places.size()]
				agent.tile = home
				agent.home_tile = home

func _on_political_visibility_changed(changes: Array) -> void:
	if not _initialized:
		return
	var known: Dictionary = world.narrative.get("political_intel", {})
	var territory: Dictionary = world.narrative.get("political_territory", {})
	var seen_chunks: Dictionary = {}
	for change: Dictionary in changes:
		if int(change.get("state", 0)) != WorldSystem.FogState.VISIBLE:
			continue
		var tile: Vector2i = change["pos"]
		var chunk: Vector2i = Config.tile_to_chunk(tile)
		var id: String = str(_territorial_claims.get(chunk, ""))
		if id.is_empty():
			continue
		var settlement: AlifeSettlement = world.settlements.find(id) as AlifeSettlement
		if settlement == null:
			continue
		if not seen_chunks.has(chunk):
			seen_chunks[chunk] = true
			_observe_territorial_chunk(chunk, tile, settlement, territory)
		if settlement.tile == tile:
			_observe_political_settlement(settlement, known)
	world.narrative["political_intel"] = known
	world.narrative["political_territory"] = territory
	_sample_observed_armies()

func _observe_territorial_chunk(chunk: Vector2i, tile: Vector2i, settlement: AlifeSettlement, territory: Dictionary) -> void:
	var key: String = Config.vec2i_to_key(chunk)
	var faction: AlifeFaction = world.factions.find(settlement.owner_faction) as AlifeFaction
	var settled: bool = _settlement_chunks.has(chunk)
	if not settled and (faction == null or settlement.status != AlifeSettlement.Status.NORMAL):
		territory.erase(key)
		return
	territory[key] = {
		"chunk": [chunk.x, chunk.y], "sample": [tile.x, tile.y], "district": settled,
		"color": faction.color.to_html() if faction != null and settlement.status == AlifeSettlement.Status.NORMAL else Color.GRAY.to_html(),
	}

func _sample_observed_armies() -> void:
	if not _initialized:
		return
	var tracks: Dictionary = world.narrative.get("political_armies", {})
	var observed: Dictionary = {}
	var player_tile: Vector2i = GameManager.get_player_tile()
	for conflict: AlifeConflict in world.conflicts.all():
		if conflict.resolved or conflict.phase not in ["marching", "siege", "assault"]:
			continue
		var visible_tile: Vector2i = Vector2i(-1, -1)
		var witness_id: String = ""
		for id: String in conflict.attacker_agents:
			var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
			if agent == null or not agent.alive or agent.deployment_id != conflict.conflict_id:
				continue
			if Config.tile_distance(agent.tile, player_tile) > 60:
				continue
			var info: Dictionary = {}
			SignalBus.world_tile_queried.emit(agent.tile, info)
			if int(info.get("fog_state", 0)) == WorldSystem.FogState.VISIBLE:
				visible_tile = agent.tile
				witness_id = id
				break
		if visible_tile.x < 0:
			continue
		var id: String = conflict.conflict_id
		observed[id] = true
		var faction: AlifeFaction = world.factions.find(conflict.attacker_id) as AlifeFaction
		var track: Dictionary = tracks.get(id, {"points": [], "continuous": false})
		var points: Array = track["points"]
		var coords: Array = [visible_tile.x, visible_tile.y]
		var same_agent: bool = witness_id == str(track.get("witness_id", ""))
		if points.is_empty() or not bool(track["continuous"]) or not same_agent or points.back()["tile"] != coords:
			var joined: bool = false
			if not points.is_empty() and bool(track["continuous"]) and same_agent:
				var previous: Array = points.back()["tile"]
				joined = Config.tile_distance(Vector2i(previous[0], previous[1]), visible_tile) == 1
			points.append({"tile": coords, "joined": joined})
			if points.size() > 32:
				points.pop_front()
		track["faction"] = faction.name if faction != null else conflict.attacker_id
		track["color"] = faction.color.to_html() if faction != null else Color.GRAY.to_html()
		track["observed_hour"] = world.simulated_hour
		track["continuous"] = true
		track["witness_id"] = witness_id
		tracks[id] = track
	for id: String in tracks.keys():
		if world.simulated_hour - float(tracks[id]["observed_hour"]) > 48.0:
			tracks.erase(id)
		elif not observed.has(id):
			tracks[id]["continuous"] = false
	world.narrative["political_armies"] = tracks

func _observe_political_settlement(settlement: AlifeSettlement, known: Dictionary) -> void:
	var faction: AlifeFaction = world.factions.find(settlement.owner_faction) as AlifeFaction
	var fronts: Array[String] = []
	for conflict: AlifeConflict in world.conflicts.all():
		if not conflict.resolved and conflict.target_settlement == settlement.settlement_id and conflict.phase in ["siege", "assault"]:
			var attacker: AlifeFaction = world.factions.find(conflict.attacker_id) as AlifeFaction
			fronts.append(attacker.name if attacker != null else conflict.attacker_id)
	known[settlement.settlement_id] = {
		"tile": [settlement.tile.x, settlement.tile.y],
		"name": settlement.name,
		"faction": faction.name if faction != null else "Independent",
		"color": faction.color.to_html() if faction != null else Color.GRAY.to_html(),
		"status": settlement.status,
		"fronts": fronts,
		"observed_hour": world.simulated_hour,
	}

func _on_political_map_queried(result: Dictionary) -> void:
	if not _initialized:
		return
	var known: Dictionary = world.narrative.get("political_intel", {})
	for settlement: AlifeSettlement in world.settlements.all():
		if Config.tile_distance(settlement.tile, GameManager.get_player_tile()) > 60:
			continue
		var info: Dictionary = {}
		SignalBus.world_tile_queried.emit(settlement.tile, info)
		if int(info.get("fog_state", 0)) == WorldSystem.FogState.VISIBLE:
			_observe_political_settlement(settlement, known)
	world.narrative["political_intel"] = known
	_collect_political_rumors(known)
	result["settlements"] = known.values().duplicate(true)
	var territory: Dictionary = world.narrative.get("political_territory", {})
	for key: String in territory.keys():
		var sample: Array = territory[key].get("sample", [])
		if sample.size() != 2:
			continue
		var tile: Vector2i = Vector2i(sample[0], sample[1])
		if Config.tile_distance(tile, GameManager.get_player_tile()) > 60:
			continue
		var info: Dictionary = {}
		SignalBus.world_tile_queried.emit(tile, info)
		if int(info.get("fog_state", 0)) != WorldSystem.FogState.VISIBLE:
			continue
		var chunk: Vector2i = Config.tile_to_chunk(tile)
		var settlement: AlifeSettlement = world.settlements.find(str(_territorial_claims.get(chunk, ""))) as AlifeSettlement
		if settlement != null:
			_observe_territorial_chunk(chunk, tile, settlement, territory)
	result["territory"] = territory.values().duplicate(true)
	_sample_observed_armies()
	var tracks: Dictionary = world.narrative.get("political_armies", {})
	result["armies"] = tracks.values().duplicate(true)

func _collect_political_rumors(known: Dictionary) -> void:
	var local_id: String = str(_settlement_chunks.get(Config.tile_to_chunk(GameManager.get_player_tile()), ""))
	if local_id.is_empty():
		return
	var local: AlifeSettlement = world.settlements.find(local_id) as AlifeSettlement
	if local == null or local.status in [AlifeSettlement.Status.RAZED, AlifeSettlement.Status.RUINS]:
		return
	var known_by_tile: Dictionary = {}
	for entry: Dictionary in known.values():
		known_by_tile[entry["tile"]] = entry
	for rumor: Dictionary in world.rumors:
		var type: String = str(rumor.get("event_type", ""))
		if type not in ["settlement_captured", "settlement_razed", "siege_started", "battle_resolved", "peace_declared"]:
			continue
		var entry: Dictionary = known_by_tile.get(rumor.get("origin_tile", []), {})
		if entry.is_empty():
			continue
		var reception: Dictionary = rumor.get("received_at", {}).get(local_id, {})
		if reception.is_empty():
			continue
		var timestamp: float = float(rumor.get("created_hour", 0.0))
		var previous: Dictionary = entry.get("rumor", {})
		if timestamp <= float(entry.get("observed_hour", 0.0)) or int(rumor["event_id"]) <= int(previous.get("event_id", 0)):
			continue
		entry["rumor"] = {
			"event_id": int(rumor["event_id"]), "content": str(reception.get("content", "")),
			"source": local.name, "heard_hour": world.simulated_hour,
		}

func _on_settlement_queried(chunk: Vector2i, result: Dictionary) -> void:
	if not _initialized or not _settlement_chunks.has(chunk):
		return
	var settlement: AlifeSettlement = world.settlements.find(_settlement_chunks[chunk]) as AlifeSettlement
	if settlement != null and chunk == Config.tile_to_chunk(settlement.tile):
		result.merge({
			"settlement_id": settlement.settlement_id,
			"poi_id": "merchant_outpost",
			"name": settlement.name,
			"tile_pos": settlement.tile,
			"settlement_tile": settlement.tile,
		})

func _on_entity_died(entity: Node, killer_id: String) -> void:
	if entity is CaravanPackAnimal:
		var pack: CaravanPackAnimal = entity as CaravanPackAnimal
		var route: CaravanRoute = world.routes.find(pack.route_id) as CaravanRoute
		if route != null and killer_id == "player":
			_mark_caravan_raid(route, Config.iso_to_world(pack.global_position))
		pack_materializer.on_death(pack)
		return
	if entity == null or not entity.has_meta("global_agent_id"):
		return
	var id: String = str(entity.get_meta("global_agent_id"))
	var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
	if agent == null or not agent.alive:
		return
	materializer._sync(id, entity as NPCBase)
	agent.alive = false
	agent.health = 0.0
	var settlement: AlifeSettlement = world.settlements.find(agent.settlement_id) as AlifeSettlement
	if settlement != null:
		settlement.population = maxi(0, settlement.population - 1)
		if agent.role == "guard":
			settlement.garrison = maxi(0, settlement.garrison - 1)
	world.record_event("agent_died", agent.tile, [id], {"killer": killer_id})
	_spawn_resident_body(entity as NPCBase, agent)
	if killer_id == "player" and not entity.is_in_group("enemies"):
		_record_killing_witnesses(agent)
	FactionSuccession.leader_died(world, agent.faction_id, id)

func _sync_refugee_camp_views() -> void:
	if not is_instance_valid(materializer.parent):
		return
	var camps: Dictionary = world.narrative.get("refugee_camps", {})
	var visible_camps: Dictionary = {}
	for id: String in camps:
		var row: Dictionary = camps[id]
		var coords: Array = row["tile"]
		var tile: Vector2i = Vector2i(coords[0], coords[1])
		if not materializer.loaded_chunks.has(Config.tile_to_chunk(tile)):
			continue
		var info: Dictionary = {}
		SignalBus.world_tile_queried.emit(tile, info)
		if int(info.get("fog_state", 0)) != WorldSystem.FogState.VISIBLE:
			continue
		visible_camps[id] = true
		var view: Node2D = _refugee_camp_views.get(id) as Node2D
		if not is_instance_valid(view):
			view = preload("res://scripts/alife/settlements/refugee_camp_view.gd").new()
			view.set("camp_id", id)
			view.position = materializer.parent.to_local(Config.world_to_iso(tile))
			materializer.parent.add_child(view)
			_refugee_camp_views[id] = view
		view.show_residents(row["members"].size())
	for id: String in _refugee_camp_views.keys():
		if visible_camps.has(id):
			continue
		var view: Node2D = _refugee_camp_views[id]
		if is_instance_valid(view):
			view.queue_free()
		_refugee_camp_views.erase(id)

func _on_refugee_aid_requested(camp_id: String, actor: Node, item_id: String, result: Dictionary) -> void:
	if not _initialized or not is_instance_valid(actor) or not actor is Player or not actor.is_alive():
		return
	var view: Variant = _refugee_camp_views.get(camp_id)
	if not is_instance_valid(view) or view.is_queued_for_deletion() or not InteractionPicker.in_reach(actor, view):
		return
	var camp: Dictionary = world.narrative.get("refugee_camps", {}).get(camp_id, {})
	if camp.is_empty() or camp["members"].is_empty():
		return
	var food_limit: float = float(camp["members"].size()) * 3.0
	if float(camp.get("food", 0.0)) >= food_limit:
		result["message"] = "The camp already has enough food."
		return
	if item_id.is_empty():
		for slot: Dictionary in actor.inventory.slots:
			var candidate: String = str(slot.get("item_id", ""))
			var def: Dictionary = DataRegistry.get_item(candidate)
			if str(def.get("type", "")) == "food" and float(def.get("stats", {}).get("nutrition", 0.0)) > 0.0:
				result["offer_item"] = candidate
				result["message"] = "Лагерь беженцев: нажмите ПКМ ещё раз, чтобы передать 1 %s." % str(def.get("name", candidate))
				return
		result["message"] = "The refugees need food."
		return
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var nutrition: float = float(definition.get("stats", {}).get("nutrition", 0.0))
	if str(definition.get("type", "")) != "food" or nutrition <= 0.0 or actor.inventory.remove_item(item_id, 1) != 1:
		result["message"] = "That food is no longer available."
		return
	camp["food"] = float(camp.get("food", 0.0)) + nutrition / 10.0
	world.record_event("refugee_aid_delivered", Config.iso_to_world(view.global_position), ["player"], {"item": item_id})
	result["ok"] = true
	result["message"] = "The refugees share the food you donated."

func _spawn_resident_body(entity: NPCBase, agent: GlobalAgent) -> void:
	var parent: Node = entity.get_parent()
	if parent == null:
		return
	var body: CorpseEntity = CorpseEntity.new()
	body.species = "resident"
	body.resident_id = agent.agent_id
	body.settlement_id = agent.settlement_id
	body.faction_id = agent.faction_id
	body.position = entity.position
	parent.add_child(body)

func _discover_resident_bodies() -> void:
	for node: Node in get_tree().get_nodes_in_group("corpses"):
		var body: CorpseEntity = node as CorpseEntity
		if body == null or body.resident_id.is_empty() or body.is_queued_for_deletion():
			continue
		var tile: Vector2i = Config.iso_to_world(body.global_position)
		for id: String in world.agents.materialized:
			var reference: Variant = world.agents.materialized[id]
			if not is_instance_valid(reference):
				continue
			var npc: NPCBase = reference as NPCBase
			var witness: GlobalAgent = world.agents.find(id) as GlobalAgent
			if witness == null or not witness.alive or not npc.is_alive():
				continue
			if witness.settlement_id != body.settlement_id and witness.faction_id != body.faction_id:
				continue
			var witness_tile: Vector2i = Config.iso_to_world(npc.global_position)
			if Config.tile_distance(witness_tile, tile) > 6 or not _witness_has_sight(witness_tile, tile):
				continue
			if witness.memories.any(func(row: Dictionary) -> bool: return row.get("subject_id") == body.resident_id and row.get("event_type") in ["found_body", "witnessed_killing"]):
				continue
			var memory: AlifeMemoryEvent = AlifeMemoryEvent.new()
			memory.event_type = "found_body"
			memory.location = tile
			memory.day = GameManager.get_day()
			memory.witness_id = id
			memory.subject_id = body.resident_id
			memory.sentiment = -10
			witness.memories.append(memory.to_dict())
			witness.morale = maxf(0.0, witness.morale - 0.1)
			npc.notice_body(body.global_position)

func _record_killing_witnesses(victim: GlobalAgent) -> void:
	var witnesses: Array[String] = []
	for id: String in world.agents.materialized:
		var reference: Variant = world.agents.materialized[id]
		if not is_instance_valid(reference) or id == victim.agent_id:
			continue
		var npc: NPCBase = reference as NPCBase
		var witness: GlobalAgent = world.agents.find(id) as GlobalAgent
		if witness == null or not witness.alive or not npc.is_alive():
			continue
		if witness.settlement_id != victim.settlement_id and witness.faction_id != victim.faction_id:
			continue
		var tile: Vector2i = Config.iso_to_world(npc.global_position)
		if Config.tile_distance(tile, victim.tile) > 8 or not _witness_has_sight(tile, victim.tile):
			continue
		if witness.grudges.any(func(row: Dictionary) -> bool: return row.get("victim") == victim.agent_id):
			continue
		witness.grudges.append({"reason": "witnessed_killing", "victim": victim.agent_id, "hour": world.simulated_hour})
		var memory: AlifeMemoryEvent = AlifeMemoryEvent.new()
		memory.event_type = "witnessed_killing"
		memory.location = victim.tile
		memory.day = GameManager.get_day()
		memory.witness_id = id
		memory.subject_id = victim.agent_id
		memory.sentiment = -35
		memory.permanent = true
		witness.memories.append(memory.to_dict())
		npc.memory.remember("witnessed_killing", "player", memory.sentiment, memory.day)
		witness.relation_to_player = npc.memory.personal_opinion_of_player
		witness.memory_state = npc.memory.to_dict()
		witnesses.append(id)
		if witness.role in ["guard", "soldier", "caravan_guard"]:
			_on_agent_materialized(id, npc)
		else:
			npc.frighten_for(8.0)
		SignalBus.npc_grudge_added.emit(id, "witnessed_killing")
	if not witnesses.is_empty():
		LocalWarrants.file_report(world, victim, witnesses)
		world.record_event("killing_witnessed", victim.tile, ["player"], {
			"victim": victim.agent_id, "witnesses": witnesses, "settlement_id": victim.settlement_id,
		})

func _on_resident_spoken_to(agent_id: String) -> void:
	if not _initialized:
		return
	var resident: GlobalAgent = world.agents.find(agent_id) as GlobalAgent
	var reference: Variant = world.agents.materialized.get(agent_id)
	if resident == null or not resident.alive or not is_instance_valid(reference):
		return
	var tile: Vector2i = Config.iso_to_world(reference.global_position)
	var local_id: String = str(_settlement_chunks.get(Config.tile_to_chunk(tile), ""))
	var settlement: AlifeSettlement = world.settlements.find(local_id) as AlifeSettlement
	if settlement == null or settlement.status in [AlifeSettlement.Status.RAZED, AlifeSettlement.Status.RUINS]:
		return
	var heard: Dictionary = world.narrative.get("heard_rumors", {})
	for key: String in heard.keys():
		if world.simulated_hour - float(heard[key]) > 24.0 * 15.0:
			heard.erase(key)
	for row: Dictionary in BulletinBoard.get_rumors_at(world, local_id):
		var key: String = str(row["rumor_id"])
		if heard.has(key):
			continue
		heard[key] = world.simulated_hour
		world.narrative["heard_rumors"] = heard
		SignalBus.local_rumor_heard.emit(settlement.name, str(row["content"]))
		SignalBus.notification_posted.emit("Rumor: " + str(row["content"]))
		break

func _witness_has_sight(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var steps: int = Config.tile_distance(from_tile, to_tile)
	for step: int in range(1, steps):
		var tile: Vector2i = Vector2i(Vector2(from_tile).lerp(Vector2(to_tile), float(step) / steps).round())
		var info: Dictionary = {}
		SignalBus.world_tile_queried.emit(tile, info)
		var structure: String = str(info.get("structure_id", ""))
		if structure in ["wall", "wood_wall", "stone_wall"]:
			return false
		if structure in ["door", "wood_door"]:
			var door_state: Dictionary = {}
			SignalBus.door_state_queried.emit(tile, door_state)
			if not bool(door_state.get("open", false)):
				return false
	return true

func _publish_events() -> void:
	for row: Dictionary in world.events.duplicate():
		var id: int = int(row.get("event_id", 0))
		if id <= _last_published_event:
			continue
		_last_published_event = id
		var event: AlifeWorldEvent = AlifeWorldEvent.from_dict(row)
		SignalBus.world_event_occurred.emit(event.event_type, event.location, event.participants)
		SignalBus.alife_event_published.emit(row.duplicate(true))
		if event.event_type == "local_warrant_issued":
			var settlement: AlifeSettlement = world.settlements.find(str(event.data.get("settlement_id", ""))) as AlifeSettlement
			if settlement != null and Config.tile_distance(settlement.tile, GameManager.get_player_tile()) <= 24:
				SignalBus.notification_posted.emit("%s has issued a local warrant." % settlement.name)
		if event.participants.size() >= 2:
			if event.event_type == "war_declared":
				SignalBus.faction_at_war.emit(str(event.participants[0]), str(event.participants[1]))
			elif event.event_type == "peace_declared":
				SignalBus.faction_peace_declared.emit(str(event.participants[0]), str(event.participants[1]))
		if event.event_type in ["settlement_status_changed", "settlement_captured", "settlement_independent"]:
			var settlement_id: String = str(event.data.get("settlement_id", ""))
			var settlement: AlifeSettlement = world.settlements.find(settlement_id) as AlifeSettlement
			if settlement != null:
				SignalBus.settlement_status_changed.emit(settlement_id, settlement.status)
		elif event.event_type == "faction_collapsed" and not event.participants.is_empty():
			SignalBus.faction_collapsed.emit(str(event.participants[0]))
		elif event.event_type == "leader_died" and event.participants.size() >= 2:
			SignalBus.faction_leader_died.emit(str(event.participants[0]), str(event.participants[1]))
		if event.event_type.begins_with("caravan_"):
			SignalBus.caravan_event.emit(str(event.data.get("route_id", "")), event.event_type, event.location)
			if event.event_type == "caravan_arrived":
				SignalBus.caravan_trip_completed.emit(str(event.data.get("home_id", "")), int(event.data.get("trips", 0)), bool(event.data.get("roi", false)))
		if event.event_type == "escort_completed":
			_escort_reward_check = true
	for row: Dictionary in world.rumors:
		var id: int = int(row.get("rumor_id", 0))
		if id > _last_published_rumor:
			_last_published_rumor = id
			var rumor: RumorEntry = RumorEntry.from_dict(row)
			SignalBus.rumor_created.emit(rumor.content, rumor.origin_tile)
	if _escort_reward_check:
		_claim_escort_rewards()
	world.compact_events(_last_published_event)

func _on_combat_target_queried(agent_id: String, result: Dictionary) -> void:
	var reference: Variant = world.agents.materialized.get(agent_id)
	var source: NPCBase = reference as NPCBase if is_instance_valid(reference) else null
	if not is_instance_valid(source) or not source.is_alive():
		return
	var agent: GlobalAgent = world.agents.find(agent_id) as GlobalAgent
	if agent != null and agent.role in ["guard", "soldier", "caravan_guard"]:
		var jurisdiction: AlifeSettlement = world.settlements.find(agent.settlement_id) as AlifeSettlement
		var player_tile: Vector2i = GameManager.get_player_tile()
		if jurisdiction != null and jurisdiction.owner_faction == agent.faction_id \
				and _territorial_claims.get(Config.tile_to_chunk(player_tile)) == jurisdiction.settlement_id \
				and LocalWarrants.is_active(world, jurisdiction):
			var wanted: Node2D = get_tree().get_first_node_in_group("player") as Node2D
			if is_instance_valid(wanted) and source.global_position.distance_to(wanted.global_position) <= 500.0:
				result["target"] = wanted
				return
		for grudge: Dictionary in agent.grudges:
			if str(grudge.get("reason", "")) in ["caravan_raid", "witnessed_killing"]:
				var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
				if is_instance_valid(player) and source.global_position.distance_to(player.global_position) <= 500.0:
					result["target"] = player
					return
	var best: float = INF
	if agent != null:
		var route_id: String = agent.ambush_route_id if not agent.ambush_route_id.is_empty() else agent.caravan_id
		var route: CaravanRoute = world.routes.find(route_id) as CaravanRoute
		if route != null and route.ambush_phase == "active":
			var opponents: Array = route.guards + [route.merchant_id] if route.ambushers.has(agent_id) else route.ambushers
			for other_id: String in opponents:
				var candidate_reference: Variant = world.agents.materialized.get(other_id)
				if not is_instance_valid(candidate_reference):
					continue
				var candidate: NPCBase = candidate_reference as NPCBase
				var distance: float = source.global_position.distance_squared_to(candidate.global_position)
				if candidate.is_alive() and distance < best:
					best = distance
					result["target"] = candidate
			if result.has("target"):
				result["flee_only"] = agent.role == "trader"
				return
	for conflict: AlifeConflict in world.conflicts.all():
		if conflict.resolved or conflict.phase != "siege":
			continue
		var opponents: Array = []
		if conflict.attacker_agents.has(agent_id):
			opponents = conflict.defender_agents
		elif conflict.defender_agents.has(agent_id):
			opponents = conflict.attacker_agents
		for other_id: String in opponents:
			var target_reference: Variant = world.agents.materialized.get(other_id)
			var target: NPCBase = target_reference as NPCBase if is_instance_valid(target_reference) else null
			if not is_instance_valid(target) or not target.is_alive():
				continue
			var distance: float = source.global_position.distance_squared_to(target.global_position)
			if distance < best:
				best = distance
				result["target"] = target

func _publish_markets() -> void:
	var markets: Dictionary = {}
	for settlement: AlifeSettlement in world.settlements.all():
		markets[settlement.settlement_id] = _market_data(settlement)
	SignalBus.alife_market_snapshot.emit(markets)

func _market_data(settlement: AlifeSettlement) -> Dictionary:
	return {"id": settlement.settlement_id, "name": settlement.name, "is_city": settlement.settlement_type in ["town", "city", "fortress"], "treasury": settlement.treasury, "caravan_trips": settlement.caravan_successes, "is_roi_achieved": settlement.stock_tier >= 3, "stock_tier": settlement.stock_tier, "prosperity": settlement.prosperity, "food": settlement.food, "stockpile": settlement.stockpile.duplicate(), "faction_id": settlement.owner_faction, "population": settlement.population, "items": MarketPricing.items(settlement), "managed": true}

func _on_market_queried(trader: Node, result: Dictionary) -> void:
	if not _initialized or not is_instance_valid(trader):
		return
	if trader.is_queued_for_deletion() or (trader.has_method("is_alive") and not bool(trader.call("is_alive"))):
		result.merge({"managed": true, "closed": true, "items": {}})
		return
	var id: String = str(trader.get_meta("settlement_id", ""))
	var settlement: AlifeSettlement = world.settlements.find(id) as AlifeSettlement
	if settlement == null and trader is Node2D:
		var tile: Vector2i = Config.iso_to_world((trader as Node2D).global_position)
		var distance: float = 12.0
		for candidate: AlifeSettlement in world.settlements.all():
			var candidate_distance: float = Config.tile_distance(candidate.tile, tile)
			if candidate_distance < distance:
				distance = candidate_distance
				settlement = candidate
	if settlement != null:
		result.merge(_market_data(settlement), true)
		if LocalWarrants.is_active(world, settlement):
			result.merge({"items": {}, "closed": true, "name": "Market closed to wanted travelers",
				"close_reason": "The local authorities have issued a warrant."}, true)
			if _can_negotiate_amnesty(trader, settlement):
				result["amnesty_silver"] = LocalWarrants.amnesty_quote(world, settlement)
			return
		var agent: GlobalAgent = world.agents.find(str(trader.get_meta("global_agent_id", ""))) as GlobalAgent
		if agent != null and not agent.caravan_id.is_empty():
			result["items"] = {}
			result["closed"] = true
			result["name"] = "Caravan cargo reserved for delivery"

func _can_negotiate_amnesty(trader: Node, settlement: AlifeSettlement) -> bool:
	if not is_instance_valid(trader) or not trader is NPCBase or not trader.is_alive():
		return false
	var agent: GlobalAgent = world.agents.find(str(trader.get_meta("global_agent_id", ""))) as GlobalAgent
	if agent == null or not agent.alive or agent.settlement_id != settlement.settlement_id:
		return false
	var tile: Vector2i = Config.iso_to_world(trader.global_position)
	return agent.role in ["trader", "elder"] and agent.caravan_id.is_empty() \
		and _settlement_chunks.get(Config.tile_to_chunk(tile)) == settlement.settlement_id

func _on_local_amnesty_requested(trader: Node, quoted: int, result: Dictionary) -> void:
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if not _initialized or not is_instance_valid(player) or not is_instance_valid(trader) or not trader is NPCBase:
		return
	var settlement: AlifeSettlement = world.settlements.find(str(trader.get_meta("settlement_id", ""))) as AlifeSettlement
	if settlement == null or not _can_negotiate_amnesty(trader, settlement) or player.global_position.distance_to(trader.global_position) > 120.0:
		result["message"] = "Speak to a local representative to request amnesty."
		return
	result.merge(LocalWarrants.pay_amnesty(world, settlement, player.inventory, quoted), true)

func _on_trade_requested(trader: Node, inventory: Resource, item_id: String, count: int, is_buying: bool, skill_mod: float, memory_mult: float, result: Dictionary) -> void:
	var market: Dictionary = {}
	_on_market_queried(trader, market)
	if not bool(market.get("managed", false)):
		return
	result["handled"] = true
	if bool(market.get("closed", false)):
		result["error"] = str(market.get("close_reason", "These goods are reserved for delivery."))
		return
	if _trading:
		result["error"] = "A trade is already in progress."
		return
	var settlement: AlifeSettlement = world.settlements.find(str(market.get("id", ""))) as AlifeSettlement
	if settlement == null:
		return
	_trading = true
	result.merge(MarketTrade.execute(settlement, inventory as InventoryComponent, item_id, count, is_buying, skill_mod, memory_mult), true)
	_trading = false
	if bool(result.get("ok", false)):
		world.record_event("player_traded", settlement.tile, [settlement.owner_faction], {"settlement_id": settlement.settlement_id, "item": item_id, "count": int(result["count"]), "buying": is_buying, "silver_value": int(result["silver_value"])})

func _cargo_near_player(id: String) -> bool:
	var entity: CaravanPackAnimal = pack_materializer.get_entity(id)
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	return _initialized and is_instance_valid(entity) and entity.visible and is_instance_valid(player) and entity.global_position.distance_to(player.global_position) <= 120.0

func _on_cargo_open_requested(id: String) -> void:
	if _cargo_near_player(id):
		SignalBus.alife_cargo_opened.emit(id)

func _on_cargo_queried(id: String, result: Dictionary) -> void:
	if not _cargo_near_player(id):
		return
	var data: Dictionary = CaravanCargo.endpoint(world, id)
	if not data.is_empty():
		result.merge({"title": data["title"], "cargo": (data["cargo"] as Dictionary).duplicate(true)})
		result["is_wreck"] = data.has("wreck")
		var route: CaravanRoute = data["route"] as CaravanRoute
		result["escort_available"] = not data.has("wreck") and EscortContracts.can_offer(world, route)
		result["escort_state"] = str((world.contracts.get(EscortContracts.id_for(route), {}) as Dictionary).get("state", ""))

func _on_cargo_take_requested(id: String, item: String, count: int, result: Dictionary) -> void:
	if _cargo_busy or not _cargo_near_player(id):
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	var inventory: InventoryComponent = player.get("inventory") as InventoryComponent
	_cargo_busy = true
	result.merge(CaravanCargo.take(world, id, item, count, inventory), true)
	_cargo_busy = false
	if bool(result.get("theft", false)):
		var route: CaravanRoute = world.routes.find(str(result.get("route_id", ""))) as CaravanRoute
		if route != null:
			_mark_caravan_raid(route, Config.iso_to_world(pack_materializer.get_entity(id).global_position))

func _mark_caravan_raid(route: CaravanRoute, location: Vector2i) -> void:
	if route.attacked_by_player:
		return
	var witnesses: Array = []
	for id: String in [route.merchant_id] + route.guards:
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent != null and agent.alive and Config.tile_distance(agent.tile, location) <= 12.0:
			witnesses.append(agent)
	if witnesses.is_empty():
		return
	route.attacked_by_player = true
	EscortContracts.fail_route(world, route, "betrayed_caravan")
	var home: AlifeSettlement = world.settlements.find(route.from_id) as AlifeSettlement
	if home != null:
		var outlaw: Dictionary = world.reputation.get("outlaw_regions", {})
		outlaw[home.settlement_id] = true
		world.reputation["outlaw_regions"] = outlaw
		SignalBus.faction_rep_change_requested.emit(home.owner_faction, -40, "raided_caravan")
	for agent: GlobalAgent in witnesses:
		agent.grudges.append({"reason": "caravan_raid", "hour": world.simulated_hour, "route_id": route.route_id})
		agent.relation_to_player = maxi(-100, agent.relation_to_player - 30)
		var reference: Variant = world.agents.materialized.get(agent.agent_id)
		if is_instance_valid(reference):
			var npc: NPCBase = reference as NPCBase
			npc.memory.remember("caravan_raid", "player", -30, GameManager.get_day())
			_on_agent_materialized(agent.agent_id, npc)
		SignalBus.npc_grudge_added.emit(agent.agent_id, "caravan_raid")
	world.record_event("caravan_attacked", location, [home.owner_faction] if home != null else [], {"route_id": route.route_id, "settlement_id": route.from_id})

func _on_agent_materialized(id: String, entity: Node) -> void:
	var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
	if agent != null and not agent.ambush_route_id.is_empty():
		entity.add_to_group("enemies")
		entity.set_meta("alife_caravan_hostile", true)
		return
	if agent == null or not agent.role in ["guard", "soldier", "caravan_guard"]:
		return
	for grudge: Dictionary in agent.grudges:
		if str(grudge.get("reason", "")) in ["caravan_raid", "witnessed_killing"]:
			entity.add_to_group("enemies")
			entity.set_meta("alife_caravan_hostile", true)
			return

func _sync_caravan_hostile_visibility() -> void:
	for reference: Variant in world.agents.materialized.values():
		if not is_instance_valid(reference):
			continue
		var entity: NPCBase = reference as NPCBase
		if entity.has_meta("alife_caravan_hostile"):
			var info: Dictionary = {}
			SignalBus.world_tile_queried.emit(Config.iso_to_world(entity.global_position), info)
			entity.visible = true

func _materialize_encounters() -> void:
	var needed: Dictionary = {}
	for route: CaravanRoute in world.routes.all():
		if not route.active or route.ambush_phase != "active":
			continue
		for id: String in route.ambushers + route.guards + [route.merchant_id]:
			needed[id] = true
	for id: String in _encounter_views.keys():
		var reference: Variant = world.agents.materialized.get(id)
		if not is_instance_valid(reference):
			_encounter_views.erase(id)
		elif not needed.has(id):
			var entity: NPCBase = reference as NPCBase
			if not entity.visible or Config.tile_distance(Config.iso_to_world(entity.global_position), materializer.player_tile) > Config.LOD_NEAR_TILES:
				materializer.dematerialize(id)
				_encounter_views.erase(id)
	var created: int = 0
	for id: String in needed:
		if created >= 2 or _encounter_views.size() >= 12:
			break
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent == null or not agent.alive or world.agents.materialized.has(id):
			continue
		if not materializer.loaded_chunks.has(Config.tile_to_chunk(agent.tile)) or Config.tile_distance(agent.tile, materializer.player_tile) > Config.LOD_MID_TILES:
			continue
		if materializer.materialize(agent) != null:
			_encounter_views[id] = true
			created += 1

func _on_escort_accept_requested(route_id: String, result: Dictionary) -> void:
	if not _cargo_near_player(route_id):
		return
	var route: CaravanRoute = world.routes.find(route_id) as CaravanRoute
	if route != null:
		var hour: float = float(GameManager.get_day() - 1) * 24.0 + GameManager.get_hour()
		result["ok"] = EscortContracts.accept(world, route, hour)
		SignalBus.notification_posted.emit("Escort accepted. Stay within 12 tiles of the convoy." if bool(result["ok"]) else "The merchant cannot offer an escort contract for this trip.")

func _claim_escort_rewards() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	var inventory: InventoryComponent = player.get("inventory") as InventoryComponent
	if inventory == null:
		return
	_escort_reward_check = false
	for id: String in world.contracts.keys():
		var reward: int = EscortContracts.claim(world, id, inventory)
		if reward > 0:
			var contract: Dictionary = world.contracts[id]
			SignalBus.faction_rep_change_requested.emit(str(contract["faction_id"]), 8, "escorted_caravan")
			SignalBus.notification_posted.emit("Escort completed: %d silver received." % reward)
