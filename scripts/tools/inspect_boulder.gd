@tool
extends SceneTree

func _init() -> void:
	var global_p = ProjectSettings.globalize_path("res://assets/sprites/world/resources/boulder.png")
	var img = Image.load_from_file(global_p)
	var w = img.get_width()
	var h = img.get_height()
	print("Checking bottom 30 rows of boulder.png (height=", h, "):")
	for y in range(h - 30, h):
		var count = 0
		for x in range(w):
			if img.get_pixel(x, y).a > 0.1: count += 1
		print("Row y=", y, " non-transparent pixels: ", count)
	quit(0)
