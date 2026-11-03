class_name FurnaceSystem
extends Node

static var instance: FurnaceSystem = null

signal furnace_updated(furnace_id: String)

const SMELT_RECIPES: Dictionary = {
	"iron_ore": "iron_ingot",
	"clay": "brick",
	"wood": "coal",
	"food_raw": "cooked_food",
	"raw_meat": "cooked_food",
	"fish": "cooked_fish"
}

const FUEL_BURN_TIMES: Dictionary = {
	"coal": 20.0,
	"wood": 8.0,
	"plank": 4.0
}

# furnace_id -> Dictionary { "fuel_item": String, "fuel_count": int, "burn_remaining": float, "max_burn_time": float, "ore_item": String, "ore_count": int, "ore2_item": String, "ore2_count": int, "smelt_progress": float, "out_item": String, "out_count": int }
var _furnaces: Dictionary = {}


func _ready() -> void:
	instance = self
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		_furnaces.clear()


static func is_valid_fuel(item_id: String) -> bool:
	return FUEL_BURN_TIMES.has(item_id)


static func is_valid_input(item_id: String) -> bool:
	return item_id in ["iron_ore", "copper_ore", "tin_ore", "coal", "iron_ingot", "quality_iron", "clay", "wood", "food_raw", "raw_meat", "fish"]


static func get_smelt_recipe(in1: String, in2: String) -> Dictionary:
	if in1.is_empty() and in2.is_empty():
		return {}

	# 1. Dual-slot Alloy & Carbon Blending Recipes (order independent)
	if (in1 == "copper_ore" and in2 == "tin_ore") or (in1 == "tin_ore" and in2 == "copper_ore"):
		return { "output": "bronze_ingot", "need1": 1, "need2": 1, "duration": 3.6 }
	if (in1 == "iron_ingot" and in2 == "coal") or (in1 == "coal" and in2 == "iron_ingot"):
		return { "output": "steel_ingot", "need1": 1, "need2": 1, "duration": 4.5 }
	if (in1 == "quality_iron" and in2 == "coal") or (in1 == "coal" and in2 == "quality_iron"):
		return { "output": "steel_ingot", "need1": 1, "need2": 1, "duration": 4.0 }
	if (in1 == "iron_ore" and in2 == "coal") or (in1 == "coal" and in2 == "iron_ore"):
		return { "output": "quality_iron", "need1": 1, "need2": 1, "duration": 3.8 }

	# 2. Single-slot Ore & Cooking Recipes (active if other slot is empty)
	if in2.is_empty():
		if in1 == "iron_ore":
			return { "output": "iron_ingot", "need1": 1, "need2": 0, "duration": 3.6 }
		elif in1 == "clay":
			return { "output": "brick", "need1": 1, "need2": 0, "duration": 3.0 }
		elif in1 == "wood":
			return { "output": "coal", "need1": 1, "need2": 0, "duration": 2.4 }
		elif in1 == "food_raw" or in1 == "raw_meat":
			return { "output": "cooked_food", "need1": 1, "need2": 0, "duration": 2.0 }
		elif in1 == "fish":
			return { "output": "cooked_fish", "need1": 1, "need2": 0, "duration": 2.0 }
	elif in1.is_empty():
		if in2 == "iron_ore":
			return { "output": "iron_ingot", "need1": 0, "need2": 1, "duration": 3.6 }
		elif in2 == "clay":
			return { "output": "brick", "need1": 0, "need2": 1, "duration": 3.0 }
		elif in2 == "wood":
			return { "output": "coal", "need1": 0, "need2": 1, "duration": 2.4 }
		elif in2 == "food_raw" or in2 == "raw_meat":
			return { "output": "cooked_food", "need1": 0, "need2": 1, "duration": 2.0 }
		elif in2 == "fish":
			return { "output": "cooked_fish", "need1": 0, "need2": 1, "duration": 2.0 }

	return {}


static func get_output_item(input_id: String) -> String:
	var r: Dictionary = get_smelt_recipe(input_id, "")
	return str(r.get("output", ""))


func get_furnace_state(furnace_id: String) -> Dictionary:
	if not _furnaces.has(furnace_id):
		_furnaces[furnace_id] = {
			"fuel_item": "",
			"fuel_count": 0,
			"burn_remaining": 0.0,
			"max_burn_time": 8.0,
			"ore_item": "",
			"ore_count": 0,
			"ore2_item": "",
			"ore2_count": 0,
			"smelt_progress": 0.0,
			"out_item": "",
			"out_count": 0
		}
	return _furnaces[furnace_id]


func set_slot_data(furnace_id: String, slot_type: String, item_id: String, count: int) -> void:
	var state: Dictionary = get_furnace_state(furnace_id)
	if slot_type == "input" or slot_type == "input1":
		state["ore_item"] = item_id if count > 0 else ""
		state["ore_count"] = count if item_id != "" else 0
	elif slot_type == "input2":
		state["ore2_item"] = item_id if count > 0 else ""
		state["ore2_count"] = count if item_id != "" else 0
	elif slot_type == "fuel":
		state["fuel_item"] = item_id if count > 0 else ""
		state["fuel_count"] = count if item_id != "" else 0
	elif slot_type == "output":
		state["out_item"] = item_id if count > 0 else ""
		state["out_count"] = count if item_id != "" else 0
	furnace_updated.emit(furnace_id)


