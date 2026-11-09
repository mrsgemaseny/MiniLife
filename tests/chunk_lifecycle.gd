extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DataRegistry.reload_all()
	var world: WorldSystem = WorldSystem.new()
	var dead: Node = Node.new()
	var alive: Node = Node.new()
	var chunk: Vector2i = Vector2i(7,6)
	world._spawned_entities_by_chunk[chunk] = [dead, alive]
	dead.free()
	# Regression: the old typed loop raised "Trying to assign invalid previously freed instance" here.
	world._snapshot_entities(chunk)
	assert(world._spawned_entities_by_chunk[chunk].size() == 1, "Freed reference not pruned")
	world._snapshot_entities(chunk)
	var context: AlifeWorldContext = AlifeWorldContext.new()
	var materializer: AgentMaterializer = AgentMaterializer.new()
	materializer.world = context
	var expired: Node = Node.new()
	context.agents.materialized["expired"] = expired
	expired.free()
	assert(materializer._live_entity("expired") == null, "Materializer retained freed reference")
	var center: Vector2i = Vector2i(Config.WORLD_SIZE_CHUNKS / 2, Config.WORLD_SIZE_CHUNKS / 2)
	var terrain: TerrainGenerator = TerrainGenerator.new(Config.DEFAULT_WORLD_SEED)
	for x in range(center.x-2, center.x+2):
		for y in range(center.y-2,center.y+2):
			var tile: Vector2i = Config.chunk_origin(Vector2i(x,y))+Vector2i(8,8)
			if Config.tile_distance(tile,Vector2i(Config.WORLD_SIZE_TILES/2,Config.WORLD_SIZE_TILES/2)) < 48:
				assert(PoiGenerator.get_chunk_poi(Config.DEFAULT_WORLD_SEED,Vector2i(x,y),terrain.get_biome_at(tile)).is_empty(),"POI in starter wilderness")
	alive.free()
	world.free()
	print("CHUNK_LIFECYCLE_OK: freed references, repeated snapshot, materializer, starter POI exclusion")
	get_tree().quit(0)
