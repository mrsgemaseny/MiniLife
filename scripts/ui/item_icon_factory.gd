class_name ItemIconFactory
extends RefCounted

# Procedural 32x32 pixel-art ImageTexture generator & cache for all items and structures.

static var _icon_cache: Dictionary = {}


static func get_icon(item_id: String) -> ImageTexture:
	if item_id.is_empty():
		return null
	if _icon_cache.has(item_id):
		return _icon_cache[item_id] as ImageTexture

	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_item_art(img, item_id)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_icon_cache[item_id] = tex
	return tex


static func _draw_item_art(img: Image, id: String) -> void:
	var out: Color = Color(0.08, 0.09, 0.12, 0.96)
	if id.find("axe") != -1:
		# Diagonal wooden handle + stone/iron axe blade
		_draw_thick_line(img, Vector2i(6, 26), Vector2i(24, 8), Color(0.55, 0.36, 0.18), 2, out)
		var blade_col: Color = Color(0.76, 0.80, 0.86) if id.find("iron") != -1 else Color(0.58, 0.60, 0.64)
		_fill_circle(img, Vector2i(21, 11), 6, blade_col, out)
		_fill_circle(img, Vector2i(23, 13), 4, blade_col.lightened(0.20), Color(0, 0, 0, 0))
	elif id.find("pick") != -1:
		# Pickaxe handle + curved double pick head
		_draw_thick_line(img, Vector2i(6, 26), Vector2i(23, 9), Color(0.55, 0.36, 0.18), 2, out)
		var head_col: Color = Color(0.74, 0.78, 0.84) if id.find("iron") != -1 else Color(0.56, 0.58, 0.62)
		_draw_thick_line(img, Vector2i(14, 6), Vector2i(26, 18), head_col, 2, out)
	elif id.find("sword") != -1 or id.find("blade") != -1 or id.find("dagger") != -1:
		# Metallic blade + brass crossguard + grip
		var steel_col: Color = Color(0.84, 0.88, 0.94)
		_draw_thick_line(img, Vector2i(10, 22), Vector2i(26, 6), steel_col, 2, out)
		_draw_thick_line(img, Vector2i(7, 17), Vector2i(15, 25), Color(0.86, 0.68, 0.24), 2, out)
		_draw_thick_line(img, Vector2i(5, 27), Vector2i(10, 22), Color(0.45, 0.26, 0.14), 2, out)
	elif id.find("bow") != -1:
		# Curved wooden bow + taut white bowstring
		_draw_thick_line(img, Vector2i(9, 6), Vector2i(22, 16), Color(0.62, 0.40, 0.20), 2, out)
		_draw_thick_line(img, Vector2i(22, 16), Vector2i(9, 26), Color(0.62, 0.40, 0.20), 2, out)
		_draw_thick_line(img, Vector2i(9, 6), Vector2i(9, 26), Color(0.88, 0.90, 0.94), 1, Color(0, 0, 0, 0))
	elif id.find("arrow") != -1:
		_draw_thick_line(img, Vector2i(6, 26), Vector2i(25, 7), Color(0.60, 0.42, 0.22), 1, out)
		_fill_circle(img, Vector2i(25, 7), 3, Color(0.80, 0.84, 0.90), out)
		_fill_circle(img, Vector2i(7, 25), 3, Color(0.90, 0.28, 0.24), out)
	elif id.find("wood") != -1 or id.find("log") != -1 or id.find("wall") != -1:
		# Stacked timber logs with light wood rings
		_fill_rect(img, Rect2i(5, 16, 22, 9), Color(0.48, 0.31, 0.16), out)
		_fill_rect(img, Rect2i(7, 9, 18, 8), Color(0.56, 0.37, 0.20), out)
		_fill_circle(img, Vector2i(24, 20), 4, Color(0.82, 0.66, 0.44), out)
		_fill_circle(img, Vector2i(23, 13), 3, Color(0.82, 0.66, 0.44), out)
	elif id.find("stone") != -1 or id.find("flint") != -1:
		# Craggy gray boulder / flint shard
		var scol: Color = Color(0.56, 0.60, 0.65) if id.find("stone") != -1 else Color(0.36, 0.38, 0.44)
		_fill_circle(img, Vector2i(16, 18), 9, scol, out)
		_fill_circle(img, Vector2i(13, 14), 6, scol.lightened(0.18), Color(0, 0, 0, 0))
	elif id.find("iron") != -1 or id.find("copper") != -1 or id.find("ingot") != -1:
		var mcol: Color = Color(0.82, 0.52, 0.28) if id.find("copper") != -1 else Color(0.74, 0.80, 0.88)
		if id.find("ingot") != -1:
			_fill_rect(img, Rect2i(6, 12, 20, 10), mcol, out)
			_fill_rect(img, Rect2i(8, 14, 16, 4), mcol.lightened(0.22), Color(0, 0, 0, 0))
		elif id.find("chainmail") != -1 or id.find("armor") != -1:
			_fill_rect(img, Rect2i(8, 7, 16, 18), mcol, out)
			_fill_rect(img, Rect2i(5, 8, 22, 7), mcol.darkened(0.12), out)
		else:
			_fill_circle(img, Vector2i(16, 17), 9, Color(0.48, 0.50, 0.54), out)
			_fill_circle(img, Vector2i(14, 15), 3, mcol.lightened(0.25), out)
			_fill_circle(img, Vector2i(19, 19), 3, mcol.lightened(0.25), out)
	elif id.find("food") != -1 or id.find("meat") != -1 or id.find("stew") != -1:
		# Roasted meat on bone
		_draw_thick_line(img, Vector2i(6, 25), Vector2i(25, 7), Color(0.92, 0.88, 0.80), 2, out)
		var meat_col: Color = Color(0.76, 0.36, 0.20) if id.find("cooked") != -1 else Color(0.86, 0.28, 0.30)
		_fill_circle(img, Vector2i(16, 16), 8, meat_col, out)
		_fill_circle(img, Vector2i(14, 13), 4, meat_col.lightened(0.20), Color(0, 0, 0, 0))
	elif id.find("bread") != -1:
		_fill_rect(img, Rect2i(5, 12, 22, 11), Color(0.84, 0.58, 0.24), out)
		_fill_rect(img, Rect2i(7, 10, 18, 6), Color(0.94, 0.72, 0.34), out)
	elif id.find("bandage") != -1 or id.find("medicine") != -1 or id.find("splint") != -1:
		# White medical roll / potion with crimson cross
		_fill_rect(img, Rect2i(7, 8, 18, 16), Color(0.92, 0.93, 0.96), out)
		_fill_rect(img, Rect2i(14, 11, 4, 10), Color(0.86, 0.18, 0.22), Color(0, 0, 0, 0))
		_fill_rect(img, Rect2i(11, 14, 10, 4), Color(0.86, 0.18, 0.22), Color(0, 0, 0, 0))
	elif id.find("berr") != -1 or id.find("herb") != -1:
		_fill_circle(img, Vector2i(16, 17), 9, Color(0.24, 0.58, 0.28), out)
		if id.find("berr") != -1:
			_fill_circle(img, Vector2i(13, 15), 3, Color(0.90, 0.18, 0.22), out)
			_fill_circle(img, Vector2i(19, 17), 3, Color(0.90, 0.18, 0.22), out)
			_fill_circle(img, Vector2i(15, 20), 3, Color(0.90, 0.18, 0.22), out)
	elif id.find("cloth") != -1 or id.find("leather") != -1:
		var ccol: Color = Color(0.84, 0.80, 0.72) if id.find("cloth") != -1 else Color(0.62, 0.40, 0.22)
		_fill_rect(img, Rect2i(7, 9, 18, 14), ccol, out)
		_fill_rect(img, Rect2i(9, 12, 14, 4), ccol.lightened(0.15), Color(0, 0, 0, 0))
	elif id.find("campfire") != -1 or id.find("torch") != -1 or id.find("forge") != -1:
		_fill_circle(img, Vector2i(16, 20), 7, Color(0.96, 0.42, 0.10), out)
		_fill_circle(img, Vector2i(16, 15), 5, Color(1.0, 0.86, 0.24), out)
	else:
		_fill_rect(img, Rect2i(7, 7, 18, 18), Color(0.64, 0.52, 0.34), out)


