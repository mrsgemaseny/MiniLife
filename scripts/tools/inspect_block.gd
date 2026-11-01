@tool
extends SceneTree

func _init() -> void:
	var global_p = ProjectSettings.globalize_path("res://assets/sprites/blocks/voxelTile_18.png")
	var img = Image.load_from_file(global_p)
	var w = img.get_width()
	var h = img.get_height()
	print("Checking voxelTile_18.png (111x128):")
	for y in range(h - 30, h):
		var count = 0
		var min_x = w
		var max_x = 0
		for x in range(w):
			if img.get_pixel(x, y).a > 0.1:
				count += 1
				if x < min_x: min_x = x
				if x > max_x: max_x = x
		print("Row y=", y, " non-transparent pixels: ", count, " x-range: [", min_x, "..", max_x, "]")
	quit(0)
