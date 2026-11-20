class_name CombatLogText
extends RefCounted


static func event_id(result: Dictionary) -> String:
	var outcome: String = str(result.get("outcome", ""))
	if outcome == "armor_contact":
		return "armor_glancing" if str(result.get("armor_outcome", "")) == "glancing" else "armor_full"
	return outcome


static func line_for(result: Dictionary, sequence: int) -> String:
	var row: Dictionary = DataRegistry.get_entry("combat_log_ru", event_id(result))
	var lines: Array = row.get("lines", [])
	if lines.is_empty():
		return ""
	return str(lines[posmod(sequence, lines.size())])
