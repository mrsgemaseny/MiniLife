extends Node2D

const Materials = preload("res://scripts/systems/world/settlement_materials.gd")
const STONE_ROOFS: Array[Color] = [Color("8c513b"), Color("725552"), Color("74604c")]
const TIMBER_ROOFS: Array[Color] = [Color("685039"), Color("8b6b46"), Color("6b6450")]

var _rooms: Array[Rect2i] = []
var _fog_state: Callable
var _player_tile: Vector2i
var _damaged: Dictionary = {}
var _materials: Dictionary = {}
var _styles: Dictionary = {}
var _ramparts: Dictionary = {}

func _ready() -> void:
	z_index = 2
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.fog_batch_updated.connect(func(_changes: Array) -> void: queue_redraw())
	SignalBus.hour_passed.connect(func(_hour: int) -> void: queue_redraw())
	SignalBus.structure_destroyed.connect(_on_structure_destroyed)

func configure(info: Dictionary, removed: Array, fog_state: Callable, player_tile: Vector2i) -> void:
	_rooms.assign(info.get("roofs", []))
	_fog_state = fog_state
	_player_tile = player_tile
	_damaged.clear()
	_materials.clear()
	var streets: Dictionary = info.get("streets", {})
	_styles = streets.get("styles", {})
	_ramparts = streets.get("ramparts", {}).duplicate()
	var structures: Dictionary = info.get("structures", {})
	for room: Rect2i in _rooms:
		_materials[room.position] = structures.get(Config.vec2i_to_key(room.position), "wood_wall")
	for key: String in removed:
		_on_structure_destroyed("", Config.key_to_vec2i(key))
	queue_redraw()

func _on_player_tile_changed(tile: Vector2i) -> void:
	_player_tile = tile
	queue_redraw()

func _on_structure_destroyed(_id: String, tile: Vector2i) -> void:
	if _ramparts.erase(tile):
		queue_redraw()
	for room: Rect2i in _rooms:
		if room.has_point(tile):
			_damaged[room.position] = true
			queue_redraw()

func _draw() -> void:
	for tile: Vector2i in _ramparts:
		var fog: int = _fog_state.call(tile)
		if fog != 0:
			_draw_rampart(tile, _ramparts[tile], fog == 2)
	for room: Rect2i in _rooms:
		if room.grow(1).has_point(_player_tile) or _damaged.has(room.position):
			continue
		var fog: int = int(_fog_state.call(room.get_center()))
		if fog == 0:
			continue
		var masonry: bool = _materials[room.position] == "wall"
		var palette: Array[Color] = STONE_ROOFS if masonry else TIMBER_ROOFS
		var color: Color = palette[posmod(hash(room.position), palette.size())]
		var style: String = _styles.get(room.position, "")
		match style:
			"basilica", "temple":
				color = Color("a0543a")
			"lord_house":
				color = Color("655653")
			"smithy":
				color = Color("4e4741")
			"villa", "shop":
				color = Color("b56c47")
			"thermae":
				color = Color("747a6d")
			"insula":
				color = Color("945940").lerp(Color("b48157"), float(posmod(hash(room.position), 5)) * 0.12)
		if fog == 1:
			color = color.darkened(0.38)
		_draw_room_roof(room, color, masonry, fog == 2, style)

