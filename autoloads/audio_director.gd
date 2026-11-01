extends Node

# Procedural Ambient Music & Organic Tactile SFX Engine
# Minecraft / RimWorld / C418-style ambient meditation & tactile game sounds

const SAMPLE_RATE: int = 22050
const SFX_POOL_SIZE: int = 8

var _sfx_pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer = null
var _sfx_cache: Dictionary = {}
var _music_phrases: Array[AudioStreamWAV] = []
var _music_interval_timer: float = 4.0
var _current_music_index: int = 0
var _current_biome: String = "plains"
var _in_combat: bool = false
var _combat_decay_timer: float = 0.0
var _last_footstep_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 1. Polyphonic SFX Player Pool
	for i in range(SFX_POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.volume_db = -10.0
		add_child(p)
		_sfx_pool.append(p)

	# 2. Dedicated Procedural Music Player
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -17.0
	add_child(_music_player)

	# 3. Procedurally synthesize all organic SFX & calm ambient phrases
	_bake_all_sfx()
	_bake_music_phrases()

	# 4. Wire events strictly through SignalBus
	SignalBus.resource_hit.connect(_on_resource_hit)
	SignalBus.resource_node_depleted.connect(_on_resource_depleted)
	SignalBus.resource_harvested.connect(_on_resource_harvested)
	SignalBus.footstep_stepped.connect(_on_footstep)
	SignalBus.weapon_swung.connect(_on_weapon_swung)
	SignalBus.bow_drawn.connect(_on_bow_drawn)
	SignalBus.bow_released.connect(_on_bow_released)
	SignalBus.arrow_impacted.connect(_on_arrow_impacted)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.structure_built.connect(_on_structure_built)
	SignalBus.tech_researched.connect(_on_tech_researched)
	SignalBus.ui_panel_toggled.connect(_on_ui_panel_toggled)
	SignalBus.ui_sound_requested.connect(_on_ui_sound_requested)
	SignalBus.player_damaged.connect(_on_player_damaged)
	SignalBus.player_biome_changed.connect(_on_biome_changed)


func _process(delta: float) -> void:
	if _in_combat:
		_combat_decay_timer -= delta
		if _combat_decay_timer <= 0.0:
			_in_combat = false
			SignalBus.combat_state_changed.emit(false)

	# Peaceful Ambient Music Scheduler (Minecraft / C418 style quiet rest between phrases)
	if _music_player != null and not _music_player.playing:
		_music_interval_timer -= delta
		if _music_interval_timer <= 0.0 and not _music_phrases.is_empty():
			_play_next_ambient_phrase()


func play_sfx(sfx_id: String, volume_offset_db: float = 0.0, pitch_variance: float = 0.06) -> void:
	if not _sfx_cache.has(sfx_id):
		return
	var stream: AudioStreamWAV = _sfx_cache[sfx_id] as AudioStreamWAV
	if stream == null:
		return

	# Find available player or pick the least recently started
	var target_p: AudioStreamPlayer = null
	for p in _sfx_pool:
		if not p.playing:
			target_p = p
			break
	if target_p == null and not _sfx_pool.is_empty():
		target_p = _sfx_pool[0]

	if target_p != null:
		target_p.stream = stream
		target_p.volume_db = -10.0 + volume_offset_db
		target_p.pitch_scale = clampf(1.0 + randf_range(-pitch_variance, pitch_variance), 0.75, 1.35)
		target_p.play()


func play_tone(freq_hz: float, duration_sec: float = 0.08, volume_db: float = -12.0) -> void:
	play_sfx("ui_click", volume_db - (-10.0), 0.04)


func _play_next_ambient_phrase() -> void:
	if _music_phrases.is_empty() or _music_player == null:
		return
	var phrase: AudioStreamWAV = _music_phrases[_current_music_index % _music_phrases.size()]
	_current_music_index = (_current_music_index + 1) % _music_phrases.size()

	_music_player.stream = phrase
	_music_player.pitch_scale = randf_range(0.97, 1.03)
	_music_player.play()
	# Quiet peaceful interval between 20 and 35 seconds
	_music_interval_timer = randf_range(20.0, 35.0)


# ==============================================================================
# PROCEDURAL AUDIO SYNTHESIS
# ==============================================================================

func _create_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var total: int = samples.size()
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(total * 2)
	for i in range(total):
		var s: float = clampf(samples[i], -1.0, 1.0)
		var ival: int = int(s * 32767.0)
		if ival < 0:
			ival += 65536
		pcm[i * 2] = ival & 0xFF
		pcm[i * 2 + 1] = (ival >> 8) & 0xFF

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	return wav


func _bake_all_sfx() -> void:
	# 1. Wood Chop (warm axe impact with timber resonance)
	_sfx_cache["wood_chop"] = _synth_wood_chop()

	# 2. Stone Hit (crisp pickaxe clink with rock fracture crack)
	_sfx_cache["stone_hit"] = _synth_stone_hit()

	# 3. Ore Hit (bright crystalline chime with metallic ring)
	_sfx_cache["ore_hit"] = _synth_ore_hit()

	# 4. Bush Rustle (soft foliage and branch rustle)
	_sfx_cache["bush_rustle"] = _synth_bush_rustle()

	# 5. Resource Break (satisfying crunch & crumble when depleted)
	_sfx_cache["resource_break"] = _synth_resource_break()

	# 6. Footstep (soft muted turf tap)
	_sfx_cache["footstep"] = _synth_footstep()

	# 7. Bow Draw (wooden tension sweep)
	_sfx_cache["bow_draw"] = _synth_bow_draw()

	# 8. Bow Shoot (clean string twang + whoosh)
	_sfx_cache["bow_shoot"] = _synth_bow_shoot()

	# 9. Arrow Hit (solid impact thud)
	_sfx_cache["arrow_hit"] = _synth_arrow_hit()

	# 10. Weapon Swung (blade air swoosh)
	_sfx_cache["weapon_swung"] = _synth_weapon_swung()

	# 11. Item Crafted (harmonious double assembly chime)
	_sfx_cache["item_crafted"] = _synth_item_crafted()

	# 12. Structure Built (deep masonry / wood placement thud)
	_sfx_cache["structure_build"] = _synth_structure_build()

	# 13. Tech Researched (ancient ethereal 4-bell arpeggio)
	_sfx_cache["tech_research"] = _synth_tech_research()

	# 14. Item Pickup / Pop (playful ascending drop pop)
	_sfx_cache["item_pickup"] = _synth_item_pickup()

	# 15. UI Click (subtle tactile wooden tick)
	_sfx_cache["ui_click"] = _synth_ui_click()

	# 16. UI Open (soft parchment unfurl)
	_sfx_cache["ui_open"] = _synth_ui_open()

	# 17. UI Close (muffled leather close)
	_sfx_cache["ui_close"] = _synth_ui_close()


func _synth_wood_chop() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.13)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		# Rapid frequency pitch drop 180Hz -> 85Hz
		var freq: float = lerpf(180.0, 85.0, clampf(t / 0.08, 0.0, 1.0))
		phase = fmod(phase + freq / float(SAMPLE_RATE), 1.0)
		var env: float = exp(-26.0 * t)
		var noise_burst: float = randf_range(-1.0, 1.0) * exp(-90.0 * t) * 0.45
		var body: float = (sin(phase * TAU) * 0.75 + sin(phase * 2.0 * TAU) * 0.25) * env
		buf[i] = (body + noise_burst) * 0.85
	return _create_wav(buf)