func add_fuel(furnace_id: String, player: Node, item_id: String, amount: int = 1) -> bool:
	if not is_valid_fuel(item_id):
		SignalBus.notification_posted.emit("Furnace only accepts Coal, Wood, or Planks as fuel.")
		return false

	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv == null or not inv.has_item(item_id, amount):
		SignalBus.notification_posted.emit("Missing " + item_id.capitalize())
		return false

	var state: Dictionary = get_furnace_state(furnace_id)
	inv.remove_item(item_id, amount)
	state["fuel_item"] = item_id
	state["fuel_count"] = int(state.get("fuel_count", 0)) + amount
	furnace_updated.emit(furnace_id)
	return true


func add_ore(furnace_id: String, player: Node, item_id: String, amount: int = 1, slot_idx: int = 1) -> bool:
	if not is_valid_input(item_id):
		SignalBus.notification_posted.emit("Furnace can only smelt Ore, Raw Meat, Fish, Wood, or Charcoal.")
		return false

	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv == null or not inv.has_item(item_id, amount):
		SignalBus.notification_posted.emit("Missing " + item_id.capitalize())
		return false

	var state: Dictionary = get_furnace_state(furnace_id)
	var key_item: String = "ore_item" if slot_idx == 1 else "ore2_item"
	var key_cnt: String = "ore_count" if slot_idx == 1 else "ore2_count"

	var cur_ore: String = str(state.get(key_item, ""))
	if cur_ore != "" and cur_ore != item_id and int(state.get(key_cnt, 0)) > 0:
		SignalBus.notification_posted.emit("Slot already contains " + cur_ore.capitalize())
		return false

	inv.remove_item(item_id, amount)
	state[key_item] = item_id
	state[key_cnt] = int(state.get(key_cnt, 0)) + amount
	furnace_updated.emit(furnace_id)
	return true


func take_output(furnace_id: String, player: Node) -> int:
	var state: Dictionary = get_furnace_state(furnace_id)
	var count: int = int(state.get("out_count", 0))
	var out_id: String = str(state.get("out_item", ""))
	if count <= 0 or out_id == "":
		return 0

	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv == null:
		return 0

	if not inv.can_fit_item(out_id, count):
		SignalBus.notification_posted.emit("Inventory full!")
		return 0

	inv.add_item(out_id, count)
	state["out_count"] = 0
	state["out_item"] = ""
	SignalBus.notification_posted.emit("Collected %s x%d" % [out_id.capitalize(), count])
	furnace_updated.emit(furnace_id)
	return count


func _process(delta: float) -> void:
	var any_changed: bool = false
	for fid in _furnaces:
		var state: Dictionary = _furnaces[fid]
		var in1_id: String = str(state.get("ore_item", ""))
		var in1_cnt: int = int(state.get("ore_count", 0))
		var in2_id: String = str(state.get("ore2_item", ""))
		var in2_cnt: int = int(state.get("ore2_count", 0))
		var burn_rem: float = float(state.get("burn_remaining", 0.0))
		var fuel_cnt: int = int(state.get("fuel_count", 0))

		var recipe_info: Dictionary = get_smelt_recipe(in1_id if in1_cnt > 0 else "", in2_id if in2_cnt > 0 else "")
		var has_recipe: bool = not recipe_info.is_empty()
		var n1: int = int(recipe_info.get("need1", 0))
		var n2: int = int(recipe_info.get("need2", 0))
		var can_smelt: bool = has_recipe and (in1_cnt >= n1) and (in2_cnt >= n2)

		# Consume fuel to maintain fire when smelting
		if can_smelt and burn_rem <= 0.0 and fuel_cnt > 0:
			var fuel_id: String = str(state.get("fuel_item", "coal"))
			var btime: float = float(FUEL_BURN_TIMES.get(fuel_id, 8.0))
			state["fuel_count"] = fuel_cnt - 1
			state["max_burn_time"] = btime
			state["burn_remaining"] = btime
			burn_rem = btime
			any_changed = true

		# Active smelting tick
		if burn_rem > 0.0:
			state["burn_remaining"] = maxf(0.0, burn_rem - delta)
			if can_smelt:
				var duration: float = float(recipe_info.get("duration", 3.6))
				var prog: float = float(state.get("smelt_progress", 0.0)) + (delta / duration)
				if prog >= 1.0:
					prog = 0.0
					state["ore_count"] = in1_cnt - n1
					if int(state["ore_count"]) <= 0:
						state["ore_item"] = ""
					state["ore2_count"] = in2_cnt - n2
					if int(state["ore2_count"]) <= 0:
						state["ore2_item"] = ""

					var target_out: String = str(recipe_info.get("output", ""))
					state["out_item"] = target_out
					state["out_count"] = int(state.get("out_count", 0)) + 1
					any_changed = true
				state["smelt_progress"] = prog
			else:
				state["smelt_progress"] = 0.0
		else:
			if float(state.get("smelt_progress", 0.0)) > 0.0:
				state["smelt_progress"] = 0.0
				any_changed = true

	if any_changed:
		for fid in _furnaces:
			furnace_updated.emit(fid)


func _on_save_data_requested(bundle: Dictionary) -> void:
	bundle["furnaces"] = _furnaces.duplicate(true)


func _on_save_data_loaded(bundle: Dictionary) -> void:
	if bundle.has("furnaces"):
		_furnaces = (bundle["furnaces"] as Dictionary).duplicate(true)
