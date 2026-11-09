extends Node2D

class Living extends Node2D:
	var species: String
	func _draw() -> void:
		AnimalRig.draw_animal(self, species, 0.0, 0.0, 1.0, false, false)

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("292722"))
	for i in range(4):
		var species: String = ["wolf", "sheep", "moose", "bandit_scout"][i]
		var x: float = 120.0 + i * 245.0
		var label: Label = Label.new()
		label.text = species
		label.position = Vector2(x - 45.0, 30.0)
		add_child(label)
		if i < 3:
			var living: Living = Living.new()
			living.species = species
			living.position = Vector2(x, 260.0)
			living.scale = Vector2(3.0, 3.0)
			add_child(living)
		var body: CorpseEntity = CorpseEntity.new()
		body.species = species
		body.position = Vector2(x, 440.0)
		body.scale = Vector2(3.0, 3.0)
		add_child(body)
	call_deferred("capture")

func capture() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png("res://output/corpse_visual_2026-11-06.png")
	print("CORPSE_PREVIEW_RESULT: ", result)
	get_tree().quit(int(result))
