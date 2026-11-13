extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var save_system: SaveSystem = main.get_node("Systems/SaveSystem") as SaveSystem
	var player: Player = main.get_node("World/Player") as Player
	var test_slot: String = "test_equipment_" + Crypto.new().generate_random_bytes(8).hex_encode()
	GameManager.start_new_game(14321, test_slot)
	main.get_node("UILayer/MainMenu").close_menu()
	GameManager.resume()
	player.inventory.set_slot(11, {"item_id": "gambeson", "count": 1, "durability": 80})
	player.use_slot_item(11)
	_check(player.equipment.get_item_id("clothing") == "gambeson", "First armor layer was not equipped")
	player.inventory.set_slot(12, {"item_id": "gambeson", "count": 1, "durability": 80})
	player.use_slot_item(12)
	_check(player.inventory.get_slot(12).get("item_id", "") == "gambeson", "Rejected duplicate armor was removed from inventory")
	_check(player.equipment.get_item_id("chest").is_empty(), "Rejected duplicate armor changed chest slot")
	for entry: Dictionary in [
		{"index": 8, "id": "iron_armor", "durability": 200},
		{"index": 9, "id": "leather_helmet", "durability": 80},
		{"index": 10, "id": "iron_shield", "durability": 175},
	]:
		var slot_index: int = int(entry["index"])
		player.inventory.set_slot(slot_index, {"item_id": entry["id"], "count": 1, "durability": entry["durability"]})
		player.use_slot_item(slot_index)
	var expected: Dictionary = {"clothing": "gambeson", "chest": "iron_armor", "head": "leather_helmet", "offhand": "iron_shield"}
	for slot: String in expected:
		_check(player.equipment.get_item_id(slot) == expected[slot], "Armor did not equip: " + slot)
	_check(save_system.save_slot(test_slot), "Saving equipment failed")
	var saved: Dictionary = SaveSystem._read_json(Config.SAVE_ROOT + test_slot + "/player.json")
	for slot: String in expected:
		_check(str(saved.get("equipment", {}).get(slot, {}).get("item_id", "")) == expected[slot], "Armor missing on disk: " + slot)
	player.equipment.from_dict({})
	player.inventory.from_dict({})
	_check(save_system.load_slot(test_slot), "Loading equipment failed")
	for slot: String in expected:
		_check(player.equipment.get_item_id(slot) == expected[slot], "Armor missing after load: " + slot)
	save_system.delete_slot(test_slot)
	print("EQUIPMENT_SAVE_RUNTIME: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
