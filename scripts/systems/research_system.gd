class_name ResearchSystem
extends Node

static var instance: ResearchSystem = null

var _techs: Dictionary = {} # tech_id -> Dictionary
var _researched: Array[String] = ["primitive_survival"]


func _ready() -> void:
	instance = self
	_load_tech_tree()
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


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
	return _techs.get(tech_id, {})


func get_researched_techs() -> Array[String]:
	return _researched


func is_researched(tech_id: String) -> bool:
	return _researched.has(tech_id)


func can_research(tech_id: String, player: Node) -> Dictionary:
	if not _techs.has(tech_id):
		return {"ok": false, "reason": "Unknown technology"}
	if is_researched(tech_id):
		return {"ok": false, "reason": "Already researched"}

	var tech_def: Dictionary = _techs[tech_id]
	var prereqs: Array = tech_def.get("prerequisites", [])
	for pre in prereqs:
		var pre_str: String = str(pre)
		if not is_researched(pre_str):
			var pre_name: String = str(_techs.get(pre_str, {}).get("name", pre_str))
			return {"ok": false, "reason": "Requires: " + pre_name}

	if player != null:
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		if inv == null:
			return {"ok": false, "reason": "No inventory"}
		var costs: Dictionary = tech_def.get("costs", {})
		for item_id in costs:
			var req_cnt: int = int(costs[item_id])
			if not inv.has_item(str(item_id), req_cnt):
				return {"ok": false, "reason": "Requires %s x%d" % [str(item_id).capitalize(), req_cnt]}

	return {"ok": true, "reason": ""}


func research_tech(tech_id: String, player: Node) -> bool:
	var check: Dictionary = can_research(tech_id, player)
	if not bool(check.get("ok", false)):
		var reason: String = str(check.get("reason", "Cannot research"))
		SignalBus.notification_posted.emit(reason)
		return false

	var tech_def: Dictionary = _techs[tech_id]
	if player != null:
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
	if bundle.has("research"):
		var rdata: Dictionary = bundle["research"]
		var list: Array = rdata.get("researched", ["primitive_survival"])
		_researched.clear()
		for item in list:
			_researched.append(str(item))
		if not _researched.has("primitive_survival"):
			_researched.append("primitive_survival")
		SignalBus.tech_tree_updated.emit()