func _synth_stone_hit() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.11)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase1: float = 0.0
	var phase2: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		phase1 = fmod(phase1 + 1150.0 / float(SAMPLE_RATE), 1.0)
		phase2 = fmod(phase2 + 2350.0 / float(SAMPLE_RATE), 1.0)
		var env: float = exp(-35.0 * t)
		var crack: float = randf_range(-1.0, 1.0) * exp(-120.0 * t) * 0.40
		var clink: float = (sin(phase1 * TAU) * 0.65 + sin(phase2 * TAU) * 0.35) * env
		buf[i] = (clink + crack) * 0.75
	return _create_wav(buf)


func _synth_ore_hit() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.16)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase1: float = 0.0
	var phase2: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		phase1 = fmod(phase1 + 1760.0 / float(SAMPLE_RATE), 1.0)
		phase2 = fmod(phase2 + 2640.0 / float(SAMPLE_RATE), 1.0)
		var env: float = exp(-18.0 * t)
		var chime: float = (sin(phase1 * TAU) * 0.60 + sin(phase2 * TAU) * 0.40) * env
		var friction: float = randf_range(-1.0, 1.0) * exp(-80.0 * t) * 0.25
		buf[i] = (chime + friction) * 0.70
	return _create_wav(buf)


func _synth_bush_rustle() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.12)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var lp: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = sin(clampf(t / 0.12, 0.0, 1.0) * PI)
		var raw_n: float = randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw_n, 0.18)
		buf[i] = lp * env * 0.55
	return _create_wav(buf)


