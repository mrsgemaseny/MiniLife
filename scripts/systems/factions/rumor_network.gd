class_name RumorNetwork
extends RefCounted

# Queues and propagates reputation rumors across allied and rival factions.

var pending_rumors: Array[Dictionary] = []

func enqueue_rumor(source_faction: String, rep_delta: int, delay_seconds: float = 8.0) -> void:
	if abs(rep_delta) < 4:
		return
	pending_rumors.append({
		"source_faction": source_faction,
		"rep_delta": rep_delta,
		"remaining": delay_seconds
	})

func tick(delta: float, factions_defs: Dictionary) -> Array[Dictionary]:
	var triggered: Array[Dictionary] = []
	for i in range(pending_rumors.size() - 1, -1, -1):
		var rumor: Dictionary = pending_rumors[i]
		var rem: float = float(rumor.get("remaining", 0.0)) - delta
		if rem <= 0.0:
			var source: String = str(rumor.get("source_faction", ""))
			var rep_delta: int = int(rumor.get("rep_delta", 0))
			var def: Dictionary = factions_defs.get(source, {})
			var allies: Array = def.get("allies", [])
			for ally in allies:
				triggered.append({
					"source": source,
					"target": str(ally),
					"delta": int(round(float(rep_delta) * 0.5))
				})
			var enemies: Array = def.get("enemies", [])
			for rival in enemies:
				triggered.append({
					"source": source,
					"target": str(rival),
					"delta": int(round(float(-rep_delta) * 0.35))
				})
			pending_rumors.remove_at(i)
		else:
			rumor["remaining"] = rem
			pending_rumors[i] = rumor
	return triggered
