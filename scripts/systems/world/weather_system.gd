class_name WeatherSystem
extends Node2D

const WEATHER_CLEAR: String = "clear"
const WEATHER_CLOUDY: String = "cloudy"
const WEATHER_RAIN: String = "rain"
const WEATHER_STORM: String = "storm"
const WEATHER_FOG: String = "fog"

var current_weather: String = WEATHER_CLEAR
var weather_hours_left: int = 4
var _is_interior: bool = false
var _particles: GPUParticles2D = null
var _fog_particles: GPUParticles2D = null
var _canvas_modulate: CanvasModulate = null
var _current_ambient: Color = Color(1.0, 1.0, 1.0)
var _lightning_timer: float = 14.0
var _lightning_flash: float = 0.0


func _ready() -> void:
	z_index = 20
	_setup_canvas_modulate()
	_setup_weather_particles()
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.interior_entered.connect(_on_interior_entered)
	SignalBus.interior_exited.connect(_on_interior_exited)
	_current_ambient = _compute_target_ambient(GameManager.get_hour())
	if _canvas_modulate != null:
		_canvas_modulate.color = _current_ambient


func _setup_canvas_modulate() -> void:
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "WorldCanvasModulate"
	_canvas_modulate.color = Color.WHITE
	add_child(_canvas_modulate)


func _setup_weather_particles() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "WeatherCanvas"
	canvas.layer = 15
	add_child(canvas)

	# Rain particles
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

	var rain_img: Image = Image.create(2, 8, false, Image.FORMAT_RGBA8)
	rain_img.fill(Color(0.85, 0.92, 1.0, 0.85))
	_particles.texture = ImageTexture.create_from_image(rain_img)
	canvas.add_child(_particles)

	# Fog / Mist particles
	_fog_particles = GPUParticles2D.new()
	_fog_particles.name = "FogParticles"
	_fog_particles.amount = 45
	_fog_particles.lifetime = 5.5
	_fog_particles.position = Vector2(640, 360)
	_fog_particles.emitting = false

	var fog_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	fog_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fog_mat.emission_box_extents = Vector3(720.0, 400.0, 1.0)
	fog_mat.direction = Vector3(1.0, 0.08, 0.0)
	fog_mat.spread = 15.0
	fog_mat.initial_velocity_min = 22.0
	fog_mat.initial_velocity_max = 44.0
	fog_mat.gravity = Vector3.ZERO
	fog_mat.color = Color(0.88, 0.90, 0.95, 0.14)
	_fog_particles.process_material = fog_mat

	# Soft 48x48 radial gradient texture for misty fog
	var fog_img: Image = Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var fc: Vector2 = Vector2(24.0, 24.0)
	for y in range(48):
		for x in range(48):
			var dist: float = (Vector2(float(x), float(y)) - fc).length() / 24.0
			var a: float = clampf(1.0 - dist, 0.0, 1.0)
			fog_img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a * 0.7))
	_fog_particles.texture = ImageTexture.create_from_image(fog_img)
	canvas.add_child(_fog_particles)


func _process(delta: float) -> void:
	var target_amb: Color = _compute_target_ambient(GameManager.get_hour())

	# Dynamic lightning flash during severe thunderstorms
	if current_weather == WEATHER_STORM and not _is_interior:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_flash = 0.18
			_lightning_timer = randf_range(9.0, 22.0)
			var audio: Node = get_node_or_null("../AudioDirector")
			if audio != null and audio.has_method("play_tone"):
				audio.call("play_tone", 55.0, 0.55, -6.0)
			SignalBus.notification_posted.emit("Lightning splits the heavens with a deafening roar of thunder!")

	if _lightning_flash > 0.0:
		_lightning_flash = maxf(0.0, _lightning_flash - delta)
		var flash_ratio: float = _lightning_flash / 0.18
		target_amb = target_amb.lerp(Color(1.9, 1.95, 2.1), flash_ratio)

	_current_ambient = _current_ambient.lerp(target_amb, clampf(delta * 4.5, 0.0, 1.0))
	if _canvas_modulate != null:
		_canvas_modulate.color = _current_ambient


func _compute_target_ambient(hour: float) -> Color:
	if _is_interior:
		return Color(0.12, 0.12, 0.16)

	var base_sky: Color = get_base_ambient_for_hour(hour)
	var w_mult: Color = get_weather_modulate()
	return base_sky * w_mult


