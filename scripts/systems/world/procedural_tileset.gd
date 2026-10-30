class_name ProceduralTileset
extends RefCounted

const BIOME_PALETTE: Dictionary = {
	"plains": Color(0.31, 0.54, 0.26, 1.0),
	"forest": Color(0.19, 0.41, 0.20, 1.0),
	"mountains": Color(0.37, 0.40, 0.44, 1.0),
	"desert": Color(0.76, 0.61, 0.33, 1.0),
	"swamp": Color(0.24, 0.36, 0.28, 1.0),
	"fog_unexplored": Color(0.05, 0.06, 0.08, 0.96),
	"fog_visited": Color(0.08, 0.10, 0.14, 0.52)
}

const BIOME_ATLAS_COORDS: Dictionary = {
	"plains": Vector2i(0, 0),
	"forest": Vector2i(1, 0),
	"mountains": Vector2i(2, 0),
	"desert": Vector2i(3, 0),
	"swamp": Vector2i(4, 0),
	"fog_unexplored": Vector2i(5, 0),
	"fog_visited": Vector2i(6, 0)
}


static func build_isometric_tileset() -> TileSet:
	var tile_w: int = Config.TILE_SIZE.x
	var tile_h: int = Config.TILE_SIZE.y
	var count: int = BIOME_ATLAS_COORDS.size()
	var img: Image = Image.create(tile_w * count, tile_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for key in BIOME_ATLAS_COORDS:
		var coords: Vector2i = BIOME_ATLAS_COORDS[key]
		var col: Color = BIOME_PALETTE.get(key, Color.GRAY)
		_rasterize_iso_diamond(img, coords.x * tile_w, 0, tile_w, tile_h, col, not str(key).begins_with("fog_"))

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var ts: TileSet = TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Config.TILE_SIZE

	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Config.TILE_SIZE
	ts.add_source(source, 0)

	for key in BIOME_ATLAS_COORDS:
		var coords: Vector2i = BIOME_ATLAS_COORDS[key]
		source.create_tile(coords)
	return ts


static func get_biome_atlas_coord(biome_id: String) -> Vector2i:
	return BIOME_ATLAS_COORDS.get(biome_id, Vector2i(0, 0))


static func _rasterize_iso_diamond(img: Image, ox: int, oy: int, w: int, h: int, base_col: Color, add_texture_detail: bool) -> void:
	var hw: float = float(w) * 0.5
	var hh: float = float(h) * 0.5
	var border_col: Color = base_col.darkened(0.18)
	var highlight_col: Color = base_col.lightened(0.10)

	for py in range(h):
		for px in range(w):
			var dx: float = absf((float(px) + 0.5) - hw) / hw
			var dy: float = absf((float(py) + 0.5) - hh) / hh
			var manhattan: float = dx + dy
			if manhattan <= 1.0:
				var pixel_col: Color = base_col
				if manhattan >= 0.90:
					pixel_col = border_col
				elif add_texture_detail:
					var pattern: int = ((px * 17 + py * 31) ^ (px * py)) & 15
					if pattern == 0:
						pixel_col = highlight_col
					elif pattern == 1:
						pixel_col = base_col.darkened(0.08)
				img.set_pixel(ox + px, oy + py, pixel_col)
