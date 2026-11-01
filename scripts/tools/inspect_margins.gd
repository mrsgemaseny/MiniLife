@tool
extends SceneTree

func _init() -> void:
	var files = [
		"res://assets/sprites/world/resources/oak_tree.png",
		"res://assets/sprites/world/resources/pine_tree.png",
		"res://assets/sprites/world/resources/boulder.png",
		"res://assets/sprites/world/resources/berry_bush.png",
		"res://assets/sprites/blocks/voxelTile_14.png",
		"res://assets/sprites/blocks/voxelTile_17.png",
		"res://assets/sprites/blocks/voxelTile_18.png",
		"res://assets/sprites/blocks/voxelTile_19.png",
		"res://assets/sprites/blocks/voxelTile_28.png"
	]
	for path in files:
		var global_p = ProjectSettings.globalize_path(path)
		var img = Image.load_from_file(global_p)
		if img == null:
			print("FAILED: ", path)
			continue
		var w = img.get_width()
		var h = img.get_height()
		var min_x = w
		var max_x = 0
		var min_y = h
		var max_y = 0
		for y in range(h):
			for x in range(w):
				if img.get_pixel(x, y).a > 0.05:
					if x < min_x: min_x = x
					if x > max_x: max_x = x
					if y < min_y: min_y = y
					if y > max_y: max_y = y
		print(path.get_file(), " Size: (", w, ",", h, ") Non-alpha bounds: x=[", min_x, "..", max_x, "] y=[", min_y, "..", max_y, "] Bottom transparent margin: ", h - 1 - max_y)
	quit(0)
