@tool
extends SceneTree

func _init() -> void:
	print("Starting sprite slicing and transparency processing...")
	DirAccess.make_dir_recursive_absolute("res://assets/sprites/world/tiles")
	DirAccess.make_dir_recursive_absolute("res://assets/sprites/world/resources")
	DirAccess.make_dir_recursive_absolute("res://assets/sprites/world/growth")

	_slice_resources()
	_slice_tiles()
	_slice_growth()
	print("All sprites successfully sliced and saved as transparent PNGs!")
	quit(0)

func _is_checkerboard(c: Color) -> bool:
	var diff_rg: float = absf(c.r - c.g)
	var diff_gb: float = absf(c.g - c.b)
	var diff_rb: float = absf(c.r - c.b)
	var is_neutral: bool = (diff_rg < 0.06 and diff_gb < 0.06 and diff_rb < 0.06)
	var is_bright: bool = (c.r >= 0.68 and c.g >= 0.68 and c.b >= 0.68)
	return is_neutral and is_bright

func _remove_checkerboard_flood(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)

	var queue: Array[Vector2i] = []

	# Push all border pixels that match checkerboard
	for x in range(w):
		for y in [0, h - 1]:
			var idx: int = y * w + x
			if visited[idx] == 0:
				visited[idx] = 1
				var c: Color = img.get_pixel(x, y)
				if _is_checkerboard(c):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
					queue.append(Vector2i(x, y))

	for y in range(h):
		for x in [0, w - 1]:
			var idx: int = y * w + x
			if visited[idx] == 0:
				visited[idx] = 1
				var c: Color = img.get_pixel(x, y)
				if _is_checkerboard(c):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
					queue.append(Vector2i(x, y))

	# BFS flood fill
	var q_idx: int = 0
	while q_idx < queue.size():
		var pt: Vector2i = queue[q_idx]
		q_idx += 1

		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = pt.x + dir.x
			var ny: int = pt.y + dir.y
			if nx >= 0 and nx < w and ny >= 0 and ny < h:
				var nidx: int = ny * w + nx
				if visited[nidx] == 0:
					visited[nidx] = 1
					var nc: Color = img.get_pixel(nx, ny)
					if _is_checkerboard(nc):
						img.set_pixel(nx, ny, Color(0, 0, 0, 0))
						queue.append(Vector2i(nx, ny))

func _crop_and_save(img: Image, out_path: String) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var min_x: int = w
	var min_y: int = h
	var max_x: int = 0
	var max_y: int = 0

	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.05:
				if x < min_x: min_x = x
				if y < min_y: min_y = y
				if x > max_x: max_x = x
				if y > max_y: max_y = y

	if min_x <= max_x and min_y <= max_y:
		var crop_w: int = (max_x - min_x) + 1
		var crop_h: int = (max_y - min_y) + 1
		var cropped: Image = img.get_region(Rect2i(min_x, min_y, crop_w, crop_h))
		cropped.save_png(out_path)
		print("Saved: ", out_path, " (", crop_w, "x", crop_h, ")")
	else:
		img.save_png(out_path)
		print("Saved uncropped: ", out_path)

func _slice_resources() -> void:
	var path: String = "C:/Users/murat/Downloads/Gemini_Generated_Image_dy99gydy99gydy99.jpg"
	var sheet: Image = Image.load_from_file(path)
	if sheet == null:
		print("Error: Could not load ", path)
		return

	var cell_w: int = 2752 / 3
	var cell_h: int = 1536 / 3

	var names: Array[Array] = [
		["oak_tree", "pine_tree", "boulder"],
		["berry_bush", "mushrooms", "dead_tree"],
		["wildflowers", "reeds", "pebbles"]
	]

	for row in range(3):
		for col in range(3):
			var rname: String = str(names[row][col])
			var rx: int = col * cell_w
			var ry: int = row * cell_h
			var cell: Image = sheet.get_region(Rect2i(rx, ry, cell_w, cell_h))
			cell.convert(Image.FORMAT_RGBA8)
			_remove_checkerboard_flood(cell)
			_crop_and_save(cell, "res://assets/sprites/world/resources/%s.png" % rname)

func _slice_tiles() -> void:
	var path: String = "C:/Users/murat/Downloads/Gemini_Generated_Image_e941lte941lte941.jpg"
	var sheet: Image = Image.load_from_file(path)
	if sheet == null:
		print("Error: Could not load ", path)
		return

	var cell_w: int = 2752 / 3
	var cell_h: int = 1536 / 3

	var names: Array[Array] = [
		["tile_grass", "tile_dirt", "tile_flagstone"],
		["tile_water", "tile_sand", "tile_swamp"],
		["tile_stone_path", "tile_snow", "tile_mountain"]
	]

	for row in range(3):
		for col in range(3):
			var tname: String = str(names[row][col])
			var rx: int = col * cell_w
			var ry: int = row * cell_h
			var cell: Image = sheet.get_region(Rect2i(rx, ry, cell_w, cell_h))
			cell.convert(Image.FORMAT_RGBA8)
			_remove_checkerboard_flood(cell)
			_crop_and_save(cell, "res://assets/sprites/world/tiles/%s.png" % tname)

func _slice_growth() -> void:
	var path: String = "C:/Users/murat/Downloads/Gemini_Generated_Image_xdd38zxdd38zxdd3.jpg"
	var sheet: Image = Image.load_from_file(path)
	if sheet == null:
		print("Error: Could not load ", path)
		return

	var cell_w: int = 2752 / 4
	var cell_h: int = 1536

	var names: Array[String] = ["tree_sapling", "tree_small", "tree_mature", "tree_ancient"]

	for col in range(4):
		var gname: String = names[col]
		var rx: int = col * cell_w
		var cell: Image = sheet.get_region(Rect2i(rx, 0, cell_w, cell_h))
		cell.convert(Image.FORMAT_RGBA8)
		_remove_checkerboard_flood(cell)
		_crop_and_save(cell, "res://assets/sprites/world/growth/%s.png" % gname)
