class_name EquipmentComponent
extends Resource

signal slot_changed(slot: String, item_id: String)
signal item_broken(slot: String, item_id: String)

const SLOTS: Array[String] = ["head", "chest", "legs", "weapon", "offhand"]
const UNARMED_STATS: Dictionary = {
	"damage": 5.0,
	"damage_type": "physical",
	"attack_speed": 1.0,
	"range": "melee"
}

var _equipped: Dictionary = {}


func _init() -> void:
	for s in SLOTS:
		_equipped[s] = {"item_id": "", "durability": -1}


static func _get_item_def(item_id: String) -> Dictionary:
	return DataRegistry.get_item(item_id)


func can_equip(item_id: String) -> bool:
	var def: Dictionary = _get_item_def(item_id)
	var slot: String = _resolve_slot(def)
	return slot != "" and SLOTS.has(slot)


func equip(item_id: String, durability: int = -1) -> Dictionary:
	var def: Dictionary = _get_item_def(item_id)
	var slot: String = _resolve_slot(def)
	if slot == "" or not SLOTS.has(slot):
		return {}
	var prev: Dictionary = _equipped.get(slot, {"item_id": "", "durability": -1}).duplicate()
	var dur: int = durability if durability >= 0 else int(def.get("durability", -1))
	_equipped[slot] = {"item_id": item_id, "durability": dur}
	slot_changed.emit(slot, item_id)
	return prev


func unequip(slot: String) -> Dictionary:
	if not SLOTS.has(slot):
		return {}
	var prev: Dictionary = _equipped.get(slot, {"item_id": "", "durability": -1}).duplicate()
	_equipped[slot] = {"item_id": "", "durability": -1}
	slot_changed.emit(slot, "")
	return prev


func get_item_id(slot: String) -> String:
	var entry: Dictionary = _equipped.get(slot, {})
	return str(entry.get("item_id", ""))


func get_slot_entry(slot: String) -> Dictionary:
	return _equipped.get(slot, {"item_id": "", "durability": -1}).duplicate()


func get_all_equipped() -> Dictionary:
	var out: Dictionary = {}
	for s in SLOTS:
		out[s] = get_item_id(s)
	return out


func get_defense() -> float:
	var total: float = 0.0
	for s in SLOTS:
		var item_id: String = get_item_id(s)
		if item_id == "":
			continue
		var def: Dictionary = _get_item_def(item_id)
		var stats: Dictionary = def.get("stats", {})
		total += float(stats.get("defense", 0.0))
	return total


func get_weapon_stats() -> Dictionary:
	var weapon_id: String = get_item_id("weapon")
	if weapon_id == "":
		return UNARMED_STATS.duplicate()
	var def: Dictionary = _get_item_def(weapon_id)
	var stats: Dictionary = def.get("stats", {})
	var merged: Dictionary = UNARMED_STATS.duplicate()
	for k in stats:
		merged[k] = stats[k]
	return merged


func get_tool_type() -> String:
	var weapon_id: String = get_item_id("weapon")
	if weapon_id == "":
		return ""
	var def: Dictionary = _get_item_def(weapon_id)
	var stats: Dictionary = def.get("stats", {})
	return str(stats.get("tool_type", ""))


func damage_weapon(wear: int = 1) -> bool:
	var entry: Dictionary = _equipped.get("weapon", {})
	var item_id: String = str(entry.get("item_id", ""))
	var dur: int = int(entry.get("durability", -1))
	if item_id == "" or dur < 0:
		return false
	dur -= wear
	if dur <= 0:
		_equipped["weapon"] = {"item_id": "", "durability": -1}
		slot_changed.emit("weapon", "")
		item_broken.emit("weapon", item_id)
		return true
	entry["durability"] = dur
	_equipped["weapon"] = entry
	return false


func get_sprite_layers() -> Dictionary:
	var layers: Dictionary = {}
	for s in SLOTS:
		var item_id: String = get_item_id(s)
		if item_id == "":
			continue
		var def: Dictionary = _get_item_def(item_id)
		var visual: Dictionary = def.get("visual", {})
		var sprite_path: String = str(visual.get("sprite", ""))
		if sprite_path != "":
			layers[s] = "res://assets/sprites/" + sprite_path
	return layers


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for s in SLOTS:
		out[s] = _equipped[s].duplicate()
	return out


func from_dict(data: Dictionary) -> void:
	for s in SLOTS:
		var raw: Variant = data.get(s, {"item_id": "", "durability": -1})
		if raw is Dictionary:
			_equipped[s] = {
				"item_id": str(raw.get("item_id", "")),
				"durability": int(raw.get("durability", -1))
			}
		elif raw is String:
			_equipped[s] = {"item_id": str(raw), "durability": -1}
		else:
			_equipped[s] = {"item_id": "", "durability": -1}


func _resolve_slot(def: Dictionary) -> String:
	if def.has("equip_slot"):
		return str(def["equip_slot"])
	var t: String = str(def.get("type", ""))
	match t:
		"weapon", "tool":
			return "weapon"
		"armor_head", "helmet":
			return "head"
		"armor_chest", "armor":
			return "chest"
		"armor_legs", "boots":
			return "legs"
		"shield", "offhand":
			return "offhand"
	return ""
