class_name StructureEntity
extends StaticBody2D

@export var structure_id: String = "wall"
var tile_pos: Vector2i = Vector2i.ZERO
var current_hp: float = 100.0
var max_hp: float = 100.0
var is_door_open: bool = false
var _def: Dictionary = {}
var _collision: CollisionShape2D = null


func _ready() -> void:
	y_sort_enabled = true
	_def = DataRegistry.get_structure(structure_id)
	max_hp = float(_def.get("hp", 100.0))
	current_hp = max_hp
	var passable: bool = bool(_def.get("passable", false))
	var interactable: bool = bool(_def.get("interactable", false))

	if interactable:
		add_to_group("interactable")
	if structure_id in ["workbench", "forge", "campfire"]:
		add_to_group("craft_station")

	_setup_collision(passable)
	if _def.has("trap"):
		_setup_trap_trigger()
	queue_redraw()


func _draw() -> void:
	var base_col: Color = Color.from_string(str(_def.get("color", "#6c757d")), Color(0.5, 0.5, 0.5))
	var height_px: float = float(_def.get("height_px", 18.0))
	var hw: float = float(Config.HALF_TILE.x) * 0.88
	var hh: float = float(Config.HALF_TILE.y) * 0.88

	if structure_id == "door" and is_door_open:
		base_col.a = 0.42

	var bottom_diamond: PackedVector2Array = IsoMath.diamond_polygon(Vector2.ZERO, hw, hh)
	if height_px <= 6.0:
		draw_colored_polygon(bottom_diamond, base_col)
		draw_polyline(bottom_diamond, base_col.darkened(0.28), 1.5, true)
		return

	var top_offset: Vector2 = Vector2(0.0, -height_px)
	var top_diamond: PackedVector2Array = IsoMath.diamond_polygon(top_offset, hw, hh)
	var left_face: PackedVector2Array = PackedVector2Array([
		bottom_diamond[3], bottom_diamond[2], top_diamond[2], top_diamond[3]
	])
	var right_face: PackedVector2Array = PackedVector2Array([
		bottom_diamond[2], bottom_diamond[1], top_diamond[1], top_diamond[2]
	])
	draw_colored_polygon(left_face, base_col.darkened(0.18))
	draw_colored_polygon(right_face, base_col.darkened(0.30))
	draw_colored_polygon(top_diamond, base_col.lightened(0.08))

	if structure_id == "campfire" or structure_id == "forge":
		draw_circle(top_offset, 6.0, Color(1.0, 0.48, 0.1, 0.9))
		draw_circle(top_offset + Vector2(0.0, -2.0), 3.5, Color(1.0, 0.85, 0.2, 0.95))


func get_station_id() -> String:
	if structure_id in ["workbench", "forge", "campfire"]:
		return structure_id
	return ""


func interact(actor: Node) -> void:
	match structure_id:
		"door":
			is_door_open = not is_door_open
			if _collision != null:
				_collision.set_deferred("disabled", is_door_open)
			queue_redraw()
		"workbench", "forge", "campfire":
			SignalBus.craft_station_opened.emit(structure_id)
		"storage":
			SignalBus.ui_panel_requested.emit("inventory")
		"bed":
			if actor != null:
				var stats: StatsComponent = actor.get("stats") as StatsComponent
				var needs: NeedsComponent = actor.get("needs") as NeedsComponent
				if stats != null:
					stats.modify("health", 30.0)
					stats.modify("stamina", 100.0)
				if needs != null:
					needs.rest_at_bed(1.2)
			SignalBus.notification_posted.emit("Rested at bed (+HP, +Stamina, +Rest).")


func take_structure_damage(amount: float) -> void:
	current_hp -= amount
	if current_hp <= 0.0:
		SignalBus.structure_removal_requested.emit(tile_pos, null)


func _setup_collision(passable: bool) -> void:
	_collision = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 14.0
	_collision.shape = shape
	_collision.disabled = passable
	add_child(_collision)


func _setup_trap_trigger() -> void:
	var area: Area2D = Area2D.new()
	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 16.0
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node) -> void:
		if body != null and body.is_in_group("combatant") and not body.is_in_group("player"):
			SignalBus.trap_triggered.emit(structure_id, tile_pos, body)
	)
	add_child(area)
