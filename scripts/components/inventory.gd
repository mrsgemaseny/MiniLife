class_name InventoryComponent
extends Resource

signal contents_changed()
signal gold_changed(gold: int)

@export var max_weight: float = Config.MAX_INVENTORY_WEIGHT
@export var max_slots: int = Config.MAX_INVENTORY_SLOTS
@export var gold: int = 0
var slots: Array[Dictionary] = []


static func _get_item_def(item_id: String) -> Dictionary:
	return DataRegistry.get_item(item_id)


func add_item(item_id: String, count: int = 1, durability: int = -1) -> int:
	if count <= 0 or item_id.is_empty():
		return 0
	var def: Dictionary = _get_item_def(item_id)
	var unit_weight: float = float(def.get("weight", 1.0))
	var stackable: bool = bool(def.get("stackable", true))
	var default_dur: int = int(def.get("durability", -1))
	var remaining: int = count

	if stackable:
		for slot in slots:
			if str(slot.get("item_id", "")) == item_id:
				var can_fit: int = _max_count_by_weight(unit_weight, remaining)
				if can_fit > 0:
					slot["count"] = int(slot["count"]) + can_fit
					remaining -= can_fit
				break

	while remaining > 0:
		var batch: int = remaining if stackable else 1
		var can_fit: int = _max_count_by_weight(unit_weight, batch)
		if can_fit <= 0:
			break
		var placed: bool = false
		for i in range(slots.size()):
			if slots[i].is_empty() or str(slots[i].get("item_id", "")).is_empty():
				slots[i] = {
					"item_id": item_id,
					"count": can_fit,
					"durability": durability if durability >= 0 else default_dur
				}
				placed = true
				break
		if not placed:
			if slots.size() < max_slots:
				slots.append({
					"item_id": item_id,
					"count": can_fit,
					"durability": durability if durability >= 0 else default_dur
				})
			else:
				break
		remaining -= can_fit

	var added: int = count - remaining
	if added > 0:
		contents_changed.emit()
	return added


func remove_item(item_id: String, count: int = 1) -> int:
	if count <= 0:
		return 0
	var to_remove: int = count
	for i in range(slots.size() - 1, -1, -1):
		if to_remove <= 0:
			break
		var slot: Dictionary = slots[i]
		if str(slot.get("item_id", "")) != item_id:
			continue
		var cur: int = int(slot.get("count", 0))
		var take: int = mini(cur, to_remove)
		cur -= take
		to_remove -= take
		if cur <= 0:
			slots.remove_at(i)
		else:
			slot["count"] = cur
	var removed: int = count - to_remove
	if removed > 0:
		contents_changed.emit()
	return removed


func remove_at_index(slot_index: int, count: int = 1) -> Dictionary:
	if slot_index < 0 or slot_index >= slots.size():
		return {}
	var slot: Dictionary = slots[slot_index]
	if slot.is_empty():
		return {}
	var cur: int = int(slot.get("count", 1))
	var take: int = mini(cur, count)
	var out: Dictionary = {
		"item_id": str(slot.get("item_id", "")),
		"count": take,
		"durability": int(slot.get("durability", -1))
	}
	cur -= take
	if cur <= 0:
		slots[slot_index] = {}
	else:
		slot["count"] = cur
	contents_changed.emit()
	return out


func set_slot(slot_index: int, item_data: Dictionary) -> void:
	if slot_index < 0 or slot_index >= max_slots:
		return
	while slots.size() <= slot_index:
		slots.append({})
	if item_data.is_empty() or int(item_data.get("count", 0)) <= 0:
		slots[slot_index] = {}
	else:
		slots[slot_index] = item_data.duplicate(true)
	contents_changed.emit()


func swap_slots(idx_a: int, idx_b: int) -> void:
	if idx_a < 0 or idx_a >= max_slots or idx_b < 0 or idx_b >= max_slots:
		return
	var max_idx: int = maxi(idx_a, idx_b)
	while slots.size() <= max_idx:
		slots.append({})
	var tmp: Dictionary = slots[idx_a]
	slots[idx_a] = slots[idx_b]
	slots[idx_b] = tmp
	contents_changed.emit()


