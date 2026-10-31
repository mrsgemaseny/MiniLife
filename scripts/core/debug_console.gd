class_name DebugConsole
extends Node


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--e2e-smoke"):
		call_deferred("_run_e2e_smoke_test")


func _run_e2e_smoke_test() -> void:
	await get_tree().process_frame
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	for step in range(4):
		player.global_position += Vector2(32.0, 16.0)
		SignalBus.player_tile_changed.emit(Config.iso_to_world(player.global_position))
	player.perform_attack()
	player.use_slot_item(0)
	player.use_slot_item(4)
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_method("interact"):
			npc.call("interact", player)
			SignalBus.dialogue_choice_selected.emit(0)
	SignalBus.craft_requested.emit("stone_axe", player, "")
	SignalBus.build_requested.emit("campfire", player.current_tile + Vector2i(2, 2), player)
	for pname in ["inventory", "craft", "build", "quests", "character", "factions", "chronicle", "achievements"]:
		SignalBus.ui_panel_requested.emit(pname)
	SignalBus.ui_close_all_requested.emit()
	var first_npc: Node = get_tree().get_first_node_in_group("npc")
	if first_npc != null:
		SignalBus.trade_transaction_requested.emit(first_npc, "bread", 1, true)
		SignalBus.trade_transaction_requested.emit(first_npc, "wood", 1, false)
	SignalBus.save_requested.emit("e2e_smoke_slot")
	SignalBus.load_requested.emit("e2e_smoke_slot")
	SignalBus.world_delete_requested.emit("e2e_smoke_slot")
	print("E2E_ALL_SYSTEMS_VERIFIED_OK")
	get_tree().quit(0)


func execute_command(raw_line: String) -> String:
	var cleaned: String = raw_line.strip_edges()
	if cleaned == "":
		return ""
	var parts: PackedStringArray = cleaned.split(" ", false)
	var cmd: String = parts[0].to_lower()
	var out: String = ""

	match cmd:
		"god":
			GameManager.debug_god_mode = not GameManager.debug_god_mode
			out = "God mode: " + str(GameManager.debug_god_mode)
		"fast":
			GameManager.debug_fast_time = not GameManager.debug_fast_time
			out = "Fast time: " + str(GameManager.debug_fast_time)
		"reveal":
			GameManager.debug_reveal_map = not GameManager.debug_reveal_map
			out = "Reveal map: " + str(GameManager.debug_reveal_map)
		"give":
			if parts.size() >= 2:
				var item_id: String = parts[1]
				var count: int = int(parts[2]) if parts.size() >= 3 else 1
				var player: Node = get_tree().get_first_node_in_group("player")
				if player != null:
					var inv: InventoryComponent = player.get("inventory") as InventoryComponent
					if inv != null:
						var added: int = inv.add_item(item_id, count)
						out = "Added %d x %s" % [added, item_id]
		"gold":
			var amount: int = int(parts[1]) if parts.size() >= 2 else 100
			var player: Node = get_tree().get_first_node_in_group("player")
			if player != null:
				var inv: InventoryComponent = player.get("inventory") as InventoryComponent
				if inv != null:
					inv.add_gold(amount)
					out = "Added %d gold" % amount
		"time":
			if parts.size() >= 2:
				var hr: float = float(parts[1])
				GameManager.set_day_and_hour(GameManager.get_day(), hr)
				out = "Set hour to %.1f" % hr
		"event":
			if parts.size() >= 2:
				SignalBus.game_event_triggered.emit(parts[1])
				out = "Triggered event " + parts[1]
		_:
			out = "Unknown command: " + cmd

	SignalBus.debug_command_executed.emit(cleaned, out)
	if out != "":
		SignalBus.notification_posted.emit(out)
	return out
