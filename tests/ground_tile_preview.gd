extends Node2D

const TILE_NAMES: Array[String] = ["tile_grass", "tile_swamp", "tile_sand", "tile_mountain"]
var ground_uv: PackedVector2Array = PackedVector2Array([
	Vector2(0.5, 0.14), Vector2(0.88, 16.0 / 37.0),
	Vector2(0.5, 0.71), Vector2(0.12, 16.0 / 37.0),
])
var textures: Array[Texture2D] = []

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("202720"))
	for name: String in TILE_NAMES:
		textures.append(load("res://assets/sprites/world/tiles/%s.png" % name) as Texture2D)
	queue_redraw()
	call_deferred("_capture")

func _draw() -> void:
	for row: int in range(TILE_NAMES.size()):
		var texture: Texture2D = textures[row]
		draw_texture_rect(texture, Rect2(1100.0, 100.0 + row * 220.0, 200.0, 125.0), false)
		for y: int in range(3):
			for x: int in range(12):
				var center: Vector2 = Vector2(150.0 + x * Config.TILE_SIZE.x, 95.0 + (row * 3 + y) * Config.TILE_SIZE.y)
				IsoMath.draw_textured_quad(self, IsoMath.cell_polygon(center), Color.WHITE, ground_uv, texture)

func _capture() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/ground_tile_preview.png")
	print("GROUND_TILE_PREVIEW: PASS")
	get_tree().quit()
