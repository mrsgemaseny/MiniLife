@tool
extends SceneTree

func _init() -> void:
	var path: String = "C:/Users/murat/Downloads/Gemini_Generated_Image_dy99gydy99gydy99.jpg"
	var sheet: Image = Image.load_from_file(path)
	print("Checking vertical slice at x=500..600 from y=400 to 700:")
	for y in range(480, 560):
		var colors = []
		for x in [500, 550, 600]:
			colors.append(sheet.get_pixel(x, y))
		print("y=", y, " c550: ", colors[1])
	quit(0)
