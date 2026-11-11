class_name BuildingSystem
extends Node2D

static var instance: BuildingSystem = null

var _placed_nodes: Dictionary = {}
var _placed_floors: Dictionary = {}
var _placed_structures: Dictionary = {}
var _storage_mgr: StorageManager = StorageManager.new()
var _defense_net: DefenseNetwork = DefenseNetwork.new()
var _active_build_id: String = ""
var _cursor_tile: Vector2i = Vector2i.ZERO
var _smooth_cursor_world: Vector2 = Vector2.ZERO
var _pulse_phase: float = 0.0


func _ready() -> void:
	instance = self
	y_sort_enabled = true
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.build_mode_changed.connect(_on_build_mode_changed)
	SignalBus.build_requested.connect(_on_build_requested)
	SignalBus.structure_placement_validated.connect(_on_structure_placement_validated)
	SignalBus.structure_restored.connect(_on_structure_restored)
	SignalBus.settlement_door_passage_requested.connect(_on_settlement_door_passage_requested)
	SignalBus.door_state_queried.connect(func(tile: Vector2i, result: Dictionary) -> void:
		var door: StructureEntity = _placed_structures.get(Config.vec2i_to_key(tile)) as StructureEntity
		if is_instance_valid(door) and door.structure_id in ["door", "wood_door"]:
			result["open"] = door.is_door_open)
	SignalBus.structure_destroyed.connect(_on_structure_destroyed)
	SignalBus.structure_removal_requested.connect(_on_structure_removal_requested)
	SignalBus.trap_triggered.connect(_on_trap_triggered)
	SignalBus.structure_placement_rejected.connect(func(_structure_id: String, _tile_pos: Vector2i, reason: String) -> void:
		if reason != "":
			SignalBus.notification_posted.emit(reason))
	SignalBus.crafting_sources_queried.connect(func(origin: Vector2i, result: Dictionary) -> void:
		result["inventories"] = _storage_mgr.get_nearby_containers(origin, 4))


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		clear_all_structures()


func clear_all_structures() -> void:
	for key in _placed_structures.keys():
		var s: Node = _placed_structures[key]
		if is_instance_valid(s):
			s.queue_free()
	_placed_structures.clear()
	for key in _placed_floors.keys():
		var f: Node = _placed_floors[key]
		if is_instance_valid(f):
			f.queue_free()
	_placed_floors.clear()
	_placed_nodes.clear()
	_storage_mgr = StorageManager.new()
	_defense_net = DefenseNetwork.new()
	for node in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(node) and node is StructureEntity:
			node.queue_free()


func _process(delta: float) -> void:
	if _active_build_id == "":
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	var next_tile: Vector2i = Config.iso_to_world(mouse_world)
	if next_tile != _cursor_tile:
		_cursor_tile = next_tile
	var target_world: Vector2 = Config.world_to_iso(_cursor_tile)
	if _smooth_cursor_world == Vector2.ZERO:
		_smooth_cursor_world = target_world
	else:
		_smooth_cursor_world = _smooth_cursor_world.lerp(target_world, clampf(delta * 18.0, 0.0, 1.0))
	_pulse_phase += delta * 5.5
	queue_redraw()


func is_build_mode_active() -> bool:
	return _active_build_id != ""


