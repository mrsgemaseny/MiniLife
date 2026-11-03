class_name SaveSystem
extends Node

const SCHEMA_VERSION: int = 1

var _active_slot: String = Config.DEFAULT_SAVE_SLOT
var _dirty_chunks: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("save_system")
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


func quick_save() -> bool:
	var ok: bool = save_slot("quicksave", "Быстрое сохранение")
	if ok:
		SignalBus.notification_posted.emit("Быстрое сохранение записано [F5]")
	else:
		SignalBus.notification_posted.emit("Ошибка быстрого сохранения!")
	return ok


func quick_load() -> bool:
	var target: String = "quicksave"
	if not slot_exists(target):
		var saves: Array[Dictionary] = list_saves()
		if not saves.is_empty():
			target = str(saves[0].get("slot", ""))
		else:
			SignalBus.notification_posted.emit("Сохранения не найдены!")
			return false
	var ok: bool = load_slot(target)
	if ok:
		SignalBus.notification_posted.emit("Сохранение успешно загружено [F9]")
	else:
		SignalBus.notification_posted.emit("Ошибка загрузки сохранения!")
	return ok


func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var root_dir: String = Config.SAVE_ROOT
	if not DirAccess.dir_exists_absolute(root_dir):
		return saves
	var dir: DirAccess = DirAccess.open(root_dir)
	if dir == null:
		return saves
	dir.list_dir_begin()
	var folder_name: String = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var meta_path: String = root_dir + folder_name + "/meta.json"
			if FileAccess.file_exists(meta_path):
				var meta: Dictionary = _read_json(meta_path)
				var unix_ts: int = int(meta.get("unix_timestamp", 0))
				if unix_ts <= 0:
					unix_ts = int(FileAccess.get_modified_time(meta_path))
				var display_name: String = str(meta.get("name", folder_name))
				if display_name.is_empty():
					display_name = folder_name
				var day: int = int(meta.get("day", 1))
				var hour: float = float(meta.get("hour", Config.START_HOUR))
				var time_str: String = str(meta.get("time_str", "День %d, %02d:%02d" % [day, int(floor(hour)), int(fmod(hour * 60.0, 60.0))]))
				var saved_at: String = str(meta.get("saved_at", ""))
				var seed_val: int = int(meta.get("seed", Config.DEFAULT_WORLD_SEED))
				var gold_val: int = int(meta.get("gold", 0))
				var hp_val: int = int(meta.get("hp", 100))
				saves.append({
					"slot": folder_name,
					"name": display_name,
					"day": day,
					"hour": hour,
					"time_str": time_str,
					"saved_at": saved_at,
					"unix_timestamp": unix_ts,
					"seed": seed_val,
					"gold": gold_val,
					"hp": hp_val,
					"is_quicksave": (folder_name == "quicksave"),
					"is_autosave": (folder_name == "autosave")
				})
		folder_name = dir.get_next()
	dir.list_dir_end()

	# Sort newest first
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("unix_timestamp", 0)) > int(b.get("unix_timestamp", 0))
	)
	return saves


func delete_slot(slot: String) -> bool:
	delete_world_slot(slot)
	return true


