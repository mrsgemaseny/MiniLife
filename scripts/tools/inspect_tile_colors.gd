@tool
extends SceneTree

func _init() -> void:
	var global_p = ProjectSettings.globalize_path("res://assets/sprites/world/tiles/tile_grass.png")
	var img = Image.load_from_file(global_p)
	var w = img.get_width()
	var h = img.get_height()
	print("Inspecting tile_grass.png colors:")
	print("Center pixel: ", img.get_pixel(w/2, h/2))
	print("Pixel at (10, 10): ", img.get_pixel(10, 10))
	print("Pixel at (w/2, 2): ", img.get_pixel(w/2, 2))
	print("Pixel at (2, h/2): ", img.get_pixel(2, h/2))
	quit(0)
