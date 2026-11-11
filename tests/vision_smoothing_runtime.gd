extends Node

func _ready() -> void:
	var fog := FogOfWarSystem.new()
	var center := Vector2i(500, 500)
	var first: Array[Dictionary] = fog.update_around(center, 18)
	var unchanged: Array[Dictionary] = fog.update_around(center, 18)
	var moved: Array[Dictionary] = fog.update_around(center + Vector2i.RIGHT, 18)
	var ok: bool = first.size() > 900 and unchanged.is_empty() and moved.size() < 100
	ok = ok and fog.get_state(center) == int(Config.FogState.VISIBLE)
	ok = ok and fog.get_state(center + Vector2i(-18, 0)) == int(Config.FogState.VISITED)
	if not ok:
		push_error("Fog updates must contain only tiles whose visibility changed")
	print("VISION_TEST: ", "PASS" if ok else "FAIL", " initial=", first.size(), " unchanged=", unchanged.size(), " step=", moved.size())
	get_tree().quit(0 if ok else 1)