func save_slot(slot: String, display_name: String = "") -> bool:
	var target_slot: String = slot if slot != "" else _active_slot
	_active_slot = target_slot
	var bundle: Dictionary = {"meta": {}, "player": {}, "world": {}, "buildings": {}, "research": {}}
	SignalBus.save_data_requested.emit(bundle)

	# Direct fallback queries in case paused nodes didn't process the signal
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node != null and player_node.has_method("get_save_data"):
		bundle["player"] = player_node.call("get_save_data")

	var world_node: Node = get_tree().get_first_node_in_group("world")
	if world_node == null:
		world_node = get_tree().root.find_child("World", true, false)
	if world_node != null and world_node.has_method("get_save_data"):
		var w_direct: Dictionary = world_node.call("get_save_data")
		for k in w_direct:
			bundle["world"][k] = w_direct[k]

	var bsys: BuildingSystem = BuildingSystem.instance
	if bsys == null:
		bsys = get_tree().root.find_child("BuildingSystem", true, false) as BuildingSystem
	if bsys != null and bsys.has_method("get_save_data"):
		bundle["buildings"] = bsys.call("get_save_data")

	var rsys: ResearchSystem = ResearchSystem.instance
	if rsys == null:
		rsys = get_tree().root.find_child("ResearchSystem", true, false) as ResearchSystem
	if rsys != null:
		bundle["research"] = {"researched": rsys.get_researched_techs()}

	# Compile rich metadata
	var meta: Dictionary = bundle.get("meta", {})
	meta["schema_version"] = SCHEMA_VERSION
	meta["slot"] = target_slot
	var s_name: String = display_name
	if s_name.is_empty():
		if target_slot == "quicksave":
			s_name = "Быстрое сохранение"
		elif target_slot == "autosave":
			s_name = "Автосохранение"
		else:
			s_name = str(meta.get("name", target_slot))
	meta["name"] = s_name
	meta["seed"] = GameManager.get_world_seed()
	meta["day"] = GameManager.get_day()
	var cur_hour: float = GameManager.get_hour()
	meta["hour"] = cur_hour
	meta["time_str"] = "День %d, %02d:%02d" % [GameManager.get_day(), int(floor(cur_hour)), int(fmod(cur_hour * 60.0, 60.0))]
	meta["saved_at"] = Time.get_datetime_string_from_system(false, true)
	meta["unix_timestamp"] = int(Time.get_unix_time_from_system())

	var p_dict: Dictionary = bundle.get("player", {})
	var inv_dict: Dictionary = p_dict.get("inventory", {})
	meta["gold"] = int(inv_dict.get("gold", 0))
	var stats_dict: Dictionary = p_dict.get("stats", {})
	meta["hp"] = int(stats_dict.get("health", 100))
	meta["max_hp"] = int(stats_dict.get("max_health", 100))
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
	if not _write_json(base_dir + "buildings.json", bundle["buildings"]):
		return false
	if bundle.has("research") and not (bundle["research"] as Dictionary).is_empty():
		_write_json(base_dir + "research.json", bundle["research"])

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
	var buildings_data: Dictionary = _read_json(base_dir + "buildings.json")
	var research_data: Dictionary = _read_json(base_dir + "research.json")

	var loaded_seed: int = int(world_data.get("world_seed", Config.DEFAULT_WORLD_SEED))
	GameManager._world_seed = loaded_seed
	GameManager.set_day_and_hour(int(meta.get("day", 1)), float(meta.get("hour", Config.START_HOUR)))

	_active_slot = slot
	_dirty_chunks.clear()
	var bundle: Dictionary = {
		"meta": meta,
		"player": player_data,
		"world": world_data,
		"buildings": buildings_data,
		"research": research_data
	}
	SignalBus.save_data_loaded.emit(bundle)

	# Direct fallback calls to ensure state is cleanly restored regardless of tree pause status
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node != null and player_node.has_method("load_save_data"):
		player_node.call("load_save_data", player_data)

	var world_node: Node = get_tree().get_first_node_in_group("world")
	if world_node == null:
		world_node = get_tree().root.find_child("World", true, false)
	if world_node != null and world_node.has_method("load_save_data"):
		world_node.call("load_save_data", world_data)

	var bsys: BuildingSystem = BuildingSystem.instance
	if bsys == null:
		bsys = get_tree().root.find_child("BuildingSystem", true, false) as BuildingSystem
	if bsys != null and bsys.has_method("load_save_data"):
		bsys.call("load_save_data", buildings_data)

	if research_data.has("researched"):
		var rsys: ResearchSystem = ResearchSystem.instance
		if rsys == null:
			rsys = get_tree().root.find_child("ResearchSystem", true, false) as ResearchSystem
		if rsys != null:
			rsys._researched.clear()
			for tid in research_data["researched"]:
				rsys._researched.append(str(tid))
			SignalBus.tech_tree_updated.emit()

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
