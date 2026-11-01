class_name SaveSystem
extends Node

const SCHEMA_VERSION: int = 1

var _active_slot: String = Config.DEFAULT_SAVE_SLOT
var _dirty_chunks: Dictionary = {}


func _ready() -> void:
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.save_requested.connect(_on_save_requested)
	SignalBus.load_requested.connect(_on_load_requested)
	SignalBus.chunk_delta_changed.connect(_on_chunk_delta_changed)
	SignalBus.chunk_delta_requested.connect(_on_chunk_delta_requested)
	SignalBus.world_delete_requested.connect(_on_world_delete_requested)
	SignalBus.achievement_unlock_requested.connect(_on_achievement_unlock_requested)
	SignalBus.achievements_data_requested.connect(_on_achievements_data_requested)


static func slot_exists(slot: String) -> bool:
	var meta_path: String = _slot_dir(slot) + "meta.json"
	return FileAccess.file_exists(meta_path)


func save_slot(slot: String) -> bool:
	var target_slot: String = slot if slot != "" else _active_slot
	_active_slot = target_slot
	var bundle: Dictionary = {"meta": {}, "player": {}, "world": {}}
	SignalBus.save_data_requested.emit(bundle)
	var meta: Dictionary = bundle.get("meta", {})
	meta["schema_version"] = SCHEMA_VERSION
	bundle["meta"] = meta
	var w: Dictionary = bundle.get("world", {})
	if not w.has("world_seed"):
		w["world_seed"] = GameManager.get_world_seed()
	bundle["world"] = w

	var base_dir: String = _slot_dir(target_slot)
	DirAccess.make_dir_recursive_absolute(base_dir + "chunks")
	if not _write_json(base_dir + "meta.json", bundle["meta"]):
		return false
	if not _write_json(base_dir + "player.json", bundle["player"]):
		return false
	if not _write_json(base_dir + "world.json", bundle["world"]):
		return false

	for key in _dirty_chunks:
		var cpos: Vector2i = Config.key_to_vec2i(str(key))
		save_chunk(cpos, _dirty_chunks[key])
	_dirty_chunks.clear()
	SignalBus.game_saved.emit()
	return true


func load_slot(slot: String) -> bool:
	if not slot_exists(slot):
		return false
	var base_dir: String = _slot_dir(slot)
	var meta: Dictionary = _read_json(base_dir + "meta.json")
	if int(meta.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	var player_data: Dictionary = _read_json(base_dir + "player.json")
	var world_data: Dictionary = _read_json(base_dir + "world.json")
	var loaded_seed: int = int(world_data.get("world_seed", Config.DEFAULT_WORLD_SEED))
	GameManager._world_seed = loaded_seed

	_active_slot = slot
	_dirty_chunks.clear()
	var bundle: Dictionary = {
		"meta": meta,
		"player": player_data,
		"world": world_data
	}
	SignalBus.save_data_loaded.emit(bundle)
	GameManager.resume_loaded_game()
	SignalBus.game_loaded.emit()
	return true


func save_chunk(pos: Vector2i, delta: Dictionary) -> void:
	var chunk_path: String = _chunk_file_path(_active_slot, pos)
	if delta.is_empty():
		if FileAccess.file_exists(chunk_path):
			DirAccess.remove_absolute(chunk_path)
		return
	DirAccess.make_dir_recursive_absolute(_slot_dir(_active_slot) + "chunks")
	_write_json(chunk_path, delta)


func load_chunk(pos: Vector2i) -> Dictionary:
	var key: String = Config.vec2i_to_key(pos)
	if _dirty_chunks.has(key):
		return (_dirty_chunks[key] as Dictionary).duplicate(true)
	var chunk_path: String = _chunk_file_path(_active_slot, pos)
	if not FileAccess.file_exists(chunk_path):
		return {}
	return _read_json(chunk_path)


func save_achievements(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(Config.SAVE_ROOT)
	_write_json(Config.ACHIEVEMENTS_PATH, data)


func load_achievements() -> Dictionary:
	if not FileAccess.file_exists(Config.ACHIEVEMENTS_PATH):
		return {"unlocked": {}}
	var d: Dictionary = _read_json(Config.ACHIEVEMENTS_PATH)
	if not d.has("unlocked"):
		d["unlocked"] = {}
	return d


func delete_world_slot(slot: String) -> void:
	_dirty_chunks.clear()
	var base_dir: String = _slot_dir(slot)
	var chunks_dir: String = base_dir + "chunks/"
	if DirAccess.dir_exists_absolute(chunks_dir):
		var cdir: DirAccess = DirAccess.open(chunks_dir)
		if cdir != null:
			for f in cdir.get_files():
				DirAccess.remove_absolute(chunks_dir + f)
		DirAccess.remove_absolute(chunks_dir)
	if DirAccess.dir_exists_absolute(base_dir):
		var bdir: DirAccess = DirAccess.open(base_dir)
		if bdir != null:
			for f in bdir.get_files():
				DirAccess.remove_absolute(base_dir + f)
		DirAccess.remove_absolute(base_dir)


func _on_game_started(_seed: int, slot: String, is_new: bool) -> void:
	_active_slot = slot
	_dirty_chunks.clear()
	if is_new:
		delete_world_slot(slot)


func _on_save_requested(slot: String) -> void:
	save_slot(slot)


func _on_load_requested(slot: String) -> void:
	load_slot(slot)


func _on_chunk_delta_changed(chunk_pos: Vector2i, delta: Dictionary) -> void:
	_dirty_chunks[Config.vec2i_to_key(chunk_pos)] = delta.duplicate(true)


func _on_chunk_delta_requested(chunk_pos: Vector2i) -> void:
	var d: Dictionary = load_chunk(chunk_pos)
	SignalBus.chunk_delta_loaded.emit(chunk_pos, d)


func _on_world_delete_requested(slot: String) -> void:
	delete_world_slot(slot)


func _on_achievement_unlock_requested(achievement_id: String) -> void:
	var data: Dictionary = load_achievements()
	var unlocked: Dictionary = data.get("unlocked", {})
	if unlocked.has(achievement_id):
		return
	unlocked[achievement_id] = Time.get_datetime_string_from_system(true)
	data["unlocked"] = unlocked
	save_achievements(data)
	SignalBus.achievement_unlocked.emit(achievement_id)
	SignalBus.achievements_data_loaded.emit(data)


func _on_achievements_data_requested() -> void:
	SignalBus.achievements_data_loaded.emit(load_achievements())


static func _slot_dir(slot: String) -> String:
	return Config.SAVE_ROOT + slot + "/"


static func _chunk_file_path(slot: String, pos: Vector2i) -> String:
	return _slot_dir(slot) + "chunks/%d_%d.json" % [pos.x, pos.y]


static func _write_json(path: String, data: Variant) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}
