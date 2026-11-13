extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var save_system: SaveSystem = main.get_node("Systems/SaveSystem") as SaveSystem
	var player: Player = main.get_node("World/Player") as Player
	player.skills.set_level("foraging", 8)
	player.skills.set_level("combat_attack", 15)
	player.inventory.silver = 400
	player.traits.add_trait("iron_will")
	player.equipment.equip("iron_armor", -1, "chest")
	GameManager.start_new_game(12345)
	var first_id: String = GameManager.get_game_id()
	assert(first_id.begins_with("world_") and first_id.length() == 38)
	assert(GameManager.get_active_slot() == first_id)
	assert(SaveSystem.slot_exists(first_id))
	assert(player.skills.get_level("foraging") == 0)
	assert(player.skills.get_combat_level("combat_attack") == 0)
	assert(player.inventory.silver == 0)
	assert(player.traits.active_traits.is_empty())
	assert(player.equipment.get_item_id("chest").is_empty())
	player.skills.set_level("foraging", 9)
	GameManager.start_new_game(12345)
	var second_id: String = GameManager.get_game_id()
	assert(second_id != first_id and second_id != Config.DEFAULT_SAVE_SLOT)
	assert(SaveSystem.slot_exists(first_id) and SaveSystem.slot_exists(second_id))
	assert(player.skills.get_level("foraging") == 0)
	var first_meta: Dictionary = SaveSystem._read_json(Config.SAVE_ROOT + first_id + "/meta.json")
	var second_meta: Dictionary = SaveSystem._read_json(Config.SAVE_ROOT + second_id + "/meta.json")
	var first_player: Dictionary = SaveSystem._read_json(Config.SAVE_ROOT + first_id + "/player.json")
	var second_player: Dictionary = SaveSystem._read_json(Config.SAVE_ROOT + second_id + "/player.json")
	assert(str(first_meta.get("game_id", "")) == first_id)
	assert(str(second_meta.get("game_id", "")) == second_id)
	assert(int(first_player.get("skills", {}).get("skills", {}).get("foraging", -1)) == 0)
	assert(int(second_player.get("skills", {}).get("skills", {}).get("foraging", -1)) == 0)
	var bundle: Dictionary = {}
	SignalBus.save_data_requested.emit(bundle)
	assert(str(bundle.get("meta", {}).get("game_id", "")) == second_id)
	save_system.delete_slot(first_id)
	save_system.delete_slot(second_id)
	print("NEW_GAME_IDENTITY_PASS")
	get_tree().quit()