func _synth_resource_break() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.28)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	var lp: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		phase = fmod(phase + 95.0 / float(SAMPLE_RATE), 1.0)
		var env: float = exp(-11.0 * t)
		var rumble: float = sin(phase * TAU) * env * 0.40
		var crack: float = randf_range(-1.0, 1.0) * exp(-16.0 * t) * (1.0 + sin(t * 70.0) * 0.5) * 0.45
		lp = lerpf(lp, crack, 0.45)
		buf[i] = (rumble + lp) * 0.85
	return _create_wav(buf)


func _synth_footstep() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.055)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	var lp: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		phase = fmod(phase + 90.0 / float(SAMPLE_RATE), 1.0)
		var env: float = exp(-55.0 * t)
		var thump: float = sin(phase * TAU) * env * 0.50
		var scuff: float = randf_range(-1.0, 1.0) * exp(-70.0 * t) * 0.20
		lp = lerpf(lp, scuff, 0.25)
		buf[i] = (thump + lp) * 0.55
	return _create_wav(buf)


func _synth_bow_draw() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.18)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		var freq: float = lerpf(220.0, 360.0, t / 0.18)
		phase = fmod(phase + freq / float(SAMPLE_RATE), 1.0)
		var env: float = sin(clampf(t / 0.18, 0.0, 1.0) * PI) * 0.40
		buf[i] = sin(phase * TAU) * env
	return _create_wav(buf)


func _synth_bow_shoot() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.14)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		var freq: float = lerpf(380.0, 130.0, pow(t / 0.14, 0.5))
		phase = fmod(phase + freq / float(SAMPLE_RATE), 1.0)
		var env: float = exp(-22.0 * t)
		var twang: float = sin(phase * TAU) * env * 0.70
		var whoosh: float = randf_range(-1.0, 1.0) * exp(-30.0 * t) * 0.20
		buf[i] = (twang + whoosh) * 0.80
	return _create_wav(buf)


func _synth_arrow_hit() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.09)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		phase = fmod(phase + 190.0 / float(SAMPLE_RATE), 1.0)
		var env: float = exp(-40.0 * t)
		var click: float = randf_range(-1.0, 1.0) * exp(-120.0 * t) * 0.35
		buf[i] = (sin(phase * TAU) * env * 0.65 + click) * 0.75
	return _create_wav(buf)


func _synth_weapon_swung() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.12)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var lp: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = sin(clampf(t / 0.12, 0.0, 1.0) * PI)
		var noise: float = randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.28)
		buf[i] = lp * env * 0.45
	return _create_wav(buf)


func _synth_item_crafted() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.20)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var p1: float = 0.0
	var p2: float = 0.0
	var split: int = int(SAMPLE_RATE * 0.08)
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		if i < split:
			p1 = fmod(p1 + 440.0 / float(SAMPLE_RATE), 1.0)
			buf[i] = sin(p1 * TAU) * exp(-28.0 * t) * 0.45
		else:
			var t2: float = float(i - split) / float(SAMPLE_RATE)
			p2 = fmod(p2 + 659.2 / float(SAMPLE_RATE), 1.0)
			buf[i] = sin(p2 * TAU) * exp(-18.0 * t2) * 0.50
	return _create_wav(buf)


func _synth_structure_build() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.22)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		phase = fmod(phase + 105.0 / float(SAMPLE_RATE), 1.0)
		var env: float = exp(-16.0 * t)
		var thud: float = sin(phase * TAU) * env * 0.65
		var tap: float = randf_range(-1.0, 1.0) * exp(-60.0 * t) * 0.30
		buf[i] = (thud + tap) * 0.80
	return _create_wav(buf)