func quick_move_slot(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= slots.size() or slots[slot_index].is_empty():
		return -1
	var item: Dictionary = slots[slot_index]
	var item_id: String = str(item.get("item_id", ""))
	var is_in_hotbar: bool = (slot_index < 8)
	var target_start: int = 8 if is_in_hotbar else 0
	var target_end: int = max_slots if is_in_hotbar else 8

	while slots.size() < max_slots:
		slots.append({})

	# First try merging into existing stack in target area
	var def: Dictionary = _get_item_def(item_id)
	if bool(def.get("stackable", true)):
		for i in range(target_start, target_end):
			if not slots[i].is_empty() and str(slots[i].get("item_id", "")) == item_id:
				slots[i]["count"] = int(slots[i]["count"]) + int(item["count"])
				slots[slot_index] = {}
				contents_changed.emit()
				return i

	# Else find first empty slot in target area
	for i in range(target_start, target_end):
		if slots[i].is_empty() or str(slots[i].get("item_id", "")).is_empty():
			slots[i] = item.duplicate(true)
			slots[slot_index] = {}
			contents_changed.emit()
			return i

	return -1


func split_slot(slot_index: int, split_count: int) -> bool:
	if slot_index < 0 or slot_index >= slots.size() or slots.size() >= max_slots:
		return false
	var slot: Dictionary = slots[slot_index]
	var cur: int = int(slot.get("count", 1))
	if split_count <= 0 or split_count >= cur:
		return false
	slot["count"] = cur - split_count
	slots.append({
		"item_id": str(slot.get("item_id", "")),
		"count": split_count,
		"durability": int(slot.get("durability", -1))
	})
	contents_changed.emit()
	return true


func move_slot(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= slots.size():
		return
	if to_index < 0 or to_index >= slots.size() or from_index == to_index:
		return
	var tmp: Dictionary = slots[from_index]
	slots[from_index] = slots[to_index]
	slots[to_index] = tmp
	contents_changed.emit()


func get_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slots.size():
		return {}
	return slots[slot_index]


func count_of(item_id: String) -> int:
	var total: int = 0
	for slot in slots:
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


func count_item(item_id: String) -> int:
	return count_of(item_id)


func has_item(item_id: String, count: int = 1) -> bool:
	return count_of(item_id) >= count


func get_total_weight() -> float:
	var total: float = 0.0
	for slot in slots:
		var def: Dictionary = _get_item_def(str(slot.get("item_id", "")))
		var w: float = float(def.get("weight", 1.0))
		total += w * float(int(slot.get("count", 0)))
	return total


func get_encumbrance_speed_multiplier() -> float:
	var ratio: float = get_total_weight() / maxf(max_weight, 1.0)
	if ratio >= 1.0:
		return 0.45
	elif ratio >= 0.8:
		return 0.78
	return 1.0


func can_fit_item(item_id: String, count: int = 1) -> bool:
	var def: Dictionary = _get_item_def(item_id)
	var unit_weight: float = float(def.get("weight", 1.0))
	if get_total_weight() + unit_weight * float(count) > max_weight:
		return false
	var stackable: bool = bool(def.get("stackable", true))
	if stackable:
		for slot in slots:
			if str(slot.get("item_id", "")) == item_id:
				return true
	return slots.size() < max_slots


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func snapshot() -> Dictionary:
	var copied: Array[Dictionary] = []
	for s in slots:
		copied.append(s.duplicate())
	return {
		"slots": copied,
		"weight": get_total_weight(),
		"max_weight": max_weight,
		"max_slots": max_slots,
		"gold": gold
	}


func to_dict() -> Dictionary:
	return snapshot()


func from_dict(data: Dictionary) -> void:
	max_weight = float(data.get("max_weight", Config.MAX_INVENTORY_WEIGHT))
	max_slots = int(data.get("max_slots", Config.MAX_INVENTORY_SLOTS))
	gold = int(data.get("gold", 0))
	slots.clear()
	for s in data.get("slots", []):
		if s is Dictionary:
			slots.append({
				"item_id": str(s.get("item_id", "")),
				"count": int(s.get("count", 1)),
				"durability": int(s.get("durability", -1))
			})
	contents_changed.emit()
	gold_changed.emit(gold)


func sort_and_consolidate(include_hotbar: bool = false) -> void:
	var start_idx: int = 0 if include_hotbar else 8
	var end_idx: int = mini(slots.size(), max_slots)

	# 1. Consolidate incomplete stacks
	for i in range(start_idx, end_idx):
		if slots[i].is_empty():
			continue
		var it_id: String = str(slots[i].get("item_id", ""))
		var dur: int = int(slots[i].get("durability", -1))
		var def: Dictionary = _get_item_def(it_id)
		var stack_limit: int = int(def.get("stack_limit", 64))
		if stack_limit <= 1 or dur >= 0:
			continue # Not stackable or damaged tool

		var cur_cnt: int = int(slots[i].get("count", 1))
		if cur_cnt >= stack_limit:
			continue

		for j in range(i + 1, end_idx):
			if slots[j].is_empty():
				continue
			if str(slots[j].get("item_id", "")) == it_id and int(slots[j].get("durability", -1)) == dur:
				var donor_cnt: int = int(slots[j].get("count", 1))
				var space: int = stack_limit - cur_cnt
				var transfer: int = mini(space, donor_cnt)
				cur_cnt += transfer
				donor_cnt -= transfer
				slots[i]["count"] = cur_cnt
				if donor_cnt <= 0:
					slots[j] = {}
				else:
					slots[j]["count"] = donor_cnt
				if cur_cnt >= stack_limit:
					break

	# 2. Extract and sort items
	var items: Array[Dictionary] = []
	for i in range(start_idx, end_idx):
		if not slots[i].is_empty():
			items.append(slots[i].duplicate(true))
			slots[i] = {}

	# Sort priority: weapon/tool (0) -> armor (1) -> resource/material (2) -> consumable (3) -> other (4)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var def_a: Dictionary = _get_item_def(str(a.get("item_id", "")))
		var def_b: Dictionary = _get_item_def(str(b.get("item_id", "")))
		var cat_a: int = _get_sort_category(def_a)
		var cat_b: int = _get_sort_category(def_b)
		if cat_a != cat_b:
			return cat_a < cat_b
		var name_a: String = str(def_a.get("name", a.get("item_id", "")))
		var name_b: String = str(def_b.get("name", b.get("item_id", "")))
		if name_a != name_b:
			return name_a < name_b
		return int(a.get("count", 1)) > int(b.get("count", 1))
	)

	# 3. Place sorted items back
	for k in range(items.size()):
		slots[start_idx + k] = items[k]

	contents_changed.emit()


func _get_sort_category(def: Dictionary) -> int:
	var t: String = str(def.get("type", ""))
	if t == "weapon" or t == "tool":
		return 0
	elif t == "armor" or t == "shield":
		return 1
	elif t == "resource" or t == "material":
		return 2
	elif t == "consumable" or t == "medicine" or t == "food":
		return 3
	return 4


func _max_count_by_weight(unit_weight: float, desired: int) -> int:
	if unit_weight <= 0.0:
		return desired
	var free_weight: float = maxf(max_weight - get_total_weight(), 0.0)
	var allowed: int = int(floor(free_weight / unit_weight))
	return clampi(allowed, 0, desired)
