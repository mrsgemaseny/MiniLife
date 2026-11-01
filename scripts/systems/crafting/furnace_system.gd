class_name FurnaceSystem
extends Node

static var instance: FurnaceSystem = null

signal furnace_updated(furnace_id: String)

# furnace_id -> Dictionary { "fuel_item": String, "fuel_count": int, "burn_remaining": float, "ore_item": String, "ore_count": int, "smelt_progress": float, "out_item": String, "out_count": int }
var _furnaces: Dictionary = {}


func _ready() -> void:
	instance = self
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func get_furnace_state(furnace_id: String) -> Dictionary:
	if not _furnaces.has(furnace_id):
		_furnaces[furnace_id] = {
			"fuel_item": "",
			"fuel_count": 0,
			"burn_remaining": 0.0,
			"ore_item": "",
			"ore_count": 0,
			"smelt_progress": 0.0,
			"out_item": "",
			"out_count": 0
		}
	return _furnaces[furnace_id]


func add_fuel(furnace_id: String, player: Node, item_id: String, amount: int = 1) -> bool:
	if item_id != "coal" and item_id != "wood":
		SignalBus.notification_posted.emit("Furnace only accepts Coal or Wood as fuel.")
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
	if item_id != "iron_ore" and item_id != "copper_ore":
		SignalBus.notification_posted.emit("Furnace only smelts Iron Ore or Copper Ore.")
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

		# Consume fuel to maintain fire when smelting ore
		if ore_cnt > 0 and burn_rem <= 0.0 and fuel_cnt > 0:
			var fuel_id: String = str(state.get("fuel_item", "coal"))
			state["fuel_count"] = fuel_cnt - 1
			state["burn_remaining"] = 20.0 if fuel_id == "coal" else 8.0
			burn_rem = float(state["burn_remaining"])
			any_changed = true

		# Active smelting tick
		if burn_rem > 0.0:
			state["burn_remaining"] = maxf(0.0, burn_rem - delta)
			if ore_cnt > 0:
				var prog: float = float(state.get("smelt_progress", 0.0)) + delta / 4.0
				if prog >= 1.0:
					prog = 0.0
					state["ore_count"] = ore_cnt - 1
					var ore_id: String = str(state.get("ore_item", ""))
					var ingot_id: String = "iron_ingot" if ore_id == "iron_ore" else "bronze_ingot"
					state["out_item"] = ingot_id
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
