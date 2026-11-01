class_name BuildingSystem
extends Node2D

var _placed_nodes: Dictionary = {}
var _storage_mgr: StorageManager = StorageManager.new()
var _defense_net: DefenseNetwork = DefenseNetwork.new()
var _active_build_id: String = ""
var _cursor_tile: Vector2i = Vector2i.ZERO
var _smooth_cursor_world: Vector2 = Vector2.ZERO
var _pulse_phase: float = 0.0


func _ready() -> void:
	y_sort_enabled = true
	SignalBus.build_mode_changed.connect(_on_build_mode_changed)
	SignalBus.structure_placement_validated.connect(_on_structure_placement_validated)
	SignalBus.structure_restored.connect(_on_structure_restored)
	SignalBus.structure_destroyed.connect(_on_structure_destroyed)
	SignalBus.trap_triggered.connect(_on_trap_triggered)


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
		if player != null and has_materials(player, _active_build_id):
			SignalBus.build_requested.emit(_active_build_id, _cursor_tile, player)
		else:
			SignalBus.notification_posted.emit("Insufficient materials for " + _active_build_id)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if _active_build_id == "":
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	var valid: bool = has_materials(player, _active_build_id)
	BlueprintPlacer.draw_ghost_preview(self, _cursor_tile, valid, _smooth_cursor_world, _pulse_phase, _active_build_id)


func set_build_mode(structure_id: String) -> void:
	if structure_id != "" and DataRegistry.get_structure(structure_id).is_empty():
		return
	_active_build_id = structure_id
	_smooth_cursor_world = Vector2.ZERO
	queue_redraw()


func snap_to_iso_grid(world_pos: Vector2) -> Vector2:
	var tile: Vector2i = Config.iso_to_world(world_pos)
	return Config.world_to_iso(tile)


func has_materials(builder: Node, structure_id: String) -> bool:
	if builder == null:
		return false
	var def: Dictionary = DataRegistry.get_structure(structure_id)
	if def.is_empty():
		return false
	var inv: InventoryComponent = builder.get("inventory") as InventoryComponent
	if inv == null:
		return false
	for mat in def.get("materials", []):
		if mat is Dictionary:
			if not inv.has_item(str(mat.get("item_id", "")), int(mat.get("count", 1))):
				return false
	return true


func consume_materials(builder: Node, structure_id: String) -> void:
	if builder == null:
		return
	var def: Dictionary = DataRegistry.get_structure(structure_id)
	var inv: InventoryComponent = builder.get("inventory") as InventoryComponent
	if inv == null or def.is_empty():
		return
	for mat in def.get("materials", []):
		if mat is Dictionary:
			inv.remove_item(str(mat.get("item_id", "")), int(mat.get("count", 1)))


func _on_build_mode_changed(structure_id: String) -> void:
	set_build_mode(structure_id)


func _on_structure_placement_validated(structure_id: String, tile_pos: Vector2i, builder: Node) -> void:
	if builder != null:
		consume_materials(builder, structure_id)
		var skills: SkillsComponent = builder.get("skills") as SkillsComponent
		if skills != null:
			skills.gain_xp("construction", 14.0)
	_spawn_structure_node(structure_id, tile_pos, true)


func _on_structure_restored(structure_id: String, tile_pos: Vector2i) -> void:
	_spawn_structure_node(structure_id, tile_pos, false)


func _on_structure_destroyed(_structure_id: String, tile_pos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	_defense_net.unregister_tile(tile_pos)
	_storage_mgr.remove_container(tile_pos)
	if _placed_nodes.has(key):
		var node: Node = _placed_nodes[key]
		if is_instance_valid(node):
			node.queue_free()
		_placed_nodes.erase(key)


func _spawn_structure_node(structure_id: String, tile_pos: Vector2i, animate_build: bool = false) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	if _placed_nodes.has(key) and is_instance_valid(_placed_nodes[key]):
		return
	var inst: StructureEntity = StructureEntity.new()
	inst.structure_id = structure_id
	inst.tile_pos = tile_pos
	inst.animate_construction = animate_build
	inst.global_position = Config.world_to_iso(tile_pos)
	add_child(inst)
	_placed_nodes[key] = inst
	_defense_net.register_structure(structure_id, tile_pos)


func _on_trap_triggered(trap_id: String, tile_pos: Vector2i, target: Node) -> void:
	TrapResolver.resolve_trap_trigger(trap_id, tile_pos, target, self)
