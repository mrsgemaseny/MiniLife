extends Node

const AudioDirectorScript = preload("res://autoloads/audio_director.gd")
var failures: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var director: Node = AudioDirectorScript.new()
	add_child(director)
	var sound: Node = director.get_node("PlainsSoundscape")
	sound.set_process(false)
	check(AudioServer.get_bus_index("Music") >= 0, "Music volume bus missing")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Ambience")) == &"SFX", "Nature does not follow effects volume")
	check(director._sfx_pool[0].bus == &"SFX", "Game effects bypass volume control")
	check(not sound._active and not sound._wind.playing, "Nature plays before entering world")
	sound._on_game_started(1, "audio_test", true)
	sound._on_hour(12)
	sound._process(1.0)
	check(sound._wind.playing and sound._wind.stream.loop, "Wind is not a looping layer")
	var track_names: Array[String] = []
	for i in range(7):
		sound._start_music()
		await get_tree().create_timer(0.15).timeout
		check(sound._music.playing, "Music could not start")
		check(sound._music.stream.get_length() > 90.0, "Short synthesized phrase survived")
		check(not sound._music.stream.loop, "Composition loops instead of leaving a quiet interval")
		check(not track_names.has(sound._last_track), "Track repeats before playlist exhausted")
		track_names.append(sound._last_track)
	check(track_names.has("endless_sun") and track_names.has("glass_orbit"), "Approved compositions missing")
	var previous: String = sound._last_track
	sound._start_music()
	await get_tree().create_timer(0.15).timeout
	check(sound._last_track != previous, "Immediate repeat at shuffle boundary")
	var playing_stream: AudioStream = sound._music.stream
	var bird_wait: float = sound._bird_wait
	for biome in ["forest", "desert", "swamp", "plains", "forest"]:
		SignalBus.player_biome_changed.emit(biome)
	check(sound._music.stream == playing_stream and sound._bird_wait == bird_wait, "Mixed tiles restart soundscape")
	SignalBus.hour_passed.emit(23)
	check(sound._night and sound._bag.is_empty(), "Night palette not refreshed")
	check(sound._music.stream == playing_stream, "Time change interrupted current song")
	sound._start_music()
	await get_tree().create_timer(0.15).timeout
	check(sound.NIGHT_TRACKS.has(sound._last_track), "Day-only track selected at night")
	sound._music.stop()
	sound._on_music_finished()
	check(sound._music_wait >= 90.0 and sound._music_wait <= 210.0, "Quiet music interval missing")
	sound._bird_wait = 0.0
	sound._insect_wait = 0.0
	sound._process(0.1)
	var played: int = 0
	for p in sound._nature:
		if p.playing:
			played += 1
	check(played == 1, "Night should trigger insects without birds")
	for p in sound._nature:
		p.stop()
	SignalBus.weather_changed.emit("rain")
	sound._insect_wait = 0.0
	sound._process(0.1)
	check(not sound._nature[0].playing, "Insects start during rain")
	SignalBus.weather_changed.emit("clear")
	SignalBus.interior_entered.emit("cave", "Cave")
	sound._process(5.0)
	check(sound._interior and sound._wind.volume_db <= -44.0, "Outdoor wind not muffled indoors")
	check(not sound._nature[0].playing, "Nature starts indoors")
	SignalBus.interior_exited.emit("cave")
	check(not sound._interior, "Interior attenuation sticks after exit")
	SignalBus.combat_state_changed.emit(true)
	sound._music_wait = 0.0
	sound._process(1.0)
	check(not sound._music.playing, "Peaceful track starts during combat")
	SignalBus.combat_state_changed.emit(false)
	sound._process(0.1)
	get_tree().paused = true
	var wait_before: float = sound._insect_wait
	sound._process(5.0)
	check(sound._music.stream_paused and sound._insect_wait == wait_before, "Pause does not freeze audio and timers")
	get_tree().paused = false
	sound._process(0.1)
	check(not sound._music.stream_paused, "Audio does not resume")
	SignalBus.player_died.emit()
	sound._process(10.0)
	check(not sound._active and not sound._music.playing and not sound._wind.playing, "Audio does not stop after death")
	director.queue_free()
	await get_tree().process_frame
	# Let the audio mixer retire playbacks created rapidly by the playlist checks.
	await get_tree().create_timer(0.5).timeout
	print("PLAINS_AUDIO_RUNTIME: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
