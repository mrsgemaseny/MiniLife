@tool
extends SceneTree

func _init() -> void:
	var global_p = ProjectSettings.globalize_path("res://assets/sprites/world/resources/oak_tree.png")
	var img = Image.load_from_file(global_p)
	var w = img.get_width()
	var h = img.get_height()
	print("Checking bottom 40 rows of oak_tree.png (height=", h, "):")
	for y in range(h - 40, h):
		var non_zero = 0
		for x in range(w):
			if img.get_pixel(x, y).a > 0.1:
				non_zero += 1
		print("Row y=", y, " non-transparent pixels: ", non_zero)
	quit(0)
