@tool
extends SceneTree

func _init() -> void:
	var paths: Array[String] = [
		"C:/Users/murat/Downloads/Gemini_Generated_Image_e941lte941lte941.jpg",
		"C:/Users/murat/Downloads/Gemini_Generated_Image_dy99gydy99gydy99.jpg",
		"C:/Users/murat/Downloads/Gemini_Generated_Image_xdd38zxdd38zxdd3.jpg"
	]
	for p in paths:
		var img: Image = Image.load_from_file(p)
		if img != null:
			print(p.get_file(), " -> Size: ", img.get_size(), " Format: ", img.get_format())
		else:
			print("Failed to load: ", p)
	quit(0)
