extends Node

var _ambient_player: AudioStreamPlayer = null
var _sfx_player: AudioStreamPlayer = null
var _current_biome: String = "plains"
var _in_combat: bool = false
var _combat_decay_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.volume_db = -14.0
	add_child(_ambient_player)

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.volume_db = -10.0
	add_child(_sfx_player)

	SignalBus.player_biome_changed.connect(_on_biome_changed)
	SignalBus.player_damaged.connect(_on_combat_activity)
	SignalBus.resource_harvested.connect(_on_resource_harvested)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.structure_built.connect(_on_structure_built)


func _process(delta: float) -> void:
	if _in_combat:
		_combat_decay_timer -= delta
		if _combat_decay_timer <= 0.0:
			_in_combat = false
			SignalBus.combat_state_changed.emit(false)


func play_tone(freq_hz: float, duration_sec: float = 0.08, volume_db: float = -12.0) -> void:
	if _sfx_player == null:
		return
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = maxf(duration_sec, 0.05)
	_sfx_player.stream = gen
	_sfx_player.volume_db = volume_db
	_sfx_player.play()
	var playback: AudioStreamGeneratorPlayback = _sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames: int = int(gen.mix_rate * duration_sec)
	var phase: float = 0.0
	var increment: float = freq_hz / gen.mix_rate
	for i in range(mini(frames, playback.get_frames_available())):
		var env: float = 1.0 - (float(i) / float(maxi(frames, 1)))
		var sample: float = sin(phase * TAU) * 0.25 * env
		playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + increment, 1.0)


func _on_biome_changed(biome_id: String) -> void:
	_current_biome = biome_id


func _on_combat_activity(_amount: float, _source: String) -> void:
	if not _in_combat:
		_in_combat = true
		SignalBus.combat_state_changed.emit(true)
	_combat_decay_timer = 8.0
	play_tone(180.0, 0.09, -10.0)


func _on_resource_harvested(_res_id: String, _amount: int, _pos: Vector2i) -> void:
	play_tone(320.0, 0.06, -13.0)


func _on_item_crafted(_item_id: String) -> void:
	play_tone(520.0, 0.1, -11.0)


func _on_structure_built(_structure_id: String, _pos: Vector2i) -> void:
	play_tone(260.0, 0.1, -11.0)