func _draw_room_roof(room: Rect2i, color: Color, masonry: bool, visible_now: bool, style: String) -> void:
	var size: Vector2 = Vector2(room.size * Config.TILE_SIZE)
	var top_left: Vector2 = Config.world_to_iso(room.position) - Vector2(Config.HALF_TILE) + Vector2(-3, -20)
	var bounds := Rect2(top_left, size + Vector2(6, -2))
	var ridge: float = bounds.position.y + bounds.size.y * 0.43
	draw_rect(Rect2(bounds.position + Vector2(9, 13), bounds.size), Color(0.10, 0.08, 0.05, 0.25))
	var civic: bool = style in ["basilica", "temple", "thermae", "lord_house"]
	var facade := Rect2(bounds.position.x + 3, bounds.end.y - 5, bounds.size.x - 6, 35 if civic else 24)
	if civic:
		_draw_portico(facade, visible_now, style == "temple")
	else:
		_draw_facade(facade, masonry, visible_now)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room.position)
	var upright: bool = style == "shop" or (style in ["villa", "insula"] and room.size.y > room.size.x)
	var roofing: int = Materials.Kind.TERRACOTTA if masonry else Materials.Kind.SHINGLES
	match style:
		"lord_house", "thermae":
			roofing = Materials.Kind.SLATE
		"smithy":
			roofing = Materials.Kind.SOOTED_TILE
		"villa", "shop":
			roofing = Materials.Kind.OCHRE_TILE
	var first: Rect2
	var second: Rect2
	var ridge_start: Vector2
	var ridge_end: Vector2
	if upright:
		var center_x: float = bounds.get_center().x
		first = Rect2(bounds.position, Vector2(bounds.size.x * 0.5, bounds.size.y))
		second = Rect2(center_x, bounds.position.y, bounds.size.x * 0.5, bounds.size.y)
		ridge_start = Vector2(center_x, bounds.position.y)
		ridge_end = Vector2(center_x, bounds.end.y)
	else:
		first = Rect2(bounds.position, Vector2(bounds.size.x, ridge - bounds.position.y))
		second = Rect2(bounds.position.x, ridge, bounds.size.x, bounds.end.y - ridge)
		ridge_start = Vector2(bounds.position.x, ridge)
		ridge_end = Vector2(bounds.end.x, ridge)
	var exposure: Color = Color.WHITE if visible_now else Color("8c8a93")
	if roofing == Materials.Kind.OCHRE_TILE:
		exposure *= Color("d2c9b9")
	Materials.draw_surface(self, first, roofing, exposure)
	Materials.draw_surface(self, second, roofing, exposure * Color("bdb5aa"))
	draw_line(ridge_start, ridge_end, color.darkened(0.38), 7.0)
	draw_line(ridge_start - Vector2.ONE * 2, ridge_end - Vector2.ONE * 2, color.lightened(0.30), 3.0)
	draw_rect(bounds, color.darkened(0.55), false, 3.0)
	if civic:
		_draw_civic_roof(bounds, color, style, roofing, exposure)
	elif masonry or room.size.x >= 5:
		var chimney := Rect2(bounds.position + Vector2(bounds.size.x * rng.randf_range(0.21, 0.78), bounds.size.y * 0.32), Vector2(20, 28))
		draw_rect(Rect2(chimney.position + Vector2(5, 8), chimney.size), Color(0.1, 0.06, 0.04, 0.4))
		draw_rect(chimney, Color("736b60"))
		draw_line(chimney.position + Vector2(0, 19), chimney.position + Vector2(20, 19), Color("4a433a"), 2)
		draw_rect(Rect2(chimney.position - Vector2(2, 3), Vector2(24, 12)), Color("a19580"))
		draw_rect(Rect2(chimney.position + Vector2(3, 0), Vector2(14, 6)), Color("322c25"))
	if style == "lord_house":
		for ratio: float in [0.23, 0.77]:
			var banner := Rect2(facade.position + Vector2(facade.size.x * ratio - 6, 5), Vector2(12, 29))
			draw_rect(banner, Color("994432") if visible_now else Color("5f352d"))
			draw_line(banner.get_center() - Vector2(0, 7), banner.get_center() + Vector2(0, 7), Color("c9a564"), 2)
	elif style == "smithy":
		var stack := Rect2(bounds.position + bounds.size * Vector2(0.72, 0.18), Vector2(26, 42))
		draw_rect(Rect2(stack.position + Vector2(5, 6), stack.size), Color(0.1, 0.07, 0.06, 0.45))
		draw_rect(stack, Color("65534a"))
		draw_rect(Rect2(stack.position - Vector2(3, 4), Vector2(32, 17)), Color("998577"))
		draw_rect(Rect2(stack.position + Vector2(2, 0), Vector2(22, 9)), Color("322a26"))


