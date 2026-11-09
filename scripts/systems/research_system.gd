class_name ResearchSystem
extends Node

static var instance: ResearchSystem = null

var _techs: Dictionary = {} # tech_id -> Dictionary
var _researched: Array[String] = ["herbs_gathering"]


func _ready() -> void:
	instance = self
	_load_tech_tree()
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)
	SignalBus.production_tech_queried.connect(func(tech_id: String, result: Dictionary) -> void:
		result["researched"] = is_researched(tech_id))


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		_researched = ["herbs_gathering"]
		SignalBus.tech_tree_updated.emit()


func _load_tech_tree() -> void:
	_techs.clear()
	var raw_array: Array = GameManager.load_json_table("tech_tree.json")
	for entry in raw_array:
		if entry is Dictionary:
			var tid: String = str(entry.get("id", ""))
			if tid != "":
				_techs[tid] = entry


func get_all_techs() -> Dictionary:
	return _techs


func get_tech(tech_id: String) -> Dictionary:
	if tech_id == "primitive_survival":
		return _techs.get("herbs_gathering", {})
	if tech_id == "stone_masonry":
		return _techs.get("construction_masonry", {})
	if tech_id == "pyrology_coal":
		return _techs.get("primitive_hearth", {})
	return _techs.get(tech_id, {})


func get_researched_techs() -> Array[String]:
	return _researched


func is_researched(tech_id: String) -> bool:
	if tech_id == "primitive_survival":
		return _researched.has("herbs_gathering")
	if tech_id == "stone_masonry":
		return _researched.has("construction_masonry")
	if tech_id == "pyrology_coal":
		return _researched.has("primitive_hearth")
	return _researched.has(tech_id)


func unlock_tech(tech_id: String) -> void:
	if not _researched.has(tech_id):
		_researched.append(tech_id)
		SignalBus.tech_tree_updated.emit()


func can_research(tech_id: String, player: Node) -> Dictionary:
	if not _techs.has(tech_id):
		return {"ok": false, "reason": "Неизвестная технология"}
	if is_researched(tech_id):
		return {"ok": false, "reason": "Уже изучено"}

	if player == null:
		return {"ok": false, "reason": "Нет исследователя"}
	if GameManager.sandbox_for(player):
		return {"ok": true, "reason": ""}
	var tech_def: Dictionary = _techs[tech_id]
	if ProgressionSystem.instance != null and ProgressionSystem.instance.current_level < int(tech_def.get("min_level", 2)):
		return {"ok": false, "reason": "Требуется уровень %d" % int(tech_def.get("min_level", 2))}
	var prereqs: Array = tech_def.get("prerequisites", [])
	for pre in prereqs:
		var pre_str: String = str(pre)
		if not is_researched(pre_str):
			var pre_name: String = str(_techs.get(pre_str, {}).get("name", pre_str))
			return {"ok": false, "reason": "Требуется изучить: " + pre_name}

	if player != null:
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if inv == null:
			return {"ok": false, "reason": "Нет инвентаря"}
		var costs: Dictionary = tech_def.get("costs", {})
		for item_id in costs:
			var req_cnt: int = int(costs[item_id])
			if not inv.has_item(str(item_id), req_cnt):
				var mat_name: String = preload("res://scripts/ui/material_labels.gd").describe(str(item_id))
				if item_id == "herb": mat_name = "Трава"
				elif item_id == "wood": mat_name = "Дерево"
				elif item_id == "stone": mat_name = "Камень"
				elif item_id == "cloth": mat_name = "Ткань"
				elif item_id == "plank": mat_name = "Доски"
				return {"ok": false, "reason": "Не хватает: %s (%d/%d)" % [mat_name, inv.count_of(str(item_id)), req_cnt]}

	return {"ok": true, "reason": ""}


func research_tech(tech_id: String, player: Node) -> bool:
	var check: Dictionary = can_research(tech_id, player)
	if not bool(check.get("ok", false)):
		var reason: String = str(check.get("reason", "Cannot research"))
		SignalBus.notification_posted.emit(reason)
		return false

	var tech_def: Dictionary = _techs[tech_id]
	if player != null and not GameManager.sandbox_for(player):
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if inv != null:
			var costs: Dictionary = tech_def.get("costs", {})
			for item_id in costs:
				inv.remove_item(str(item_id), int(costs[item_id]))

	_researched.append(tech_id)
	var t_name: String = str(tech_def.get("name", tech_id))
	SignalBus.tech_researched.emit(tech_id)
	SignalBus.tech_tree_updated.emit()
	SignalBus.notification_posted.emit("Mastered Technology: " + t_name)
	return true


func _on_save_data_requested(bundle: Dictionary) -> void:
	bundle["research"] = {
		"researched": _researched
	}


func _on_save_data_loaded(bundle: Dictionary) -> void:
	if not bundle.has("research"):
		_researched = ["herbs_gathering"]
		SignalBus.tech_tree_updated.emit()
		return
	if bundle.has("research"):
		var rdata: Dictionary = bundle["research"]
		var list: Array = rdata.get("researched", ["primitive_survival"])
		_researched.clear()
		var aliases := {"primitive_survival": "herbs_gathering", "stone_masonry": "construction_masonry", "pyrology_coal": "primitive_hearth", "carpentry_planks": "plank_crafting", "iron_forging": "iron_weapons"}
		for item in list:
			var tid: String = str(aliases.get(str(item), str(item)))
			if _techs.has(tid) and not _researched.has(tid):
				_researched.append(tid)
		if not _researched.has("herbs_gathering"):
			_researched.append("herbs_gathering")
		# Legacy saves did not persist character milestones. Preserve their earned tier.
		var player_data: Dictionary = bundle.get("player", {})
		if not player_data.has("progression") and ProgressionSystem.instance != null:
			var earned_level: int = 1
			for tid in _researched:
				if tid != "herbs_gathering":
					earned_level = maxi(earned_level, int(_techs.get(tid, {}).get("min_level", 2)))
			ProgressionSystem.instance.current_level = earned_level
		SignalBus.tech_tree_updated.emit()
