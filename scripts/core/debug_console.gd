class_name DebugConsole
extends Node


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
