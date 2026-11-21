class_name RumorDistorter
extends RefCounted

static func apply_distortion(original: String, place_name: String, hops: int) -> Dictionary:
	var level: int = clampi(hops, 0, 3)
	var content: String = original
	if level == 1:
		content = "Путники рассказывают: " + original
	elif level == 2:
		content = "Непроверенные вести из %s: %s" % [place_name, original]
	elif level >= 3:
		content = "О событиях возле %s рассказывают разное." % place_name
	return {"content": content, "distortion": level}
