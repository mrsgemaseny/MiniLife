class_name FurnaceSystem
extends Node

static var instance: FurnaceSystem = null

signal furnace_updated(furnace_id: String)

const SMELT_RECIPES: Dictionary = {
	"iron_ore": "iron_ingot",
	"copper_ore": "bronze_ingot",
	"food_raw": "cooked_food",
	"wood": "coal"
}

const FUEL_BURN_TIMES: Dictionary = {
	"coal": 20.0,
	"wood": 8.0,
	"plank": 4.0
}

# furnace_id -> Dictionary { "fuel_item": String, "fuel_count": int, "burn_remaining": float, "max_burn_time": float, "ore_item": String, "ore_count": int, "smelt_progress": float, "out_item": String, "out_count": int }
var _furnaces: Dictionary = {}


func _ready() -> void:
	instance = self
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


static func is_valid_fuel(item_id: String) -> bool:
	return FUEL_BURN_TIMES.has(item_id)


static func is_valid_input(item_id: String) -> bool:
	return SMELT_RECIPES.has(item_id)


static func get_output_item(input_id: String) -> String:
	return str(SMELT_RECIPES.get(input_id, ""))


func get_furnace_state(furnace_id: String) -> Dictionary:
	if not _furnaces.has(furnace_id):
		_furnaces[furnace_id] = {
			"fuel_item": "",
			"fuel_count": 0,
			"burn_remaining": 0.0,
			"max_burn_time": 8.0,
			"ore_item": "",
			"ore_count": 0,
			"smelt_progress": 0.0,
			"out_item": "",
			"out_count": 0
		}
	return _furnaces[furnace_id]


func set_slot_data(furnace_id: String, slot_type: String, item_id: String, count: int) -> void:
	var state: Dictionary = get_furnace_state(furnace_id)
	if slot_type == "input":
		state["ore_item"] = item_id if count > 0 else ""
		state["ore_count"] = count if item_id != "" else 0
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


func add_ore(furnace_id: String, player: Node, item_id: String, amount: int = 1) -> bool:
	if not is_valid_input(item_id):
		SignalBus.notification_posted.emit("Furnace can only smelt Ore, Raw Meat, or Wood.")
		return false

	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv == null or not inv.has_item(item_id, amount):
		SignalBus.notification_posted.emit("Missing " + item_id.capitalize())
		return false

	var state: Dictionary = get_furnace_state(furnace_id)
	var cur_ore: String = str(state.get("ore_item", ""))
	if cur_ore != "" and cur_ore != item_id and int(state.get("ore_count", 0)) > 0:
		SignalBus.notification_posted.emit("Furnace already contains " + cur_ore.capitalize())
		return false

	inv.remove_item(item_id, amount)
	state["ore_item"] = item_id
	state["ore_count"] = int(state.get("ore_count", 0)) + amount
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
		var ore_cnt: int = int(state.get("ore_count", 0))
		var burn_rem: float = float(state.get("burn_remaining", 0.0))
		var fuel_cnt: int = int(state.get("fuel_count", 0))
		var cur_in: String = str(state.get("ore_item", ""))

		# Consume fuel to maintain fire when smelting
		if ore_cnt > 0 and burn_rem <= 0.0 and fuel_cnt > 0:
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
			if ore_cnt > 0 and SMELT_RECIPES.has(cur_in):
				# Base 4s per smelt. Smithing skill speeds this up.
				var base_duration: float = 3.6
				var prog: float = float(state.get("smelt_progress", 0.0)) + (delta / base_duration)
				if prog >= 1.0:
					prog = 0.0
					state["ore_count"] = ore_cnt - 1
					var target_out: String = get_output_item(cur_in)
					state["out_item"] = target_out
					state["out_count"] = int(state.get("out_count", 0)) + 1
					if int(state["ore_count"]) <= 0:
						state["ore_item"] = ""
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
