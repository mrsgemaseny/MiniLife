class_name FurnaceSystem
extends Node

static var instance: FurnaceSystem = null

signal furnace_updated(furnace_id: String)



const FUEL_BURN_TIMES: Dictionary = {
	"coal": 20.0,
	"charcoal": 20.0,
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
	SignalBus.structure_destroyed.connect(_on_structure_destroyed)


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		_furnaces.clear()


static func is_valid_fuel(item_id: String) -> bool:
	return FUEL_BURN_TIMES.has(item_id)


static func is_valid_input(item_id: String) -> bool:
	return item_id in ["clay", "wood", "food_raw", "raw_meat", "fish"]


static func get_smelt_recipe(in1: String, in2: String, count1: int = 2147483647, count2: int = 2147483647) -> Dictionary:
	return ThermalRecipes.resolve(in1, in2, count1, count2)


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
	if count < 0:
		return
	if count > 0 and ((slot_type in ["input", "input1", "input2"] and not is_valid_input(item_id)) or (slot_type == "fuel" and not is_valid_fuel(item_id))):
		return
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
	if amount <= 0:
		return false
	if not is_valid_fuel(item_id):
		SignalBus.notification_posted.emit("Furnace only accepts Coal, Wood, or Planks as fuel.")
		return false

	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv == null or not inv.has_item(item_id, amount):
		SignalBus.notification_posted.emit("Missing " + item_id.capitalize())
		return false

	var state: Dictionary = get_furnace_state(furnace_id)
	if int(state.get("fuel_count", 0)) > 0 and str(state.get("fuel_item", "")) != item_id:
		SignalBus.notification_posted.emit("Remove the stored fuel before changing its type.")
		return false
	inv.remove_item(item_id, amount)
	state["fuel_item"] = item_id
	state["fuel_count"] = int(state.get("fuel_count", 0)) + amount
	furnace_updated.emit(furnace_id)
	return true


func add_ore(furnace_id: String, player: Node, item_id: String, amount: int = 1, slot_idx: int = 1) -> bool:
	if amount <= 0 or slot_idx not in [1, 2]:
		return false
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

	var added: int = inv.add_item(out_id, count)
	if added <= 0:
		SignalBus.notification_posted.emit("Inventory full!")
		return 0

	SignalBus.item_crafted.emit(out_id)
	state["out_count"] = count - added
	if int(state["out_count"]) == 0:
		state["out_item"] = ""
	SignalBus.notification_posted.emit("Collected %s x%d" % [out_id.capitalize(), added])
	furnace_updated.emit(furnace_id)
	return added


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if GameManager.is_paused() or delta <= 0.0 or not is_finite(delta):
		return
	for fid in _furnaces.keys():
		var state: Dictionary = _furnaces[fid]
		var before: Dictionary = state.duplicate(true)
		_advance_state(state, delta)
		if state != before:
			furnace_updated.emit(str(fid))


func _advance_state(state: Dictionary, seconds: float) -> void:
	var left: float = seconds
	while left > 0.000001:
		var in1: String = str(state.get("ore_item", "")) if int(state.get("ore_count", 0)) > 0 else ""
		var in2: String = str(state.get("ore2_item", "")) if int(state.get("ore2_count", 0)) > 0 else ""
		var recipe: Dictionary = get_smelt_recipe(in1, in2, int(state.get("ore_count", 0)), int(state.get("ore2_count", 0)))
		var key: String = str(recipe.get("recipe_id", "")) + "|" + in1 + "|" + in2
		if str(state.get("recipe_key", "")) != key:
			state["smelt_progress"] = 0.0
			state["recipe_key"] = key
		var permitted: bool = not recipe.is_empty()
		var tech: String = str(recipe.get("tech", ""))
		if permitted and tech != "":
			var response: Dictionary = {}
			SignalBus.production_tech_queried.emit(tech, response)
			permitted = bool(response.get("researched", false))
		var output: String = str(recipe.get("output", ""))
		var yield_count: int = int(recipe.get("output_count", 1))
		var output_count: int = int(state.get("out_count", 0))
		var limit: int = int(DataRegistry.get_item(output).get("stack_limit", 64))
		permitted = permitted and int(state.get("ore_count", 0)) >= int(recipe.get("need1", 0)) and int(state.get("ore2_count", 0)) >= int(recipe.get("need2", 0))
		permitted = permitted and output_count + yield_count <= limit and (output_count == 0 or str(state.get("out_item", "")) == output)
		if not permitted:
			if recipe.is_empty():
				state["smelt_progress"] = 0.0
			state["burn_remaining"] = maxf(0.0, float(state.get("burn_remaining", 0.0)) - left)
			return
		var burn: float = maxf(0.0, float(state.get("burn_remaining", 0.0)))
		if burn <= 0.000001:
			var fuel: String = str(state.get("fuel_item", ""))
			if int(state.get("fuel_count", 0)) <= 0 or not is_valid_fuel(fuel):
				state["burn_remaining"] = 0.0
				return # Preserve this recipe's partial progress until refuelled.
			burn = float(FUEL_BURN_TIMES[fuel])
			state["fuel_count"] = int(state["fuel_count"]) - 1
			state["max_burn_time"] = burn
			state["burn_remaining"] = burn
			SignalBus.furnace_fuel_ignited.emit()
		var duration: float = maxf(0.1, float(recipe.get("duration", 3.0)))
		var progress: float = clampf(float(state.get("smelt_progress", 0.0)), 0.0, 1.0)
		var step: float = minf(left, minf(burn, (1.0 - progress) * duration))
		progress += step / duration
		left -= step
		state["burn_remaining"] = maxf(0.0, burn - step)
		state["smelt_progress"] = progress
		if progress >= 1.0 - 0.000001:
			state["ore_count"] = int(state.get("ore_count", 0)) - int(recipe["need1"])
			state["ore2_count"] = int(state.get("ore2_count", 0)) - int(recipe["need2"])
			if int(state["ore_count"]) == 0:
				state["ore_item"] = ""
			if int(state["ore2_count"]) == 0:
				state["ore2_item"] = ""
			state["out_item"] = output
			state["out_count"] = output_count + yield_count
			state["smelt_progress"] = 0.0


func _on_save_data_requested(bundle: Dictionary) -> void:
	bundle["furnaces"] = _furnaces.duplicate(true)


func _on_save_data_loaded(bundle: Dictionary) -> void:
	_furnaces = (bundle.get("furnaces", {}) as Dictionary).duplicate(true)
	for fid in _furnaces:
		furnace_updated.emit(str(fid))

func _on_structure_destroyed(structure_id: String, tile_pos: Vector2i) -> void:
	if structure_id != "furnace":
		return
	var id: String = "furnace_" + Config.vec2i_to_key(tile_pos)
	if not _furnaces.has(id):
		return
	var state: Dictionary = _furnaces[id]
	var items: Array = []
	for keys in [["ore_item", "ore_count"], ["ore2_item", "ore2_count"], ["fuel_item", "fuel_count"], ["out_item", "out_count"]]:
		var item: String = str(state.get(keys[0], ""))
		var count: int = int(state.get(keys[1], 0))
		if item != "" and count > 0:
			items.append({"item_id": item, "count": count, "durability": -1})
	_furnaces.erase(id)
	if not items.is_empty():
		SignalBus.loot_bag_spawned.emit(Config.world_to_iso(tile_pos), items, 0)
