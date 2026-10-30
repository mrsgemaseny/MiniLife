class_name MinimapWidget
extends Control

# Renders a real-time isometric world radar in the top-right corner of the HUD.

const RADAR_RADIUS: int = 24
const PIXEL_SCALE: int = 4

var _center_tile: Vector2i = Vector2i(128, 128)

func _ready() -> void:
	custom_minimum_size = Vector2(RADAR_RADIUS * 2 * PIXEL_SCALE + 8, RADAR_RADIUS * 2 * PIXEL_SCALE + 26)
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.fog_batch_updated.connect(_on_fog_batch_updated)

func _on_player_tile_changed(tile_pos: Vector2i) -> void:
	_center_tile = tile_pos
	queue_redraw()

func _on_fog_batch_updated(_changes: Array) -> void:
	queue_redraw()

func _draw() -> void:
	var box_w: float = float(RADAR_RADIUS * 2 * PIXEL_SCALE + 8)
	var box_h: float = float(RADAR_RADIUS * 2 * PIXEL_SCALE + 24)
	draw_rect(Rect2(0, 0, box_w, box_h), Color(0.08, 0.09, 0.11, 0.88), true)
	draw_rect(Rect2(0, 0, box_w, box_h), Color(0.38, 0.42, 0.48, 0.95), false, 1.5)

	if ThemeDB.fallback_font != null:
		var header: String = "Radar (%d, %d)" % [_center_tile.x, _center_tile.y]
		draw_string(ThemeDB.fallback_font, Vector2(6, 14), header, HORIZONTAL_ALIGNMENT_LEFT, box_w - 12, 11, Color(0.85, 0.88, 0.92))

	var world_sys: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
	if world_sys == null:
		return

	var map_origin: Vector2 = Vector2(4, 20)
	for dy in range(-RADAR_RADIUS, RADAR_RADIUS):
		for dx in range(-RADAR_RADIUS, RADAR_RADIUS):
			var tile: Vector2i = _center_tile + Vector2i(dx, dy)
			var fog: int = int(world_sys.get_fog_state(tile))
			var px: float = map_origin.x + float(dx + RADAR_RADIUS) * float(PIXEL_SCALE)
			var py: float = map_origin.y + float(dy + RADAR_RADIUS) * float(PIXEL_SCALE)
			if fog == int(Config.FogState.UNEXPLORED):
				draw_rect(Rect2(px, py, PIXEL_SCALE, PIXEL_SCALE), Color(0.05, 0.05, 0.07), true)
			else:
				var tstate: WorldSystem.TileState = world_sys.get_tile(tile)
				var col: Color = ProceduralTileset.BIOME_PALETTE.get(tstate.biome_id, Color(0.31, 0.54, 0.26))
				if fog == int(Config.FogState.VISITED):
					col = col.darkened(0.45)
				draw_rect(Rect2(px, py, PIXEL_SCALE, PIXEL_SCALE), col, true)

	var cx: float = map_origin.x + float(RADAR_RADIUS * PIXEL_SCALE)
	var cy: float = map_origin.y + float(RADAR_RADIUS * PIXEL_SCALE)
	draw_rect(Rect2(cx - 2, cy - 2, 5, 5), Color(1.0, 0.95, 0.25), true)