func _synth_tech_research() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.80)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var notes: Array[float] = [392.0, 523.25, 659.25, 783.99]
	var offsets: Array[float] = [0.0, 0.16, 0.32, 0.48]
	for n in range(4):
		var start_i: int = int(offsets[n] * SAMPLE_RATE)
		var freq: float = notes[n]
		var phase: float = 0.0
		for i in range(start_i, total):
			var t: float = float(i - start_i) / float(SAMPLE_RATE)
			phase = fmod(phase + freq / float(SAMPLE_RATE), 1.0)
			var env: float = exp(-4.5 * t)
			buf[i] += (sin(phase * TAU) * 0.7 + sin(phase * 2.0 * TAU) * 0.3) * env * 0.28
	return _create_wav(buf)


func _synth_item_pickup() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.075)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		var freq: float = lerpf(460.0, 780.0, t / 0.075)
		phase = fmod(phase + freq / float(SAMPLE_RATE), 1.0)
		var env: float = sin(clampf(t / 0.075, 0.0, 1.0) * PI) * 0.50
		buf[i] = sin(phase * TAU) * env
	return _create_wav(buf)


func _synth_ui_click() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.025)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var phase: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		phase = fmod(phase + 380.0 / float(SAMPLE_RATE), 1.0)
		buf[i] = sin(phase * TAU) * exp(-80.0 * t) * 0.35
	return _create_wav(buf)


func _synth_ui_open() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.10)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var lp: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = sin(clampf(t / 0.10, 0.0, 1.0) * PI)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.25)
		buf[i] = lp * env * 0.35
	return _create_wav(buf)


func _synth_ui_close() -> AudioStreamWAV:
	var total: int = int(SAMPLE_RATE * 0.08)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(total)
	var lp: float = 0.0
	for i in range(total):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = exp(-30.0 * t)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.20)
		buf[i] = lp * env * 0.30
	return _create_wav(buf)


# ==============================================================================
# PROCEDURAL CALM AMBIENT MUSIC PHRASES (Minecraft / C418 style meditation)
# ==============================================================================

func _bake_music_phrases() -> void:
	# Phrase 0: Dawn Awakening (D Major Pentatonic)
	_music_phrases.append(_synth_music_phrase([293.66, 369.99, 440.00, 493.88, 587.33], [0.0, 1.3, 2.5, 3.8, 5.0], 7.5))
	# Phrase 1: Green Meadows (G Major Pentatonic)
	_music_phrases.append(_synth_music_phrase([196.00, 246.94, 293.66, 329.63, 392.00, 493.88], [0.0, 1.2, 2.4, 3.6, 4.8, 6.0], 8.5))
	# Phrase 2: Ancient Pines & Hearth (C Major / A Minor)
	_music_phrases.append(_synth_music_phrase([261.63, 329.63, 392.00, 440.00, 523.25], [0.0, 1.4, 2.8, 4.2, 5.6], 8.0))
	# Phrase 3: Dusk Solitude (E Minor Pentatonic)
	_music_phrases.append(_synth_music_phrase([164.81, 246.94, 329.63, 392.00, 493.88], [0.0, 1.5, 3.0, 4.4, 5.8], 8.2))
	# Phrase 4: Starlit Wilderness (A Minor Pentatonic)
	_music_phrases.append(_synth_music_phrase([220.00, 261.63, 329.63, 392.00, 440.00], [0.0, 1.3, 2.6, 4.0, 5.4], 8.0))
	# Phrase 5: Ancient Ruins Echo (D Dorian)
	_music_phrases.append(_synth_music_phrase([146.83, 220.00, 293.66, 349.23, 392.00], [0.0, 1.5, 3.2, 4.6, 6.0], 8.8))


