extends Node

enum State { BOOT, PLAYING, PAUSED, DEAD }

var _state: State = State.BOOT
var _world_seed: int = Config.DEFAULT_WORLD_SEED
var _active_slot: String = Config.DEFAULT_SAVE_SLOT
var _day: int = 1
var _hour: float = Config.START_HOUR
var _playtime_sec: float = 0.0
var _autosave_elapsed: float = 0.0
var _player_world_pos: Vector2 = Vector2.ZERO
var _open_blocking_panels: Dictionary = {}
var _paused_by_ui: bool = false
var _selected_class: String = Config.DEFAULT_CLASS
var _selected_traits: Array[String] = ["iron_will", "quick_learner", "night_owl"]

# Debug flags
var debug_god_mode: bool = false
var debug_fast_time: bool = false
var debug_reveal_map: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_default_inputs()
	var cursor_tex: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/ui/cursor_default.png"):
		var res: Resource = load("res://assets/sprites/ui/cursor_default.png")
		if res is Texture2D:
			cursor_tex = res as Texture2D
	if cursor_tex == null:
		var c_img: Image = Image.load_from_file("res://assets/sprites/ui/cursor_default.png")
		if c_img != null and not c_img.is_empty():
			cursor_tex = ImageTexture.create_from_image(c_img)
	if cursor_tex != null:
		Input.set_custom_mouse_cursor(cursor_tex, Input.CURSOR_ARROW, Vector2(1, 1))
	SignalBus.player_died.connect(_on_player_died)
	SignalBus.ui_panel_toggled.connect(_on_ui_panel_toggled)
	SignalBus.character_creation_completed.connect(_on_character_creation_completed)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func _process(delta: float) -> void:
	if _state != State.PLAYING:
		return
	_playtime_sec += delta
	_advance_clock(delta)
	_tick_autosave(delta)


func _advance_clock(delta: float) -> void:
	var scale: float = 12.0 if debug_fast_time else 1.0
	var prev_hour_int: int = int(floor(_hour))
	var hours_delta: float = (delta * scale) / Config.SECONDS_PER_GAME_HOUR
	_hour += hours_delta
	while _hour >= float(Config.HOURS_PER_DAY):
		_hour -= float(Config.HOURS_PER_DAY)
		_day += 1
		SignalBus.day_passed.emit(_day)
	var cur_hour_int: int = int(floor(_hour))
	if cur_hour_int != prev_hour_int:
		SignalBus.hour_passed.emit(cur_hour_int)


func _tick_autosave(delta: float) -> void:
	_autosave_elapsed += delta
	if _autosave_elapsed >= Config.AUTOSAVE_INTERVAL:
		_autosave_elapsed = 0.0
		SignalBus.autosave_triggered.emit()
		SignalBus.save_requested.emit(_active_slot)


func start_new_game(new_seed: int, slot: String = Config.DEFAULT_SAVE_SLOT) -> void:
	_world_seed = new_seed
	_active_slot = slot
	_day = 1
	_hour = Config.START_HOUR
	_playtime_sec = 0.0
	_autosave_elapsed = 0.0
	_open_blocking_panels.clear()
	_paused_by_ui = false
	_state = State.PLAYING
	get_tree().paused = false
	SignalBus.game_started.emit(_world_seed, _active_slot, true)


func resume_loaded_game() -> void:
	_autosave_elapsed = 0.0
	_open_blocking_panels.clear()
	_paused_by_ui = false
	_state = State.PLAYING
	get_tree().paused = false
	SignalBus.game_started.emit(_world_seed, _active_slot, false)


func get_day() -> int:
	return _day


func get_hour() -> float:
	return _hour


func set_day_and_hour(day_val: int, hour_val: float) -> void:
	_day = maxi(day_val, 1)
	_hour = clampf(hour_val, 0.0, 23.99)
	SignalBus.hour_passed.emit(int(floor(_hour)))


func get_world_seed() -> int:
	return _world_seed


func get_active_slot() -> String:
	return _active_slot


func get_selected_class() -> String:
	return _selected_class


func get_selected_traits() -> Array[String]:
	return _selected_traits.duplicate()


func is_night() -> bool:
	return _hour < Config.DAY_START_HOUR or _hour >= Config.NIGHT_START_HOUR


func get_ambient_light_color() -> Color:
	if _hour >= 7.0 and _hour <= 18.0:
		return Color(1.0, 1.0, 1.0, 1.0)
	elif _hour > 18.0 and _hour < 21.0:
		var t: float = (_hour - 18.0) / 3.0
		return Color(1.0, 0.92, 0.82, 1.0).lerp(Color(0.32, 0.36, 0.52, 1.0), t)
	elif _hour >= 5.0 and _hour < 7.0:
		var t2: float = (_hour - 5.0) / 2.0
		return Color(0.32, 0.36, 0.52, 1.0).lerp(Color(1.0, 0.95, 0.88, 1.0), t2)
	return Color(0.32, 0.36, 0.52, 1.0)


func is_paused() -> bool:
	return _state == State.PAUSED


func is_dead() -> bool:
	return _state == State.DEAD