func _draw_rampart(tile: Vector2i, tower: bool, visible_now: bool) -> void:
	var center: Vector2 = Config.world_to_iso(tile)
	var stone: Color = Color("9a8b73") if visible_now else Color("60594f")
	var width: float = 66.0 if tower else float(Config.TILE_SIZE.x)
	var height: float = 66.0 if tower else float(Config.TILE_SIZE.y)
	var top := Rect2(center - Vector2(width * 0.5, height * 0.5 + 9), Vector2(width, height))
	draw_rect(Rect2(top.position + Vector2(0, 10), top.size), stone.darkened(0.48))
	draw_rect(top, stone.darkened(0.24))
	Materials.draw_surface(self, top.grow(-6), Materials.Kind.ASHLAR, Color.WHITE if visible_now else Color("88818a"))
	var parapet: Rect2 = top.grow(-2)
	draw_rect(parapet, stone.lightened(0.14), false, 3)
	for offset: float in [7.0, 21.0, 35.0]:
		draw_rect(Rect2(top.position + Vector2(offset, 0), Vector2(7, 7)), stone.lightened(0.21))
		draw_rect(Rect2(top.position + Vector2(offset, height - 6), Vector2(7, 6)), stone.darkened(0.08))
	if tower:
		draw_rect(top.grow(-12), stone.darkened(0.35))
		draw_rect(top.grow(-17), stone.lightened(0.05))
		draw_rect(Rect2(center - Vector2(5, 13), Vector2(10, 10)), stone.darkened(0.50))


func _draw_portico(facade: Rect2, visible_now: bool, temple: bool) -> void:
	var stone: Color = Color("c9b69a") if visible_now else Color("7a7064")
	draw_rect(facade, stone.darkened(0.67))
	Materials.draw_surface(self, facade, Materials.Kind.PLASTER, stone.darkened(0.46))
	draw_rect(Rect2(facade.position, Vector2(facade.size.x, 8)), stone)
	draw_rect(Rect2(facade.position.x, facade.end.y - 6, facade.size.x, 6), stone.darkened(0.18))
	var columns: int = maxi(3, roundi(facade.size.x / 34.0))
	for index: int in range(columns):
		var x: float = lerpf(facade.position.x + 12, facade.end.x - 12, float(index) / float(columns - 1))
		draw_rect(Rect2(x - 4, facade.position.y + 7, 8, facade.size.y - 12), stone)
		draw_rect(Rect2(x + 2, facade.position.y + 8, 2, facade.size.y - 14), stone.darkened(0.26))
		draw_rect(Rect2(x - 6, facade.end.y - 9, 12, 4), stone.lightened(0.12))
	if temple:
		var steps := Rect2(facade.position.x - 3, facade.end.y, facade.size.x + 6, 7)
		draw_rect(steps, stone.darkened(0.27))
		draw_line(steps.position + Vector2(0, 3), Vector2(steps.end.x, steps.position.y + 3), stone.darkened(0.48), 2)


