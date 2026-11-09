extends Node2D

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("546448"))
	var index: int = 0
	for species: String in ["cow", "sheep", "wolf", "deer", "boar", "chicken"]:
		var texture: Texture2D = AnimalRig.sprite_for(species)
		assert(texture != null and texture.get_image().detect_alpha() != Image.ALPHA_NONE)
		var animal := AnimalEntity.new()
		animal.animal_type = species
		animal.position = Vector2(170 + (index % 3) * 200, 190 + (index / 3) * 160)
		add_child(animal)
		animal.set_physics_process(false)
		animal.set_process(false)
		index += 1
	for id: String in ["wolf", "bandit_raider", "mercenary_guard"]:
		var enemy := EnemyBase.new()
		enemy.enemy_id = id
		enemy.position = Vector2(170 + (index % 3) * 200, 190 + (index / 3) * 160)
		add_child(enemy)
		enemy.set_physics_process(false)
		index += 1
	assert(preload("res://scripts/ui/material_labels.gd").describe("wool").contains("shear sheep"))
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--preview-mobs"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/mob_art_ingame.png")
	print("MOB_ART_PASS: fauna textures have alpha; live AnimalEntity and EnemyBase render; wool source label")
	get_tree().quit()
