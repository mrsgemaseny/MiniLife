@tool
extends SceneTree

func _init() -> void:
	# Let's inspect colors of voxelTile_01 to voxelTile_30 to see which is stone, which is wood, furnace, chest, etc.
	for i in range(1, 35):
		var fname = "voxelTile_%02d.png" % i
		var path = "res://assets/sprites/blocks/" + fname
		var global_p = ProjectSettings.globalize_path(path)
		var img = Image.load_from_file(global_p)
		if img != null:
			# Sample center of top face and side face
			var top_c = img.get_pixel(55, 20)
			var left_c = img.get_pixel(25, 60)
			print(fname, " top: ", top_c, " left: ", left_c)
	quit(0)
