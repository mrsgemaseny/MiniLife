@tool
extends SceneTree

func _init() -> void:
	var global_p = ProjectSettings.globalize_path("res://assets/sprites/world/resources/oak_tree.png")
	var img = Image.load_from_file(global_p)
	var w = img.get_width()
	var h = img.get_height()
	print("Inspecting bottom 30 rows of oak_tree.png:")
	var white_count = 0
	for y in range(h - 30, h):
		for x in range(w):
			var c = img.get_pixel(x, y)
			if c.a > 0.1 and c.r > 0.6 and c.g > 0.6 and c.b > 0.6:
				white_count += 1
	print("White/gray pixels in bottom 30 rows: ", white_count)
	quit(0)