func get_storage_manager() -> StorageManager:
	return _storage_mgr


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("demolish"):
		var target_tile: Vector2i = Config.iso_to_world(get_global_mouse_position())
		var player: Node = get_tree().get_first_node_in_group("player")
		SignalBus.structure_removal_requested.emit(target_tile, player)
		get_viewport().set_input_as_handled()
		return

	if _active_build_id == "":
		return
	if event.is_action_pressed("build_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_B or event.keycode == KEY_ESCAPE)):
		set_build_mode("")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_place"):
		var player: Node = get_tree().get_first_node_in_group("player")
		var reason: String = requirement_block_reason(player, _active_build_id)
		if player != null and reason.is_empty():
			SignalBus.build_requested.emit(_active_build_id, _cursor_tile, player)
		else:
			SignalBus.notification_posted.emit(reason if reason != "" else "Cannot build " + _active_build_id)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if _active_build_id == "":
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	var valid: bool = has_materials(player, _active_build_id) and can_place_block(_active_build_id, _cursor_tile)
	BlueprintPlacer.draw_ghost_preview(self, _cursor_tile, valid, _smooth_cursor_world, _pulse_phase, _active_build_id)


func set_build_mode(structure_id: String) -> void:
	if structure_id != "" and DataRegistry.get_structure(structure_id).is_empty():
		return
	_active_build_id = structure_id
	SignalBus.build_mode_activated.emit(structure_id)
	_smooth_cursor_world = Vector2.ZERO
	queue_redraw()


func snap_to_iso_grid(world_pos: Vector2) -> Vector2:
	var tile: Vector2i = Config.iso_to_world(world_pos)
	return Config.world_to_iso(tile)


func has_materials(builder: Node, structure_id: String) -> bool:
	return requirement_block_reason(builder, structure_id).is_empty()


static func requirement_block_reason(builder: Node, structure_id: String) -> String:
	if builder == null:
		return "No builder"
	var def: Dictionary = DataRegistry.get_structure(structure_id)
	if def.is_empty():
		return "Unknown structure"
	if GameManager.sandbox_for(builder):
		return ""
	var min_level: int = int(def.get("min_level", 2))
	if ProgressionSystem.instance != null and ProgressionSystem.instance.current_level < min_level:
		return "Requires level %d" % min_level
	var tech: String = str(def.get("tech_required", ""))
	if tech != "" and (ResearchSystem.instance == null or not ResearchSystem.instance.is_researched(tech)):
		return "Requires research: " + tech.replace("_", " ")
	var inv: InventoryComponent = builder.get("inventory") as InventoryComponent
	if inv == null:
		return "No inventory"
	var missing: PackedStringArray = PackedStringArray()
	for mat in def.get("materials", []):
		if mat is Dictionary:
			var item_id: String = str(mat.get("item_id", ""))
			var need: int = int(mat.get("count", 1))
			var have: int = inv.count_of(item_id)
			if have < need:
				missing.append("%s %d/%d" % [item_id, have, need])
	if not missing.is_empty():
		return "Need " + ", ".join(missing)
	return ""


func consume_materials(builder: Node, structure_id: String) -> void:
	if GameManager.sandbox_for(builder):
		return
	if builder == null:
		return
	var def: Dictionary = DataRegistry.get_structure(structure_id)
	var inv: InventoryComponent = builder.get("inventory") as InventoryComponent
	if inv == null or def.is_empty():
		return
	for mat in def.get("materials", []):
		if mat is Dictionary:
			inv.remove_item(str(mat.get("item_id", "")), int(mat.get("count", 1)))


func can_place_block(structure_id: String, tile_pos: Vector2i) -> bool:
	if DataRegistry.get_structure(structure_id).is_empty():
		return false
	var terrain: Dictionary = {}
	SignalBus.world_tile_queried.emit(tile_pos, terrain)
	if terrain.is_empty() or not bool(terrain.get("passable", false)):
		return false
	if bool(terrain.get("occupied", false)) and str(terrain.get("structure_id", "")) not in ["floor", "stone_floor"]:
		return false
	var key: String = Config.vec2i_to_key(tile_pos)
	var is_floor: bool = structure_id in ["floor", "stone_floor"]

	if is_floor:
		if _placed_floors.has(key) and is_instance_valid(_placed_floors[key]):
			return false
	else:
		if _placed_structures.has(key) and is_instance_valid(_placed_structures[key]):
			return false

	var def: Dictionary = DataRegistry.get_structure(structure_id)
	var passable: bool = bool(def.get("passable", false))
	if not passable:
		var ptile: Vector2i = GameManager.get_player_tile()
		if ptile == tile_pos:
			return false
		var harvestables: Array[Node] = get_tree().get_nodes_in_group("harvestable")
		for h in harvestables:
			if h is ResourceNode and (h as ResourceNode).tile_pos == tile_pos and (h as ResourceNode).is_visible_in_tree():
				return false
	return true


func place_block_from_hand(structure_id: String, tile_pos: Vector2i, builder: Node) -> bool:
	if not builder is Node2D or Config.tile_distance(Config.iso_to_world(builder.global_position), tile_pos) > 4:
		return false
	if not can_place_block(structure_id, tile_pos):
		return false
	_spawn_structure_node(structure_id, tile_pos, true, true)
	if builder != null:
		var skills: SkillsComponent = builder.get("skills") as SkillsComponent
		if skills != null:
			skills.gain_xp("construction", 8.0)
	SignalBus.structure_built.emit(structure_id, tile_pos)
	return true


func _on_build_mode_changed(structure_id: String) -> void:
	set_build_mode(structure_id)


func _on_build_requested(structure_id: String, tile_pos: Vector2i, builder: Node) -> void:
	if is_instance_valid(builder) and bool(builder.get_meta("item_action_busy", false)):
		SignalBus.structure_placement_rejected.emit(structure_id, tile_pos, "Finish the current action first")
		return
	if not builder is Node2D or Config.tile_distance(Config.iso_to_world(builder.global_position), tile_pos) > 4:
		SignalBus.structure_placement_rejected.emit(structure_id, tile_pos, "Move closer to the build site")
		return
	if not has_materials(builder, structure_id):
		return
	if can_place_block(structure_id, tile_pos):
		SignalBus.structure_placement_validated.emit(structure_id, tile_pos, builder)
	else:
		SignalBus.structure_placement_rejected.emit(structure_id, tile_pos, "Tile occupied or blocked")


func _on_structure_placement_validated(structure_id: String, tile_pos: Vector2i, builder: Node) -> void:
	if not has_materials(builder, structure_id) or not can_place_block(structure_id, tile_pos):
		return
	if builder != null:
		consume_materials(builder, structure_id)
		var skills: SkillsComponent = builder.get("skills") as SkillsComponent
		if skills != null:
			skills.gain_xp("construction", 14.0)
	_spawn_structure_node(structure_id, tile_pos, true, true)
	SignalBus.structure_built.emit(structure_id, tile_pos)


func _on_structure_restored(structure_id: String, tile_pos: Vector2i) -> void:
	_spawn_structure_node(structure_id, tile_pos, false, false)


func _on_settlement_door_passage_requested(tile: Vector2i, resident: Node2D) -> void:
	var door: StructureEntity = _placed_structures.get(Config.vec2i_to_key(tile)) as StructureEntity
	if not is_instance_valid(door) or door.is_player_built or door.structure_id != "door":
		return
	if not is_instance_valid(resident) or not resident.has_meta("global_agent_id"):
		return
	if Config.tile_distance(Config.iso_to_world(resident.global_position), tile) > 1:
		return
	var info: Dictionary = {}
	SignalBus.world_tile_queried.emit(tile, info)
	var owner: String = str(info.get("settlement_door", ""))
	if not owner.is_empty() and owner == str(resident.get_meta("settlement_id", "")):
		door.open_for_resident()


func _on_structure_removal_requested(tile_pos: Vector2i, breaker: Node) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	if _placed_structures.has(key) and is_instance_valid(_placed_structures[key]):
		var s: StructureEntity = _placed_structures[key] as StructureEntity
		if s != null and s.is_player_built:
			s.dismantle(breaker)
			return
	if _placed_floors.has(key) and is_instance_valid(_placed_floors[key]):
		var f: StructureEntity = _placed_floors[key] as StructureEntity
		if f != null and f.is_player_built:
			f.dismantle(breaker)
			return


func _on_structure_destroyed(structure_id: String, tile_pos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	_defense_net.unregister_tile(tile_pos)
	_storage_mgr.remove_container(tile_pos)

	var is_floor: bool = structure_id in ["floor", "stone_floor"]
	if is_floor:
		if _placed_floors.has(key):
			var fnode: Node = _placed_floors[key]
			if is_instance_valid(fnode):
				fnode.queue_free()
			_placed_floors.erase(key)
			if _placed_nodes.get(key) == fnode:
				_placed_nodes.erase(key)
	else:
		if _placed_structures.has(key):
			var snode: Node = _placed_structures[key]
			if is_instance_valid(snode):
				snode.queue_free()
			_placed_structures.erase(key)
			if _placed_nodes.get(key) == snode:
				if _placed_floors.has(key) and is_instance_valid(_placed_floors[key]):
					_placed_nodes[key] = _placed_floors[key]
				else:
					_placed_nodes.erase(key)


func _spawn_structure_node(structure_id: String, tile_pos: Vector2i, animate_build: bool = false, is_player_built: bool = true) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	var is_floor: bool = structure_id in ["floor", "stone_floor"]

	if is_floor:
		if _placed_floors.has(key) and is_instance_valid(_placed_floors[key]):
			return
	else:
		if _placed_structures.has(key) and is_instance_valid(_placed_structures[key]):
			return

	var inst: StructureEntity = StructureEntity.new()
	inst.structure_id = structure_id
	inst.tile_pos = tile_pos
	inst.animate_construction = animate_build
	inst.is_player_built = is_player_built
	inst.global_position = Config.world_to_iso(tile_pos)
	add_child(inst)

	if is_floor:
		_placed_floors[key] = inst
		if not _placed_nodes.has(key) or not is_instance_valid(_placed_nodes[key]):
			_placed_nodes[key] = inst
	else:
		_placed_structures[key] = inst
		_placed_nodes[key] = inst
		_defense_net.register_structure(structure_id, tile_pos)


func _on_trap_triggered(trap_id: String, tile_pos: Vector2i, target: Node) -> void:
	TrapResolver.resolve_trap_trigger(trap_id, tile_pos, target, self)


func get_save_data() -> Dictionary:
	var floors_arr: Array = []
	for key in _placed_floors:
		var node: Node = _placed_floors[key]
		if is_instance_valid(node) and node is StructureEntity:
			var se: StructureEntity = node as StructureEntity
			floors_arr.append({
				"id": se.structure_id,
				"tile": [se.tile_pos.x, se.tile_pos.y],
				"hp": se.current_hp,
				"player_built": se.is_player_built
			})
	var structs_arr: Array = []
	for key in _placed_structures:
		var node: Node = _placed_structures[key]
		if is_instance_valid(node) and node is StructureEntity:
			var se: StructureEntity = node as StructureEntity
			structs_arr.append({
				"id": se.structure_id,
				"tile": [se.tile_pos.x, se.tile_pos.y],
				"hp": se.current_hp,
				"player_built": se.is_player_built
			})
	var containers_data: Dictionary = {}
	if _storage_mgr != null:
		containers_data = _storage_mgr.to_dict()
	return {
		"floors": floors_arr,
		"structures": structs_arr,
		"containers": containers_data
	}


func load_save_data(data: Dictionary) -> void:
	# Clear currently spawned dynamic structures
	for key in _placed_structures.keys():
		var node: Node = _placed_structures[key]
		if is_instance_valid(node):
			node.queue_free()
	_placed_structures.clear()
	for key in _placed_floors.keys():
		var node: Node = _placed_floors[key]
		if is_instance_valid(node):
			node.queue_free()
	_placed_floors.clear()
	_placed_nodes.clear()

	for f in data.get("floors", []):
		var tile_arr: Array = f.get("tile", [0, 0])
		var tpos: Vector2i = Vector2i(int(tile_arr[0]), int(tile_arr[1]))
		var sid: String = str(f.get("id", ""))
		if sid != "":
			_spawn_structure_node(sid, tpos, false, bool(f.get("player_built", true)))
			var s: StructureEntity = _placed_floors.get(Config.vec2i_to_key(tpos), null) as StructureEntity
			if s != null and f.has("hp"):
				s.current_hp = float(f["hp"])

	for sdata in data.get("structures", []):
		var tile_arr: Array = sdata.get("tile", [0, 0])
		var tpos: Vector2i = Vector2i(int(tile_arr[0]), int(tile_arr[1]))
		var sid: String = str(sdata.get("id", ""))
		if sid != "":
			_spawn_structure_node(sid, tpos, false, bool(sdata.get("player_built", true)))
			var s: StructureEntity = _placed_structures.get(Config.vec2i_to_key(tpos), null) as StructureEntity
			if s != null and sdata.has("hp"):
				s.current_hp = float(sdata["hp"])

	if _storage_mgr != null:
		_storage_mgr.from_dict(data.get("containers", {}))
