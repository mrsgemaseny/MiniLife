class_name CaravanPackMaterializer
extends RefCounted

var world: AlifeWorldContext
var parent: Node2D
var entities: Dictionary = {}

func reset(context: AlifeWorldContext) -> void:
	sync_all()
	for id: String in entities.keys():
		var entity: CaravanPackAnimal = get_entity(id)
		if entity != null:
			entity.queue_free()
	entities.clear()
	world = context

func get_entity(id: String) -> CaravanPackAnimal:
	var value: Variant = entities.get(id)
	return value as CaravanPackAnimal if is_instance_valid(value) else null

func update(loaded_chunks: Dictionary, player_tile: Vector2i) -> void:
	if world == null or not is_instance_valid(parent):
		return
	var wanted: Dictionary = {}
	for route: CaravanRoute in world.routes.all():
		var value: Variant = world.agents.materialized.get(route.merchant_id)
		var merchant: NPCBase = value as NPCBase if is_instance_valid(value) else null
		if route.active and merchant != null:
			wanted[route.route_id] = true
			var pack: CaravanPackAnimal = get_entity(route.route_id)
			if pack == null:
				pack = _spawn(route.route_id, route.route_id, merchant.global_position - Vector2(40.0, 0.0), route.pack_state)
			pack.leader = merchant
			pack.visible = merchant.visible
		for wreck: Dictionary in route.wrecks:
			var point: Array = wreck["tile"]
			var tile: Vector2i = Vector2i(int(point[0]), int(point[1]))
			if (wreck["cargo"] as Dictionary).is_empty() or not loaded_chunks.has(Config.tile_to_chunk(tile)) or Config.tile_distance(player_tile, tile) > Config.LOD_MID_TILES:
				continue
			var id: String = str(wreck["id"])
			wanted[id] = true
			if get_entity(id) == null:
				var pack: CaravanPackAnimal = _spawn(id, route.route_id, Config.world_to_iso(tile), wreck.get("state", {}))
				pack.is_permanently_dead = true
				pack.stats.health = 0.0
				pack.rotation = -PI * 0.5
				pack.display_name = "Abandoned Caravan Supplies"
				pack.remove_from_group("combatant")
			get_entity(id).visible = true
	for id: String in entities.keys():
		if not wanted.has(id):
			_sync(id)
			var entity: CaravanPackAnimal = get_entity(id)
			if entity != null:
				entity.queue_free()
			entities.erase(id)

func _spawn(id: String, route_id: String, point: Vector2, state: Dictionary) -> CaravanPackAnimal:
	var entity: CaravanPackAnimal = CaravanPackAnimal.new()
	entity.cargo_id = id
	entity.route_id = route_id
	entity.position = parent.to_local(point)
	entities[id] = entity
	parent.add_child(entity)
	if not state.is_empty():
		var restored: Dictionary = state.duplicate(true)
		if id == route_id:
			restored["position"] = [point.x, point.y]
		entity.restore_spawn_state(restored)
	return entity

func sync_all() -> void:
	if world == null:
		return
	for id: String in entities.keys():
		_sync(id)

func _sync(id: String) -> void:
	var entity: CaravanPackAnimal = get_entity(id)
	if entity == null:
		return
	var route: CaravanRoute = world.routes.find(entity.route_id) as CaravanRoute
	if route == null:
		return
	if id == route.route_id:
		route.pack_state = entity.spawn_state()
	else:
		for wreck: Dictionary in route.wrecks:
			if str(wreck["id"]) == id:
				wreck["state"] = entity.spawn_state()

func on_death(entity: CaravanPackAnimal) -> void:
	var route: CaravanRoute = world.routes.find(entity.route_id) as CaravanRoute
	if route == null or entity.cargo_id != route.route_id:
		return
	var id: String = CaravanCargo.make_wreck(world, route, Config.iso_to_world(entity.global_position), entity.spawn_state())
	entities.erase(route.route_id)
	if not id.is_empty():
		entity.cargo_id = id
		entity.set_meta("caravan_pack_id", id)
		entities[id] = entity
	else:
		entity.queue_free()
	route.pack_state.clear()
	CaravanEventGenerator.fail(world, route, "pack_lost")
