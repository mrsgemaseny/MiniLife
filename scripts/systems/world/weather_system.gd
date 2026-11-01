class_name WeatherSystem
extends Node2D

var current_weather: String = "clear"
var rain_hours_left: int = 0
var _is_interior: bool = false
var _particles: GPUParticles2D = null

func _ready() -> void:
	z_index = 20
	_setup_rain_particles()
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.interior_entered.connect(_on_interior_entered)
	SignalBus.interior_exited.connect(_on_interior_exited)

func _setup_rain_particles() -> void:
	_particles = GPUParticles2D.new()
	_particles.name = "RainParticles"
	_particles.amount = 350
	_particles.lifetime = 1.3
	_particles.position = Vector2(640, -20)
	_particles.emitting = false

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(800.0, 10.0, 1.0)
	mat.direction = Vector3(-0.35, 1.0, 0.0)
	mat.spread = 4.0
	mat.initial_velocity_min = 480.0
	mat.initial_velocity_max = 620.0
	mat.gravity = Vector3(0.0, 180.0, 0.0)
	mat.color = Color(0.70, 0.82, 0.98, 0.60)
	_particles.process_material = mat

	# 2x8 pixel streak texture for raindrops
	var img: Image = Image.create(2, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.92, 1.0, 0.85))
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_particles.texture = tex

	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "WeatherCanvas"
	canvas.layer = 15
	canvas.add_child(_particles)
	add_child(canvas)

func _on_hour_passed(current_hour: int) -> void:
	if current_weather == "rain":
		rain_hours_left -= 1
		if rain_hours_left <= 0:
			_set_weather("clear")
	else:
		if (current_hour % 2) == 0:
			var roll: float = randf()
			if roll < 0.30:
				rain_hours_left = randi_range(1, 3)
				_set_weather("rain")

func _set_weather(type: String) -> void:
	if current_weather == type:
		return
	current_weather = type
	_update_emitter()
	SignalBus.weather_changed.emit(current_weather)
	if current_weather == "rain":
		SignalBus.notification_posted.emit("Rain begins to fall across the realm.")
	else:
		SignalBus.notification_posted.emit("The rain clears and skies brighten.")

func _on_interior_entered(_zone_id: String, _zone_name: String) -> void:
	_is_interior = true
	_update_emitter()

func _on_interior_exited(_zone_id: String) -> void:
	_is_interior = false
	_update_emitter()

func _update_emitter() -> void:
	if _particles == null:
		return
	_particles.emitting = (current_weather == "rain" and not _is_interior)