func _draw_civic_roof(bounds: Rect2, color: Color, style: String, roofing: int, exposure: Color) -> void:
	match style:
		"temple":
			var left := Vector2(bounds.position.x, bounds.end.y)
			var right := bounds.end
			var peak := Vector2(bounds.get_center().x, bounds.end.y - bounds.size.y * 0.24)
			var stone: Color = color.lerp(Color("d1bd9a"), 0.58)
			draw_colored_polygon(PackedVector2Array([left, peak, right]), stone.darkened(0.24))
			draw_polyline(PackedVector2Array([left, peak, right, left]), stone.lightened(0.12), 4)
			draw_circle(peak.lerp(Vector2(peak.x, left.y), 0.65), 5, stone.darkened(0.43))
		"lord_house":
			var terrace := Rect2(bounds.position + bounds.size * Vector2(0.24, 0.16), bounds.size * Vector2(0.52, 0.55))
			draw_rect(terrace.grow(4), color.darkened(0.42))
			draw_rect(terrace, color.lightened(0.16))
			Materials.draw_surface(self, terrace.grow(-9), Materials.Kind.FLAGSTONE, exposure)
			for corner: Vector2 in [bounds.position, Vector2(bounds.end.x - 43, bounds.position.y),
					Vector2(bounds.position.x, bounds.end.y - 43), bounds.end - Vector2(43, 43)]:
				var tower := Rect2(corner, Vector2(43, 43))
				draw_rect(tower.grow(2), color.darkened(0.48))
				draw_rect(tower, color.lightened(0.28))
				Materials.draw_surface(self, tower.grow(-7), Materials.Kind.ASHLAR, exposure)
				for offset: float in [0.0, 17.0, 34.0]:
					draw_rect(Rect2(corner + Vector2(offset, 0), Vector2(9, 8)), color.lightened(0.41))
			var mast: Vector2 = terrace.get_center()
			draw_line(mast, mast - Vector2(0, 28), Color("302923"), 3)
			draw_colored_polygon(PackedVector2Array([mast - Vector2(0, 28), mast + Vector2(27, -22),
				mast - Vector2(0, 15)]), Color("a74b39"))
		"basilica":
			var nave := Rect2(bounds.position + bounds.size * Vector2(0.12, 0.22), bounds.size * Vector2(0.76, 0.43))
			draw_rect(Rect2(nave.position + Vector2(4, 8), nave.size), color.darkened(0.50))
			Materials.draw_surface(self, nave, roofing, exposure)
			draw_line(Vector2(nave.position.x, nave.get_center().y), Vector2(nave.end.x, nave.get_center().y), color.darkened(0.34), 5)
		"thermae":
			var radius: float = minf(bounds.size.x, bounds.size.y) * 0.24
			var center: Vector2 = bounds.get_center()
			draw_circle(center + Vector2(5, 8), radius + 4, color.darkened(0.58))
			draw_circle(center, radius + 3, color.darkened(0.32))
			draw_circle(center, radius, color.lightened(0.27))
			for ring: int in range(1, 5):
				draw_arc(center, radius * float(ring) / 5.0, 0.0, TAU, 30, color.darkened(0.20), 2)
			draw_circle(center - Vector2(3, 3), 6, color.lightened(0.45))


func _draw_facade(facade: Rect2, masonry: bool, visible_now: bool) -> void:
	var wall_color: Color = Color("807668") if masonry else Color("79583d")
	if not visible_now:
		wall_color = wall_color.darkened(0.38)
	Materials.draw_surface(self, facade, Materials.Kind.ASHLAR if masonry else Materials.Kind.OAK, Color.WHITE if visible_now else Color("8c8a93"))
	var hour: float = GameManager.get_hour()
	var glass: Color = Color("f3ad5e") if visible_now and (hour < 6.0 or hour >= 19.0) else Color("383c3a")
	for segment: int in range(roundi(facade.size.x / float(Config.TILE_SIZE.x))):
		var x: float = facade.position.x + segment * Config.TILE_SIZE.x
		if masonry:
			draw_line(Vector2(x, facade.end.y - 7), Vector2(x + Config.TILE_SIZE.x, facade.end.y - 7), wall_color.darkened(0.33))
		else:
			draw_rect(Rect2(x, facade.position.y, 4, facade.size.y), wall_color.darkened(0.43))
		if segment % 2 == 0:
			var window := Rect2(x + 15, facade.end.y - 16, 17, 14)
			draw_rect(window, wall_color.darkened(0.54))
			draw_rect(window.grow(-3), glass)
			draw_line(window.get_center() - Vector2(0, 5), window.get_center() + Vector2(0, 5), wall_color.darkened(0.49))
	draw_line(Vector2(facade.position.x, facade.end.y), facade.end, wall_color.darkened(0.43), 2)


