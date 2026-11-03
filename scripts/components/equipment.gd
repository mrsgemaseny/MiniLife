class_name EquipmentComponent
extends Resource

signal slot_changed(slot: String, item_id: String)
signal item_broken(slot: String, item_id: String)
signal weapon_durability_changed(new_dur: int)

const SLOTS: Array[String] = ["head", "chest", "clothing", "legs", "feet", "weapon", "offhand"]
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
	if def.has("equip_slots"):
		var slots: Array = def.get("equip_slots", [])
		for s in slots:
			if SLOTS.has(str(s)):
				return true
	var slot: String = _resolve_slot(def)
	return slot != "" and SLOTS.has(slot)


func can_equip_slot(item_id: String, target_slot: String) -> bool:
	if not SLOTS.has(target_slot):
		return false
	if target_slot == "clothing" and (item_id in ["iron_hauberk", "iron_chainmail", "steel_plate_armor", "steel_brigandine"]):
		return false
	var def: Dictionary = _get_item_def(item_id)
	if def.has("equip_slots"):
		var slots: Array = def.get("equip_slots", [])
		for s in slots:
			if str(s) == target_slot:
				return true
	return _resolve_slot(def) == target_slot


func equip(item_id: String, durability: int = -1, slot_override: String = "") -> Dictionary:
	var def: Dictionary = _get_item_def(item_id)
	var slot: String = slot_override
	if slot.is_empty():
		if def.has("equip_slots"):
			var allowed_slots: Array = def.get("equip_slots", [])
			# Prefer empty slot, else first allowed slot
			for aslot in allowed_slots:
				var s_str: String = str(aslot)
				if SLOTS.has(s_str) and get_item_id(s_str).is_empty():
					slot = s_str
					break
			if slot.is_empty() and allowed_slots.size() > 0:
				slot = str(allowed_slots[0])
		else:
			slot = _resolve_slot(def)

	if slot == "" or not SLOTS.has(slot):
		return {}

	# Anti-Cheese Rule: Cannot wear duplicate items on torso layers
	if slot == "chest" and get_item_id("clothing") == item_id:
		SignalBus.notification_posted.emit("Cannot equip duplicate layers of the same armor.")
		return {}
	if slot == "clothing" and get_item_id("chest") == item_id:
		SignalBus.notification_posted.emit("Cannot equip duplicate layers of the same armor.")
		return {}

	# Strict Hauberk & Plate Restriction: Iron Hauberk and Steel Plate/Brigandine are chest-only
	if slot == "clothing" and (item_id == "iron_hauberk" or item_id == "iron_chainmail" or item_id == "steel_plate_armor" or item_id == "steel_brigandine"):
		SignalBus.notification_posted.emit("Heavy mail and plate armor must be worn on the outer chest layer.")
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


func get_durability(slot: String) -> int:
	var entry: Dictionary = _equipped.get(slot, {})
	return int(entry.get("durability", -1))


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


func get_total_weight() -> float:
	var total: float = 0.0
	for s in SLOTS:
		var item_id: String = get_item_id(s)
		if item_id == "":
			continue
		var def: Dictionary = _get_item_def(item_id)
		total += float(def.get("weight", 0.0))
	return total


func get_stamina_cost_multiplier() -> float:
	var w: float = get_total_weight()
	if w > 18.0:
		return 1.30
	elif w > 8.0:
		return 1.15
	return 1.0


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
	weapon_durability_changed.emit(dur)
	return false


func damage_armor(wear: int = 1) -> bool:
	# Day R Wear Queue: Outer Chest Armor absorbs 100% until broken
	var chest_entry: Dictionary = _equipped.get("chest", {})
	var chest_id: String = str(chest_entry.get("item_id", ""))
	var chest_dur: int = int(chest_entry.get("durability", -1))
	if chest_id != "" and chest_dur > 0:
		chest_dur -= wear
		if chest_dur <= 0:
			_equipped["chest"] = {"item_id": "", "durability": -1}
			slot_changed.emit("chest", "")
			item_broken.emit("chest", chest_id)
			return true
		else:
			chest_entry["durability"] = chest_dur
			_equipped["chest"] = chest_entry
			return false

	# If outer chest armor is shattered / empty, clothing underarmor takes damage
	var cloth_entry: Dictionary = _equipped.get("clothing", {})
	var cloth_id: String = str(cloth_entry.get("item_id", ""))
	var cloth_dur: int = int(cloth_entry.get("durability", -1))
	if cloth_id != "" and cloth_dur > 0:
		cloth_dur -= wear
		if cloth_dur <= 0:
			_equipped["clothing"] = {"item_id": "", "durability": -1}
			slot_changed.emit("clothing", "")
			item_broken.emit("clothing", cloth_id)
			return true
		else:
			cloth_entry["durability"] = cloth_dur
			_equipped["clothing"] = cloth_entry
			return false

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
	if def.has("equip_slots"):
		var slots: Array = def.get("equip_slots", [])
		if slots.size() > 0:
			return str(slots[0])
	var t: String = str(def.get("type", ""))
	match t:
		"weapon", "tool":
			return "weapon"
		"armor_head", "helmet":
			return "head"
		"armor_clothing", "clothing", "underarmor":
			return "clothing"
		"armor_chest", "armor":
			return "chest"
		"armor_legs", "pants", "greaves":
			return "legs"
		"armor_feet", "boots", "shoes":
			return "feet"
		"shield", "offhand":
			return "offhand"
	return ""