static func _fill_rect(img: Image, r: Rect2i, fill: Color, border: Color) -> void:
	for y in range(maxi(0, r.position.y), mini(32, r.position.y + r.size.y)):
		for x in range(maxi(0, r.position.x), mini(32, r.position.x + r.size.x)):
			var is_edge: bool = (x == r.position.x or x == r.position.x + r.size.x - 1 or y == r.position.y or y == r.position.y + r.size.y - 1)
			if is_edge and border.a > 0.0:
				img.set_pixel(x, y, border)
			else:
				img.set_pixel(x, y, fill)


static func _fill_circle(img: Image, center: Vector2i, radius: int, fill: Color, border: Color) -> void:
	var r2: int = radius * radius
	var br2: int = (radius - 1) * (radius - 1)
	for y in range(maxi(0, center.y - radius), mini(32, center.y + radius + 1)):
		for x in range(maxi(0, center.x - radius), mini(32, center.x + radius + 1)):
			var dx: int = x - center.x
			var dy: int = y - center.y
			var d2: int = dx * dx + dy * dy
			if d2 <= r2:
				if d2 >= br2 and border.a > 0.0:
					img.set_pixel(x, y, border)
				else:
					img.set_pixel(x, y, fill)


static func _draw_thick_line(img: Image, a: Vector2i, b: Vector2i, col: Color, thickness: int, border: Color) -> void:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	if steps == 0:
		return
	for s in range(steps + 1):
		var t: float = float(s) / float(steps)
		var px: int = int(round(lerpf(float(a.x), float(b.x), t)))
		var py: int = int(round(lerpf(float(a.y), float(b.y), t)))
		_fill_circle(img, Vector2i(px, py), thickness, col, border)