func pause() -> void:
	if _state != State.PLAYING:
		return
	_state = State.PAUSED
	get_tree().paused = true
	SignalBus.game_paused.emit(true)


func resume() -> void:
	if _state != State.PAUSED:
		return
	_state = State.PLAYING
	get_tree().paused = false
	SignalBus.game_paused.emit(false)


func set_player_world_pos(pos: Vector2) -> void:
	_player_world_pos = pos


func get_player_world_pos() -> Vector2:
	return _player_world_pos


func get_player_tile() -> Vector2i:
	return Config.iso_to_world(_player_world_pos)


func compute_sim_lod_interval(entity_world_pos: Vector2) -> float:
	var player_tile: Vector2i = get_player_tile()
	var entity_tile: Vector2i = Config.iso_to_world(entity_world_pos)
	var dist: int = Config.tile_distance(player_tile, entity_tile)
	if float(dist) < Config.LOD_NEAR_TILES:
		return 0.0
	elif float(dist) <= Config.LOD_MID_TILES:
		return Config.LOD_MID_INTERVAL
	return Config.LOD_FAR_INTERVAL


func load_json_table(relative_path: String) -> Array:
	var table_key: String = relative_path.get_basename()
	if DataRegistry.TABLE_FILES.has(table_key):
		return DataRegistry.get_rows(table_key)
	var full_path: String = Config.DATA_ROOT + relative_path
	if not FileAccess.file_exists(full_path):
		return []
	var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		return []
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	return []


func load_json_indexed(relative_path: String, key_field: String = "id") -> Dictionary:
	var table_key: String = relative_path.get_basename()
	if key_field == "id" and DataRegistry.TABLE_FILES.has(table_key):
		return DataRegistry.get_table(table_key)
	var rows: Array = load_json_table(relative_path)
	var result: Dictionary = {}
	for row in rows:
		if row is Dictionary and row.has(key_field):
			result[str(row[key_field])] = row
	return result


func _on_character_creation_completed(class_id: String, chosen_traits: Array, world_seed: int) -> void:
	_selected_class = class_id if class_id != "" else Config.DEFAULT_CLASS
	_selected_traits.clear()
	for t in chosen_traits:
		_selected_traits.append(str(t))
	start_new_game(world_seed, Config.DEFAULT_SAVE_SLOT)


func _on_player_died() -> void:
	_state = State.DEAD
	_autosave_elapsed = 0.0
	SignalBus.world_delete_requested.emit(_active_slot)


func _on_ui_panel_toggled(panel_id: String, is_open: bool, blocks_game: bool) -> void:
	if not blocks_game:
		return
	if is_open:
		_open_blocking_panels[panel_id] = true
		if _state == State.PLAYING:
			_paused_by_ui = true
			pause()
	else:
		_open_blocking_panels.erase(panel_id)
		if _open_blocking_panels.is_empty() and _paused_by_ui and _state == State.PAUSED:
			_paused_by_ui = false
			resume()


func _on_save_data_requested(bundle: Dictionary) -> void:
	bundle["meta"] = {
		"schema_version": 1,
		"seed": _world_seed,
		"slot": _active_slot,
		"day": _day,
		"hour": _hour,
		"playtime": _playtime_sec,
		"saved_at": Time.get_datetime_string_from_system(true)
	}


func _on_save_data_loaded(bundle: Dictionary) -> void:
	var meta: Dictionary = bundle.get("meta", {})
	_world_seed = int(meta.get("seed", 1337))
	_active_slot = str(meta.get("slot", Config.DEFAULT_SAVE_SLOT))
	_day = int(meta.get("day", 1))
	_hour = float(meta.get("hour", Config.START_HOUR))
	_playtime_sec = float(meta.get("playtime", 0.0))


func _register_default_inputs() -> void:
	var key_bindings: Dictionary = {
		"move_up": KEY_W,
		"move_down": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"interact": KEY_E,
		"ui_inventory": KEY_I,
		"ui_craft": KEY_C,
		"ui_build": KEY_B,
		"ui_quests": KEY_J,
		"ui_character": KEY_K,
		"ui_factions": KEY_N,
		"ui_chronicle": KEY_H,
		"ui_achievements": KEY_L,
		"ui_close": KEY_ESCAPE,
		"quick_save": KEY_F5,
		"quick_load": KEY_F9,
		"debug_god": KEY_F1,
		"debug_fast_time": KEY_F2,
		"debug_reveal": KEY_F3
	}
	for action_name in key_bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = key_bindings[action_name]
			InputMap.action_add_event(action_name, ev)

	var mouse_bindings: Dictionary = {
		"attack": MOUSE_BUTTON_LEFT,
		"build_place": MOUSE_BUTTON_LEFT,
		"build_cancel": MOUSE_BUTTON_RIGHT,
		"demolish": MOUSE_BUTTON_MIDDLE
	}
	for action_name in mouse_bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var ev: InputEventMouseButton = InputEventMouseButton.new()
			ev.button_index = mouse_bindings[action_name]
			InputMap.action_add_event(action_name, ev)
