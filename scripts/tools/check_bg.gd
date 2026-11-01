@tool
extends SceneTree

func _init() -> void:
	var img: Image = Image.load_from_file("C:/Users/murat/Downloads/Gemini_Generated_Image_dy99gydy99gydy99.jpg")
	for y in range(0, 40, 8):
		var row: String = ""
		for x in range(0, 40, 8):
			var c: Color = img.get_pixel(x, y)
			row += "(%.2f,%.2f,%.2f) " % [c.r, c.g, c.b]
		print("Row ", y, ": ", row)
	quit(0)
