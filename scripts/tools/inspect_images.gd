@tool
extends SceneTree

func _init() -> void:
	for path in [
		"C:/Users/murat/Downloads/Gemini_Generated_Image_dy99gydy99gydy99.jpg",
		"C:/Users/murat/Downloads/Gemini_Generated_Image_e941lte941lte941.jpg",
		"C:/Users/murat/Downloads/Gemini_Generated_Image_xdd38zxdd38zxdd3.jpg"
	]:
		var img = Image.load_from_file(path)
		if img != null:
			print("FILE: ", path.get_file(), " Size: ", img.get_size())
	quit(0)
