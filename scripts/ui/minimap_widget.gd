class_name MinimapWidget
extends Control

# High-performance ImageTexture radar updated only when tile/fog changes (1 draw call per frame).

const RADAR_RADIUS: int = 22
const MAP_DIM: int = RADAR_RADIUS * 2
const DISPLAY_SIZE: float = 176.0

var _center_tile: Vector2i = Vector2i(128, 128)
var _radar_image: Image = null
var _radar_texture: ImageTexture = null
var _dirty: bool = true

func _ready() -> void:
	custom_minimum_size = Vector2(DISPLAY_SIZE + 12.0, DISPLAY_SIZE + 30.0)
	_radar_image = Image.create(MAP_DIM, MAP_DIM, false, Image.FORMAT_RGBA8)
	_radar_image.fill(Color(0.05, 0.06, 0.08, 1.0))
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
				_radar_image.set_pixel(px, py, Color(0.05, 0.06, 0.08, 1.0))
			else:
				var col: Color = world_sys.get_biome_color_fast(tile)
				if fog == int(Config.FogState.VISITED):
					col = col.darkened(0.45)
				_radar_image.set_pixel(px, py, col)
	_radar_image.set_pixel(RADAR_RADIUS, RADAR_RADIUS, Color(1.0, 0.95, 0.25, 1.0))
	_radar_texture.update(_radar_image)
	_dirty = false

func _draw() -> void:
	if _dirty:
		_rebuild_radar_texture()

	var box_w: float = DISPLAY_SIZE + 16.0
	var box_h: float = DISPLAY_SIZE + 34.0
	draw_rect(Rect2(0, 0, box_w, box_h), Color(0.08, 0.09, 0.12, 0.94), true)
	draw_rect(Rect2(0, 0, box_w, box_h), Color(0.68, 0.55, 0.28, 0.95), false, 2.0)
	draw_rect(Rect2(3, 3, box_w - 6.0, box_h - 6.0), Color(0.28, 0.31, 0.38, 0.70), false, 1.0)

	if _radar_texture != null:
		draw_texture_rect(_radar_texture, Rect2(8, 24, DISPLAY_SIZE, DISPLAY_SIZE), false)
		draw_rect(Rect2(8, 24, DISPLAY_SIZE, DISPLAY_SIZE), Color(0.45, 0.38, 0.22, 0.85), false, 1.2)

	# Compass N badge
	draw_circle(Vector2(box_w * 0.5, 13.0), 8.5, Color(0.14, 0.16, 0.20, 0.98))
	draw_arc(Vector2(box_w * 0.5, 13.0), 8.5, 0.0, TAU, 16, Color(0.78, 0.64, 0.32), 1.4)

	if ThemeDB.fallback_font != null:
		draw_string(ThemeDB.fallback_font, Vector2(box_w * 0.5 - 8.0, 17.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 11, Color(0.96, 0.86, 0.52))
		var coords: String = "(%d, %d)" % [_center_tile.x, _center_tile.y]
		draw_string(ThemeDB.fallback_font, Vector2(10, 17), "Mini-map", HORIZONTAL_ALIGNMENT_LEFT, 75.0, 11, Color(0.92, 0.84, 0.62))
		draw_string(ThemeDB.fallback_font, Vector2(box_w - 82.0, 17), coords, HORIZONTAL_ALIGNMENT_RIGHT, 72.0, 11, Color(0.80, 0.84, 0.90))
