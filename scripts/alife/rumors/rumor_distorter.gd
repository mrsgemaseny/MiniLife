class_name RumorDistorter
extends RefCounted

static func apply_distortion(original: String, place_name: String, hops: int) -> Dictionary:
	var level: int = clampi(hops, 0, 3)
	var content: String = original
	if level == 1:
		content = "Travelers report: " + original
	elif level == 2:
		content = "Unconfirmed news from %s: %s" % [place_name, original]
	elif level >= 3:
		content = "There are conflicting reports of events near %s." % place_name
	return {"content": content, "distortion": level}
