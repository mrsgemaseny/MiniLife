class_name BuildingSystem
extends Node2D

var _structures_table: Dictionary = {}
var _structure_scenes: Dictionary = {}
var _placed_nodes: Dictionary = {}
var _active_build_id: String = ""
var _cursor_tile: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_structures_table = GameManager.load_json_indexed("structures.json")
	_preload_structure_scenes()
	SignalBus.build_mode_changed.connect(_on_build_mode_changed)
	SignalBus.structure_placement_validated.connect(_on_structure_placement_validated)
	SignalBus.structure_restored.connect(_on_structure_restored)
	SignalBus.structure_destroyed.connect(_on_structure_destroyed)
	SignalBus.trap_triggered.connect(_on_trap_triggered)


func _process(_delta: float) -> void:
	if _active_build_id == "":
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	var next_tile: Vector2i = Config.iso_to_world(mouse_world)
	if next_tile != _cursor_tile:
		_cursor_tile = next_tile
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _active_build_id == "":
		return
	if event.is_action_pressed("build_cancel"):
		set_build_mode("")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_place"):
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and has_materials(player, _active_build_id):
			SignalBus.build_requested.emit(_active_build_id, _cursor_tile, player)
		else:
			SignalBus.notification_posted.emit("Insufficient materials")
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if _active_build_id == "":
		return
	var center: Vector2 = Config.world_to_iso(_cursor_tile)
	var hw: float = float(Config.HALF_TILE.x)
	var hh: float = float(Config.HALF_TILE.y)
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -hh),
		center + Vector2(hw, 0.0),
		center + Vector2(0.0, hh),
		center + Vector2(-hw, 0.0)
	])
	draw_colored_polygon(pts, Color(0.2, 0.85, 0.4, 0.35))


func set_build_mode(structure_id: String) -> void:
	if structure_id != "" and not _structures_table.has(structure_id):
		return
	_active_build_id = structure_id
	queue_redraw()


func snap_to_iso_grid(world_pos: Vector2) -> Vector2:
	var tile: Vector2i = Config.iso_to_world(world_pos)
	return Config.world_to_iso(tile)


func has_materials(builder: Node, structure_id: String) -> bool:
	if builder == null or not _structures_table.has(structure_id):
		return false
	var inv: InventoryComponent = builder.get("inventory") as InventoryComponent
	if inv == null:
		return false
	var def: Dictionary = _structures_table[structure_id]
	for mat in def.get("materials", []):
		if mat is Dictionary:
			if not inv.has_item(str(mat.get("item_id", "")), int(mat.get("count", 1))):
				return false
	return true


func consume_materials(builder: Node, structure_id: String) -> void:
	if builder == null or not _structures_table.has(structure_id):
		return
	var inv: InventoryComponent = builder.get("inventory") as InventoryComponent
	if inv == null:
		return
	var def: Dictionary = _structures_table[structure_id]
	for mat in def.get("materials", []):
		if mat is Dictionary:
			inv.remove_item(str(mat.get("item_id", "")), int(mat.get("count", 1)))


func _preload_structure_scenes() -> void:
	for sid in _structures_table:
		var path: String = "res://scenes/structures/%s.tscn" % sid
		if ResourceLoader.exists(path):
			_structure_scenes[sid] = load(path)


func _on_build_mode_changed(structure_id: String) -> void:
	set_build_mode(structure_id)


func _on_structure_placement_validated(structure_id: String, tile_pos: Vector2i, builder: Node) -> void:
	if builder != null:
		consume_materials(builder, structure_id)
		var skills: SkillsComponent = builder.get("skills") as SkillsComponent
		if skills != null:
			skills.gain_xp("construction", 12.0)
	_spawn_structure_node(structure_id, tile_pos)


func _on_structure_restored(structure_id: String, tile_pos: Vector2i) -> void:
	_spawn_structure_node(structure_id, tile_pos)


func _on_structure_destroyed(_structure_id: String, tile_pos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	if _placed_nodes.has(key):
		var node: Node = _placed_nodes[key]
		if is_instance_valid(node):
			node.queue_free()
		_placed_nodes.erase(key)


func _spawn_structure_node(structure_id: String, tile_pos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(tile_pos)
	if _placed_nodes.has(key) and is_instance_valid(_placed_nodes[key]):
		return
	if not _structure_scenes.has(structure_id):
		return
	var packed: PackedScene = _structure_scenes[structure_id]
	var inst: Node2D = packed.instantiate() as Node2D
	if inst == null:
		return
	inst.global_position = Config.world_to_iso(tile_pos)
	inst.set_meta("structure_id", structure_id)
	inst.set_meta("tile_pos", tile_pos)
	add_child(inst)
	_placed_nodes[key] = inst


func _on_trap_triggered(trap_id: String, tile_pos: Vector2i, target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var def: Dictionary = _structures_table.get(trap_id, {})
	var trap_data: Dictionary = def.get("trap", {})
	var dmg: float = float(trap_data.get("damage", 25.0))
	var dtype: String = str(trap_data.get("damage_type", "physical"))
	if dmg > 0.0:
		SignalBus.damage_requested.emit(target, dmg, dtype, self)
	var status: String = str(trap_data.get("status_effect", ""))
	if status != "":
		var dur: float = float(trap_data.get("status_duration", 2.0))
		SignalBus.status_apply_requested.emit(target, status, dur, 1.0)
	if bool(trap_data.get("single_use", false)):
		SignalBus.structure_removal_requested.emit(tile_pos, null)
