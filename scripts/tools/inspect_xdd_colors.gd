@tool
extends SceneTree

func _init() -> void:
	var path: String = "C:/Users/murat/Downloads/Gemini_Generated_Image_xdd38zxdd38zxdd3.jpg"
	var img = Image.load_from_file(path)
	print("xdd corner (0,0): ", img.get_pixel(0, 0))
	print("xdd (100, 100): ", img.get_pixel(100, 100))
	print("xdd (500, 500): ", img.get_pixel(500, 500))
	print("xdd (1000, 100): ", img.get_pixel(1000, 100))
	quit(0)