func _synth_music_phrase(frequencies: Array[float], timings: Array[float], total_dur: float) -> AudioStreamWAV:
	var total_samples: int = int(SAMPLE_RATE * total_dur)
	var mix_buf: PackedFloat32Array = PackedFloat32Array()
	mix_buf.resize(total_samples)

	for n in range(mini(frequencies.size(), timings.size())):
		var freq: float = frequencies[n]
		var start_s: int = int(timings[n] * SAMPLE_RATE)
		var note_len_s: int = int(2.4 * SAMPLE_RATE)
		var inc: float = freq / float(SAMPLE_RATE)
		var phase: float = 0.0

		for s in range(note_len_s):
			var idx: int = start_s + s
			if idx >= total_samples:
				break
			var t: float = float(s) / float(SAMPLE_RATE)
			var env: float = 0.0
			if t < 0.045:
				env = t / 0.045
			else:
				env = exp(-1.75 * (t - 0.045))
			# Felt piano / acoustic bell tone: fundamental + subtle warm octave + 3rd harmonic
			var sample: float = (sin(phase * TAU) * 0.72 + sin(phase * 2.0 * TAU) * 0.22 + sin(phase * 3.0 * TAU) * 0.06) * env * 0.32
			mix_buf[idx] += sample
			phase = fmod(phase + inc, 1.0)

	return _create_wav(mix_buf)


# ==============================================================================
# EVENT LISTENERS
# ==============================================================================

func _on_resource_hit(node_id: String, _tool_type: String, _world_pos: Vector2) -> void:
	if node_id.find("oak") != -1 or node_id.find("pine") != -1 or node_id.find("tree") != -1 or node_id.find("stump") != -1:
		play_sfx("wood_chop", 0.0, 0.07)
	elif node_id.find("ore") != -1 or node_id.find("iron") != -1 or node_id.find("copper") != -1 or node_id.find("coal") != -1 or node_id.find("gold") != -1:
		play_sfx("ore_hit", 1.0, 0.06)
	elif node_id.find("rock") != -1 or node_id.find("boulder") != -1 or node_id.find("stone") != -1:
		play_sfx("stone_hit", 0.0, 0.07)
	elif node_id.find("bush") != -1 or node_id.find("berry") != -1 or node_id.find("herb") != -1:
		play_sfx("bush_rustle", -2.0, 0.09)
	else:
		play_sfx("wood_chop", 0.0, 0.08)


func _on_resource_depleted(_tile_pos: Vector2i, _res_id: String) -> void:
	play_sfx("resource_break", 2.0, 0.05)


func _on_resource_harvested(_item_id: String, _amount: int, _pos: Vector2i) -> void:
	play_sfx("item_pickup", 0.0, 0.06)


func _on_footstep(_pos: Vector2, _surface: String) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_footstep_msec < 140:
		return
	_last_footstep_msec = now
	play_sfx("footstep", -3.0, 0.08)


func _on_weapon_swung(weapon_type: String) -> void:
	if weapon_type.find("bow") != -1 or weapon_type.find("crossbow") != -1:
		return
	play_sfx("weapon_swung", -2.0, 0.08)


func _on_bow_drawn() -> void:
	play_sfx("bow_draw", -2.0, 0.05)


func _on_bow_released(_charge_ratio: float) -> void:
	play_sfx("bow_shoot", 1.0, 0.06)


func _on_arrow_impacted(_pos: Vector2, hit_type: String) -> void:
	play_sfx("arrow_hit", 1.0 if hit_type == "flesh" else 0.0, 0.07)


func _on_item_crafted(_item_id: String) -> void:
	play_sfx("item_crafted", 1.0, 0.04)


func _on_structure_built(_structure_id: String, _pos: Vector2i) -> void:
	play_sfx("structure_build", 2.0, 0.05)


func _on_tech_researched(_tech_id: String) -> void:
	play_sfx("tech_research", 3.0, 0.03)


func _on_ui_panel_toggled(_panel_id: String, is_open: bool, _blocks_game: bool) -> void:
	if is_open:
		play_sfx("ui_open", -2.0, 0.05)
	else:
		play_sfx("ui_close", -3.0, 0.05)


func _on_ui_sound_requested(sound_type: String) -> void:
	if sound_type == "click":
		play_sfx("ui_click", -1.0, 0.06)
	elif sound_type == "open":
		play_sfx("ui_open", -2.0, 0.05)
	elif sound_type == "close":
		play_sfx("ui_close", -3.0, 0.05)


func _on_player_damaged(_amount: float, _source: String) -> void:
	if not _in_combat:
		_in_combat = true
		SignalBus.combat_state_changed.emit(true)
	_combat_decay_timer = 8.0
	play_sfx("arrow_hit", 2.0, 0.10)


func _on_biome_changed(biome_id: String) -> void:
	_current_biome = biome_id

