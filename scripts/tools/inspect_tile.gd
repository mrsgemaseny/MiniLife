@tool
extends SceneTree

func _init() -> void:
	var global_p = ProjectSettings.globalize_path("res://assets/sprites/world/tiles/tile_grass.png")
	var img = Image.load_from_file(global_p)
	var w = img.get_width()
	var h = img.get_height()
	print("tile_grass.png size: ", w, "x", h)
	# Check border pixels
	var non_transparent_border = 0
	for x in range(w):
		if img.get_pixel(x, 0).a > 0.05: non_transparent_border += 1
		if img.get_pixel(x, h - 1).a > 0.05: non_transparent_border += 1
	for y in range(h):
		if img.get_pixel(0, y).a > 0.05: non_transparent_border += 1
		if img.get_pixel(w - 1, y).a > 0.05: non_transparent_border += 1
	print("non-transparent border pixels: ", non_transparent_border)
	quit(0)
