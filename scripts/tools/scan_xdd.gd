@tool
extends SceneTree

func _init() -> void:
	var path: String = "C:/Users/murat/Downloads/Gemini_Generated_Image_xdd38zxdd38zxdd3.jpg"
	var img = Image.load_from_file(path)
	var w = img.get_width()
	var h = img.get_height()
	print("Finding bounding boxes in ", path.get_file(), "...")
	var block_w = 32
	var block_h = 32
	var cols = w / block_w
	var rows = h / block_h
	for r in range(rows):
		var row_str = ""
		for c in range(cols):
			var non_bg = 0
			for by in range(block_h):
				for bx in range(block_w):
					var px = c * block_w + bx
					var py = r * block_h + by
					var col = img.get_pixel(px, py)
					var diff_rg = absf(col.r - col.g)
					var diff_gb = absf(col.g - col.b)
					if (diff_rg > 0.07 or diff_gb > 0.07 or col.r < 0.65):
						non_bg += 1
			row_str += "#" if non_bg > 200 else "."
		print(row_str)
	quit(0)
