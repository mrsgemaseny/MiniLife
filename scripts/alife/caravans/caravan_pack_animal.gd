class_name CaravanPackAnimal
extends AnimalEntity

var cargo_id: String = ""
var route_id: String = ""
var leader: Node2D

func _ready() -> void:
	animal_type = "donkey"
	has_pack = true
	super._ready()
	move_speed = 60.0
	display_name = "Caravan Pack Donkey"
	set_meta("caravan_pack_id", cargo_id)
	set_meta("caravan_route_id", route_id)

func _physics_process(delta: float) -> void:
	if is_permanently_dead or GameManager.is_paused():
		return
	if is_instance_valid(leader):
		var distance: float = global_position.distance_to(leader.global_position)
		velocity = global_position.direction_to(leader.global_position) * minf(move_speed, maxf(0.0, distance - 36.0) * 2.0)
		if distance > 48.0:
			move_and_slide()
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
	_walk_phase += delta * 5.0
	_walk_blend = move_toward(_walk_blend, 1.0 if velocity.length() > 2.0 else 0.0, delta * 5.0)
	_facing_left = velocity.x < 0.0 if velocity.length() > 2.0 else _facing_left
	queue_redraw()

func interact(_interactor: Node) -> void:
	SignalBus.alife_cargo_open_requested.emit(cargo_id)

func _draw() -> void:
	if not is_permanently_dead:
		super._draw()
		return
	var texture: Texture2D = AnimalRig.sprite_for("donkey")
	if texture == null:
		super._draw()
		return
	var width: float = 58.0
	var height: float = width * texture.get_height() / texture.get_width() * 0.6
	draw_set_transform(Vector2.ZERO, -0.14)
	draw_texture_rect(texture, Rect2(-width * 0.5, -height * 0.5, width, height), false, Color(0.72, 0.69, 0.66))
	draw_set_transform(Vector2.ZERO)

func _handle_death(killer: Node) -> void:
	if is_permanently_dead:
		return
	is_permanently_dead = true
	velocity = Vector2.ZERO
	display_name = "Fallen Caravan Donkey"
	rotation = 0.0
	remove_from_group("combatant")
	SignalBus.entity_died.emit(self, "player" if killer != null and killer.is_in_group("player") else "world")
	queue_redraw()
