from pathlib import Path
import difflib
def emit(p,s):
 old=Path(p).read_text(encoding='utf-8-sig')
 if old!=s:
  print('*** Update File: '+p)
  print(''.join(difflib.unified_diff(old.splitlines(True),s.splitlines(True),n=3)).split('\n',2)[2],end='')
print('*** Begin Patch')
p='scripts/entities/animal_entity.gd';s=Path(p).read_text(encoding='utf-8-sig')
s=s.replace('var current_state: State', 'var spawn_uid: String = ""\nvar spawn_chunk: Vector2i = Vector2i.ZERO\n\nvar current_state: State',1)
s=s.replace('\tadd_to_group("animal")','\tadd_to_group("animal")\n\tadd_to_group("animals")\n\tadd_to_group("fauna")',1)
s += '''
func is_alive() -> bool:
	return not is_permanently_dead and stats != null and stats.health > 0.0

func spawn_state() -> Dictionary:
	return {"position": [global_position.x, global_position.y], "health": stats.health,
		"last_harvest_day": last_harvest_day, "is_sheared": is_sheared, "egg_timer": _egg_timer,
		"pack": pack_inventory.to_dict() if pack_inventory != null else {}}

func restore_spawn_state(state: Dictionary) -> void:
	var pos: Array = state.get("position", [global_position.x, global_position.y])
	global_position = Vector2(float(pos[0]), float(pos[1]))
	stats.health = clampf(float(state.get("health", stats.health)), 0.0, stats.max_health)
	last_harvest_day = int(state.get("last_harvest_day", -1))
	is_sheared = bool(state.get("is_sheared", false))
	_egg_timer = float(state.get("egg_timer", 120.0))
	if pack_inventory != null:
		pack_inventory.from_dict(state.get("pack", {}))
'''
emit(p,s)
p='scripts/systems/world_system.gd';s=Path(p).read_text(encoding='utf-8-sig')
s=s.replace('match _biome_id:', 'match b_at:')
s=s.replace('if rng_fauna.randf() < 0.085:', 'if rng_fauna.randf() < 0.30:')
s=s.replace('["cow", "sheep", "chicken", "hare", "horse", "dog"][rng_fauna.randi() % 6]', '["cow", "sheep", "chicken", "hare", "horse", "hare"][rng_fauna.randi() % 6]')
s=s.replace('["donkey", "hare", "dog"][rng_fauna.randi() % 3]', '["donkey", "hare"][rng_fauna.randi() % 2]')
s=s.replace('\t\t\t\t\tanimal.animal_type = chosen_animal','\t\t\t\t\tanimal.animal_type = chosen_animal\n\t\t\t\t\tanimal.spawn_uid = animal_uid\n\t\t\t\t\tanimal.spawn_chunk = cpos')
s=s.replace('\t\t\t\t\tadd_child(animal)\n', '\t\t\t\t\tadd_child(animal)\n\t\t\t\t\tvar saved_animals: Dictionary = _delta.get("animals", {})\n\t\t\t\t\tif saved_animals.has(animal_uid):\n\t\t\t\t\t\tanimal.restore_spawn_state(saved_animals[animal_uid])\n')
s=s.replace('and _is_tile_in_bounds(atile):', 'and _is_tile_in_bounds(atile) and is_passable(atile):')
s=s.replace('var wolf_spawn_chance: float = 0.05 if is_night else 0.02', 'var wolf_spawn_chance: float = 0.05')
s=s.replace('\t\t\t\t\twolf.spawn_uid = wolf_uid', '\t\t\t\t\twolf.spawn_uid = wolf_uid\n\t\t\t\t\twolf.set_meta("spawn_chunk", cpos)')
s=s.replace('\t_spawned_entities_by_chunk[cpos] = spawned_list', '\t_spawn_location_inhabitants(cpos, spawned_list, killed)\n\t_spawned_entities_by_chunk[cpos] = spawned_list')
s=s.replace('\tif _spawned_entities_by_chunk.has(cpos):\n\t\tfor ent', '\t_snapshot_animals(cpos)\n\tif _spawned_entities_by_chunk.has(cpos):\n\t\tfor ent',1)
s=s.replace('var cpos: Vector2i = Config.tile_to_chunk(Config.iso_to_world(world_pos))', 'var cpos: Vector2i = entity.spawn_chunk if entity is AnimalEntity else entity.get_meta("spawn_chunk", Config.tile_to_chunk(Config.iso_to_world(world_pos)))')
s=s.replace('\tif poi_data.get("is_ruin", false):\n\t\t_spawn_ruin_complex(chunk_node, cpos, poi_data)', '\tif poi_data.get("is_ruin", false):\n\t\t_spawn_ruin_complex(chunk_node, cpos, poi_data)\n\telif not poi_data.is_empty():\n\t\t_spawn_minor_location(poi_data)')
s=s.replace('if ruin_def.has("interior_zone_id"):\n\t\t\t\tvar zone_id: String = str(ruin_def["interior_zone_id"])', 'if not str(ruin_def.get("interior_zone", "")).is_empty():\n\t\t\t\tvar zone_id: String = str(ruin_def["interior_zone"])')
s=s.replace('SignalBus.structure_restored.emit("wall", anchor + Vector2i(int(wp[0]), int(wp[1])))', 'SignalBus.structure_restored.emit("well", anchor + Vector2i(int(wp[0]), int(wp[1])))')
s=s.replace('func _on_save_data_requested(bundle: Dictionary) -> void:', 'func _on_save_data_requested(bundle: Dictionary) -> void:\n\tfor cpos: Vector2i in _spawned_entities_by_chunk.keys():\n\t\t_snapshot_animals(cpos)')
s += '''
func _snapshot_animals(cpos: Vector2i) -> void:
	var states: Dictionary = {}
	for entity: Node in _spawned_entities_by_chunk.get(cpos, []):
		if is_instance_valid(entity) and entity is AnimalEntity and entity.is_alive():
			states[entity.spawn_uid] = entity.spawn_state()
	if not states.is_empty():
		var delta: Dictionary = _get_or_create_delta(cpos)
		delta["animals"] = states
		_commit_delta(cpos, delta)

func _spawn_minor_location(info: Dictionary) -> void:
	var anchor: Vector2i = info["tile_pos"]
	var id: String = str(info["poi_id"])
	for x in range(5):
		for y in range(5):
			_remove_resource_node_at(anchor + Vector2i(x, y))
	SignalBus.structure_restored.emit("campfire", anchor + Vector2i(2, 2))
	var chest: Vector2i = anchor + Vector2i(3, 2)
	SignalBus.structure_restored.emit("storage", chest)
	var definition: Dictionary = DataRegistry.get_poi(id)
	var loot: Dictionary = definition.get("loot_table", {})
	if BuildingSystem.instance != null:
		BuildingSystem.instance.get_storage_manager().populate_chest_loot(chest, str(definition.get("name", id)), int(loot.get("gold", 0)), loot.get("items", {}))
	if id in ["ruins", "cave", "dungeon"]:
		for x in range(5):
			SignalBus.structure_restored.emit("wall", anchor + Vector2i(x, 0))

func _spawn_location_inhabitants(cpos: Vector2i, spawned: Array[Node], killed: Array) -> void:
	var info: Dictionary = _chunk_pois.get(cpos, {})
	if info.is_empty():
		return
	var anchor: Vector2i = info["tile_pos"]
	var ruin: Dictionary = info.get("ruin_data", {})
	var guards: Array = ruin.get("enemies", []).duplicate(true)
	if not bool(info.get("is_ruin", false)):
		var pool: Array = DataRegistry.get_poi(str(info["poi_id"])).get("enemy_pool", [])
		for i in range(mini(pool.size(), 2)):
			guards.append({"id": pool[i], "offset": [1 + i * 2, 3]})
	for i in range(guards.size()):
		var uid: String = "poi_%d_%d_%d" % [cpos.x, cpos.y, i]
		if killed.has(uid):
			continue
		var definition: Dictionary = guards[i]
		if DataRegistry.get_enemy(str(definition["id"])).is_empty():
			continue
		var offset: Array = definition.get("offset", [2, 3])
		var tile: Vector2i = anchor + Vector2i(int(offset[0]), int(offset[1]))
		if not is_passable(tile):
			continue
		var guard: EnemyBase = ENEMY_SCENE.instantiate() as EnemyBase
		guard.enemy_id = str(definition["id"])
		guard.spawn_uid = uid
		guard.set_meta("spawn_chunk", cpos)
		guard.global_position = Config.world_to_iso(tile)
		add_child(guard)
		spawned.append(guard)
'''
emit(p,s)
print('*** End Patch')