static func get_base_ambient_for_hour(h: float) -> Color:
	# Continuous 24-hour day/night lighting transitions:
	# 00:00 - 04:30: Deep midnight moonlit navy-blue
	# 04:30 - 06:00: Dawn lavender-indigo
	# 06:00 - 07:30: Sunrise warm golden amber rose
	# 07:30 - 09:00: Bright morning light
	# 09:00 - 16:30: Crisp full daylight
	# 16:30 - 18:30: Warm golden hour / sunset
	# 18:30 - 20:30: Twilight purple dusk
	# 20:30 - 24:00: Deep midnight moonlit navy-blue
	if h < 4.5:
		return Color(0.18, 0.20, 0.36)
	elif h < 6.0:
		var t: float = (h - 4.5) / 1.5
		return Color(0.18, 0.20, 0.36).lerp(Color(0.44, 0.36, 0.54), t)
	elif h < 7.5:
		var t: float = (h - 6.0) / 1.5
		return Color(0.44, 0.36, 0.54).lerp(Color(0.94, 0.70, 0.50), t)
	elif h < 9.0:
		var t: float = (h - 7.5) / 1.5
		return Color(0.94, 0.70, 0.50).lerp(Color(0.98, 0.95, 0.90), t)
	elif h < 16.5:
		return Color(1.0, 1.0, 1.0)
	elif h < 18.5:
		var t: float = (h - 16.5) / 2.0
		return Color(1.0, 1.0, 1.0).lerp(Color(0.96, 0.62, 0.36), t)
	elif h < 20.5:
		var t: float = (h - 18.5) / 2.0
		return Color(0.96, 0.62, 0.36).lerp(Color(0.46, 0.32, 0.50), t)
	elif h < 22.0:
		var t: float = (h - 20.5) / 1.5
		return Color(0.46, 0.32, 0.50).lerp(Color(0.20, 0.22, 0.38), t)
	else:
		return Color(0.18, 0.20, 0.36)


func get_weather_modulate() -> Color:
	match current_weather:
		WEATHER_CLOUDY:
			return Color(0.82, 0.85, 0.90)
		WEATHER_RAIN:
			return Color(0.68, 0.72, 0.82)
		WEATHER_STORM:
			return Color(0.44, 0.48, 0.60)
		WEATHER_FOG:
			return Color(0.76, 0.78, 0.82)
		_:
			return Color(1.0, 1.0, 1.0)


func _on_hour_passed(_current_hour: int) -> void:
	weather_hours_left -= 1
	if weather_hours_left <= 0:
		_transition_weather()


func _transition_weather() -> void:
	var cur_h: float = GameManager.get_hour()
	var roll: float = randf()
	var next_w: String = WEATHER_CLEAR
	var duration: int = randi_range(2, 4)

	match current_weather:
		WEATHER_CLEAR:
			if cur_h >= 4.0 and cur_h <= 8.0 and roll < 0.25:
				next_w = WEATHER_FOG
				duration = randi_range(2, 3)
			elif roll < 0.35:
				next_w = WEATHER_CLOUDY
			elif roll < 0.50:
				next_w = WEATHER_RAIN
			else:
				next_w = WEATHER_CLEAR
		WEATHER_CLOUDY:
			if roll < 0.40:
				next_w = WEATHER_RAIN
			elif roll < 0.55:
				next_w = WEATHER_STORM
				duration = randi_range(1, 2)
			elif roll < 0.75:
				next_w = WEATHER_CLEAR
			else:
				next_w = WEATHER_CLOUDY
		WEATHER_RAIN:
			if roll < 0.30:
				next_w = WEATHER_STORM
				duration = randi_range(1, 2)
			elif roll < 0.60:
				next_w = WEATHER_CLOUDY
			elif roll < 0.80:
				next_w = WEATHER_CLEAR
			else:
				next_w = WEATHER_RAIN
		WEATHER_STORM:
			if roll < 0.60:
				next_w = WEATHER_RAIN
			else:
				next_w = WEATHER_CLOUDY
			duration = randi_range(1, 2)
		WEATHER_FOG:
			if roll < 0.55:
				next_w = WEATHER_CLEAR
			else:
				next_w = WEATHER_CLOUDY

	weather_hours_left = duration
	_set_weather(next_w)


func _set_weather(type: String) -> void:
	if current_weather == type:
		return
	current_weather = type
	_update_emitters()
	SignalBus.weather_changed.emit(current_weather)

	match current_weather:
		WEATHER_CLEAR:
			SignalBus.notification_posted.emit("The skies clear as warm sunlight bathes the realm.")
		WEATHER_CLOUDY:
			SignalBus.notification_posted.emit("Overcast grey clouds gather across the horizon.")
		WEATHER_RAIN:
			SignalBus.notification_posted.emit("Rain begins to fall across the realm.")
		WEATHER_STORM:
			SignalBus.notification_posted.emit("A violent thunderstorm erupts with howling wind and thunder!")
		WEATHER_FOG:
			SignalBus.notification_posted.emit("A cold, dense fog rolls in, obscuring distant landmarks.")


func _on_interior_entered(_zone_id: String, _zone_name: String) -> void:
	_is_interior = true
	_update_emitters()


func _on_interior_exited(_zone_id: String) -> void:
	_is_interior = false
	_update_emitters()


func _update_emitters() -> void:
	if _particles != null:
		var is_raining: bool = (current_weather == WEATHER_RAIN or current_weather == WEATHER_STORM)
		_particles.emitting = (is_raining and not _is_interior)
		if current_weather == WEATHER_STORM:
			_particles.amount = 600
			var mat: ParticleProcessMaterial = _particles.process_material as ParticleProcessMaterial
			if mat != null:
				mat.initial_velocity_min = 620.0
				mat.initial_velocity_max = 840.0
		elif current_weather == WEATHER_RAIN:
			_particles.amount = 350
			var mat: ParticleProcessMaterial = _particles.process_material as ParticleProcessMaterial
			if mat != null:
				mat.initial_velocity_min = 480.0
				mat.initial_velocity_max = 620.0

	if _fog_particles != null:
		_fog_particles.emitting = (current_weather == WEATHER_FOG and not _is_interior)

