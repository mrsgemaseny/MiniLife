class_name MinimapWidget
extends Control

# High-performance ImageTexture radar updated only when tile/fog changes (1 draw call per frame).

const RADAR_RADIUS: int = 22
const MAP_DIM: int = RADAR_RADIUS * 2
const DISPLAY_SIZE: float = 166.0

var _center_tile: Vector2i = Vector2i(128, 128)
var _radar_image: Image = null
var _radar_texture: ImageTexture = null
var _dirty: bool = true

func _ready() -> void:
	custom_minimum_size = Vector2(DISPLAY_SIZE + 16.0, DISPLAY_SIZE + 30.0)
	_radar_image = Image.create(MAP_DIM, MAP_DIM, false, Image.FORMAT_RGBA8)
	_radar_image.fill(Color(0.05, 0.06, 0.08, 0.78))
	_radar_texture = ImageTexture.create_from_image(_radar_image)
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.fog_batch_updated.connect(_on_fog_batch_updated)

func _on_player_tile_changed(tile_pos: Vector2i) -> void:
	_center_tile = tile_pos
	_dirty = true
	queue_redraw()

func _on_fog_batch_updated(_changes: Array) -> void:
	_dirty = true
	queue_redraw()

func _rebuild_radar_texture() -> void:
	var world_sys: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
	if world_sys == null or _radar_image == null:
		return
	for py in range(MAP_DIM):
		var dy: int = py - RADAR_RADIUS
		for px in range(MAP_DIM):
			var dx: int = px - RADAR_RADIUS
			var tile: Vector2i = _center_tile + Vector2i(dx, dy)
			var fog: int = int(world_sys.get_fog_state(tile))
			if fog == int(Config.FogState.UNEXPLORED):
				_radar_image.set_pixel(px, py, Color(0.05, 0.06, 0.08, 0.75))
			else:
				var col: Color = world_sys.get_biome_color_fast(tile)
				if fog == int(Config.FogState.VISITED):
					col = col.darkened(0.42)
				col.a = 0.88
				_radar_image.set_pixel(px, py, col)
	_radar_image.set_pixel(RADAR_RADIUS, RADAR_RADIUS, Color(1.0, 0.95, 0.25, 1.0))
	_radar_texture.update(_radar_image)
	_dirty = false

func _draw() -> void:
	if _dirty:
		_rebuild_radar_texture()

	var box_w: float = DISPLAY_SIZE + 16.0
	var box_h: float = DISPLAY_SIZE + 30.0
	draw_rect(Rect2(0, 0, box_w, box_h), Color(0.06, 0.08, 0.11, 0.56), true)
	draw_rect(Rect2(0, 0, box_w, box_h), Color(0.76, 0.62, 0.34, 0.68), false, 1.2)

	if _radar_texture != null:
		draw_texture_rect(_radar_texture, Rect2(8, 22, DISPLAY_SIZE, DISPLAY_SIZE), false)
		draw_rect(Rect2(8, 22, DISPLAY_SIZE, DISPLAY_SIZE), Color(0.52, 0.44, 0.26, 0.65), false, 1.0)

	# Compass N badge
	draw_circle(Vector2(box_w * 0.5, 12.0), 7.5, Color(0.11, 0.14, 0.19, 0.85))
	draw_arc(Vector2(box_w * 0.5, 12.0), 7.5, 0.0, TAU, 16, Color(0.78, 0.64, 0.32, 0.85), 1.2)

	if ThemeDB.fallback_font != null:
		draw_string(ThemeDB.fallback_font, Vector2(box_w * 0.5 - 8.0, 16.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 10, Color(0.96, 0.86, 0.52))
		var coords: String = "(%d, %d)" % [_center_tile.x, _center_tile.y]
		draw_string(ThemeDB.fallback_font, Vector2(8, 16), "Radar", HORIZONTAL_ALIGNMENT_LEFT, 68.0, 10, Color(0.92, 0.84, 0.62))
		draw_string(ThemeDB.fallback_font, Vector2(box_w - 78.0, 16), coords, HORIZONTAL_ALIGNMENT_RIGHT, 70.0, 10, Color(0.80, 0.86, 0.92))
