extends Node
## The current local map is acoustically plains, regardless of individual tiles.
## Original music and nature occupy separate buses and independent schedules.

const MUSIC_DIR: String = "res://assets/audio/music/"
const AMBIENT_DIR: String = "res://assets/audio/ambience/"
const DAY_TRACKS: Array[String] = [
	"endless_sun", "glass_orbit", "moon_tide", "sand_circles",
	"under_the_ice", "copper_rain", "distant_shore",
]
const NIGHT_TRACKS: Array[String] = ["after_the_world", "under_the_ice", "distant_shore", "glass_orbit"]
const MUSIC_DB: float = -19.0

var _music: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _nature: Array[AudioStreamPlayer] = []
var _nature_streams: Dictionary = {}
var _bag: Array[String] = []
var _last_track: String = ""
var _active: bool = false
var _interior: bool = false
var _night: bool = false
var _wet: bool = false
var _combat: bool = false
var _hour: float = 9.0
var _music_wait: float = 12.0
var _bird_wait: float = 9.0
var _insect_wait: float = 6.0
var _music_age: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("plains_soundscape")
	_music = _player("Music", -60.0)
	_music.finished.connect(_on_music_finished)
	_wind = _player("Ambience", -60.0)
	_wind.stream = load(AMBIENT_DIR + "plains_wind.ogg") as AudioStream
	if _wind.stream is AudioStreamOggVorbis:
		(_wind.stream as AudioStreamOggVorbis).loop = true
	for i in range(3):
		_nature.append(_player("Ambience", -26.0))
	for kind in ["bird_1", "bird_2", "bird_3", "cricket_1", "cricket_2", "grasshopper"]:
		_nature_streams[kind] = load(AMBIENT_DIR + kind + ".ogg")
	_hour = GameManager.get_hour()
	_night = _hour < 6.0 or _hour >= 20.0
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.hour_passed.connect(_on_hour)
	SignalBus.game_loaded.connect(func() -> void: _on_hour(int(GameManager.get_hour())))
	SignalBus.interior_entered.connect(_on_interior_entered)
	SignalBus.interior_exited.connect(_on_interior_exited)
	SignalBus.weather_changed.connect(_on_weather)
	SignalBus.combat_state_changed.connect(func(active: bool) -> void: _combat = active)
	SignalBus.ui_panel_toggled.connect(_on_panel)
	SignalBus.player_died.connect(func() -> void: _active = false)


func _player(bus_name: String, db: float) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = bus_name
	player.volume_db = db
	add_child(player)
	return player


func _process(delta: float) -> void:
	# Menu pauses freeze playback and timers, preserving the current composition.
	var suspended: bool = get_tree().paused
	_music.stream_paused = suspended
	_wind.stream_paused = suspended
	for player in _nature:
		player.stream_paused = suspended
	if suspended:
		return
	var outdoor_db: float = -60.0 if not _active else (-44.0 if _interior else -24.0)
	_wind.volume_db = move_toward(_wind.volume_db, outdoor_db, delta * 6.0)
	if _active and not _wind.playing:
		_wind.play()
	if not _active:
		_music.volume_db = move_toward(_music.volume_db, -60.0, delta * 8.0)
		if _music.volume_db <= -60.0:
			_music.stop()
		if _wind.volume_db <= -60.0:
			_wind.stop()
		return
	if _music.playing:
		_music_age += delta
		var target: float = MUSIC_DB - (7.0 if _combat else 0.0) - (4.0 if _interior else 0.0)
		# A gentle entrance; the files already contain authored fade-outs.
		target = minf(target, lerpf(-55.0, MUSIC_DB, clampf(_music_age / 5.0, 0.0, 1.0)))
		_music.volume_db = move_toward(_music.volume_db, target, delta * 10.0)
	elif not _combat:
		_music_wait -= delta
		if _music_wait <= 0.0:
			_start_music()
	if _interior or _wet:
		for player in _nature:
			player.volume_db = move_toward(player.volume_db, -60.0, delta * 12.0)
		return
	_bird_wait -= delta
	_insect_wait -= delta
	if _bird_wait <= 0.0:
		_bird_wait = randf_range(18.0, 48.0)
		if not _night:
			_play_nature("bird_%d" % randi_range(1, 3), randf_range(-28.0, -23.0))
	if _insect_wait <= 0.0:
		var evening: bool = _night or _hour >= 17.0
		_insect_wait = randf_range(8.0, 20.0) if evening else randf_range(20.0, 42.0)
		var kind: String = "cricket_%d" % randi_range(1, 2) if evening else "grasshopper"
		_play_nature(kind, randf_range(-31.0, -26.0))


func _play_nature(kind: String, db: float) -> void:
	for player in _nature:
		if not player.playing:
			player.stream = _nature_streams.get(kind) as AudioStream
			player.volume_db = db
			player.pitch_scale = randf_range(0.95, 1.05)
			player.play()
			return


func _start_music() -> void:
	if _bag.is_empty():
		_bag.assign(NIGHT_TRACKS if _night else DAY_TRACKS)
		_bag.shuffle()
		if _bag.size() > 1 and _bag.back() == _last_track:
			var first: String = _bag[0]
			_bag[0] = _bag.back()
			_bag[_bag.size() - 1] = first
	var track: String = _bag.pop_back()
	var stream: AudioStream = load(MUSIC_DIR + track + ".ogg") as AudioStream
	if stream == null:
		_music_wait = 60.0
		return
	_last_track = track
	_music.stop()
	_music.stream = stream
	_music.pitch_scale = 1.0
	_music.volume_db = -55.0
	_music_age = 0.0
	_music.play()


func _on_music_finished() -> void:
	_music_wait = randf_range(90.0, 210.0)


func _on_game_started(_seed: int, _slot: String, _is_new: bool) -> void:
	_active = true
	_interior = false
	_combat = false
	_wet = false
	_music.stop()
	for player in _nature:
		player.stop()
	_music_wait = randf_range(12.0, 25.0)
	_bird_wait = randf_range(6.0, 15.0)
	_insect_wait = randf_range(10.0, 20.0)
	_bag.clear()
	_on_hour(int(GameManager.get_hour()))


func _on_hour(hour: int) -> void:
	_hour = float(hour)
	var night_now: bool = hour < 6 or hour >= 20
	if night_now != _night:
		_night = night_now
		_bag.clear()


func _on_interior_entered(_zone_id: String, _zone_name: String) -> void:
	_interior = true


func _on_interior_exited(_zone_id: String) -> void:
	_interior = false


func _on_weather(weather: String) -> void:
	_wet = weather == "rain" or weather == "storm"


func _on_panel(panel_id: String, is_open: bool, _blocks: bool) -> void:
	if panel_id == "main_menu":
		_active = not is_open
