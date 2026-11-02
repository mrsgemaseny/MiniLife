class_name MinecraftVitalsWidget
extends Control

# Authentic Minecraft Survival Vitals Widget
# - 10 Hearts on left (Health) with low-HP jitter and half-heart precision
# - 10 Drumsticks on right (Hunger) filling right-to-left with hunger jitter
# - Segmented Experience / Stamina bar spanning bottom

var current_health: float = 100.0
var max_health: float = 100.0
var current_hunger: float = 100.0
var max_hunger: float = 100.0
var current_stamina: float = 100.0
var max_stamina: float = 100.0

var _last_health: float = 100.0
var _hurt_timer: float = 0.0
var _jitter_timer: float = 0.0
var _jitter_offsets_hp: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
var _jitter_offsets_hunger: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

# Cached textures for pixel-perfect 14x14 icons
static var _tex_heart_full: ImageTexture = null
static var _tex_heart_half: ImageTexture = null
static var _tex_heart_empty: ImageTexture = null
static var _tex_heart_flash: ImageTexture = null

static var _tex_hunger_full: ImageTexture = null
static var _tex_hunger_half: ImageTexture = null
static var _tex_hunger_empty: ImageTexture = null

const ICON_SIZE: int = 14
const ICON_GAP: int = 2
const NUM_ICONS: int = 10


func _init() -> void:
	custom_minimum_size = Vector2(380, 22)
	size_flags_horizontal = SIZE_SHRINK_CENTER
	mouse_filter = MOUSE_FILTER_PASS
	_ensure_textures()


func _process(delta: float) -> void:
	var needs_redraw: bool = false

	if _hurt_timer > 0.0:
		_hurt_timer = maxf(0.0, _hurt_timer - delta)
		needs_redraw = true

	# Jitter low health (<= 20%) and low hunger (<= 30%)
	_jitter_timer += delta
	if _jitter_timer >= 0.10:
		_jitter_timer = 0.0
		var hp_pct: float = current_health / maxf(1.0, max_health)
		var hunger_pct: float = current_hunger / maxf(1.0, max_hunger)

		if hp_pct <= 0.22 or _hurt_timer > 0.0:
			for i in range(NUM_ICONS):
				_jitter_offsets_hp[i] = (randi() % 3) - 1
			needs_redraw = true
		elif _jitter_offsets_hp[0] != 0:
			_jitter_offsets_hp.fill(0)
			needs_redraw = true

		if hunger_pct <= 0.32:
			for i in range(NUM_ICONS):
				_jitter_offsets_hunger[i] = (randi() % 3) - 1
			needs_redraw = true
		elif _jitter_offsets_hunger[0] != 0:
			_jitter_offsets_hunger.fill(0)
			needs_redraw = true

	if needs_redraw:
		queue_redraw()


func set_health(cur: float, max_val: float) -> void:
	if cur < current_health:
		_hurt_timer = 0.35 # Hurt flash on damage
	current_health = clampf(cur, 0.0, max_val)
	max_health = maxf(1.0, max_val)
	_last_health = current_health
	tooltip_text = "Health: %d / %d  |  Hunger: %d / %d" % [int(round(current_health)), int(round(max_health)), int(round(current_hunger)), int(round(max_hunger))]
	queue_redraw()


func set_hunger(cur: float, max_val: float) -> void:
	current_hunger = clampf(cur, 0.0, max_val)
	max_hunger = maxf(1.0, max_val)
	tooltip_text = "Health: %d / %d  |  Hunger: %d / %d" % [int(round(current_health)), int(round(max_health)), int(round(current_hunger)), int(round(max_hunger))]
	queue_redraw()


func set_stamina(cur: float, max_val: float) -> void:
	current_stamina = clampf(cur, 0.0, max_val)
	max_stamina = maxf(1.0, max_val)
	queue_redraw()


func _draw() -> void:
	var hp_per_icon: float = max_health / float(NUM_ICONS)
	var hunger_per_icon: float = max_hunger / float(NUM_ICONS)

	# 1. Draw 10 Hearts on the LEFT (left-to-right)
	for i in range(NUM_ICONS):
		var ix: float = float(i * (ICON_SIZE + ICON_GAP))
		var iy: float = float(_jitter_offsets_hp[i])
		var heart_val: float = current_health - float(i) * hp_per_icon

		var tex: ImageTexture = _tex_heart_empty
		if _hurt_timer > 0.0 and (randi() & 1) == 0:
			tex = _tex_heart_flash
		elif heart_val >= hp_per_icon:
			tex = _tex_heart_full
		elif heart_val >= hp_per_icon * 0.35:
			tex = _tex_heart_half

		draw_texture(tex, Vector2(ix, iy))

	# 2. Draw 10 Drumsticks on the RIGHT (Minecraft style: right-aligned, filling right-to-left)
	var right_start_x: float = size.x - float(ICON_SIZE)
	for i in range(NUM_ICONS):
		var ix: float = right_start_x - float(i * (ICON_SIZE + ICON_GAP))
		var iy: float = float(_jitter_offsets_hunger[i])
		var food_val: float = current_hunger - float(i) * hunger_per_icon

		var tex: ImageTexture = _tex_hunger_empty
		if food_val >= hunger_per_icon:
			tex = _tex_hunger_full
		elif food_val >= hunger_per_icon * 0.35:
			tex = _tex_hunger_half

		draw_texture(tex, Vector2(ix, iy))

	# 3. Minecraft-style Segmented Stamina / Experience Bar at bottom
	var bar_y: float = float(ICON_SIZE + 3)
	var bar_w: float = size.x
	var bar_h: float = 4.0

	# Dark indented slot
	draw_rect(Rect2(0.0, bar_y, bar_w, bar_h), Color(0.05, 0.07, 0.09, 0.95))
	draw_rect(Rect2(0.0, bar_y, bar_w, bar_h), Color(0.12, 0.16, 0.20, 0.90), false, 1.0)

	var stam_pct: float = clampf(current_stamina / maxf(1.0, max_stamina), 0.0, 1.0)
	var fill_w: float = (bar_w - 2.0) * stam_pct

	if fill_w > 0.0:
		# Minecraft XP-green segmented fill
		var fill_col: Color = Color(0.33, 0.88, 0.35, 0.95)
		if stam_pct < 0.25:
			fill_col = Color(0.92, 0.55, 0.18, 0.95)
		draw_rect(Rect2(1.0, bar_y + 1.0, fill_w, bar_h - 2.0), fill_col)
		# Specular top highlight line
		draw_line(Vector2(1.0, bar_y + 1.0), Vector2(1.0 + fill_w, bar_y + 1.0), Color(0.70, 1.0, 0.70, 0.80), 1.0)

		# Segment notch dividers every 24 pixels
		var seg_x: float = 24.0
		while seg_x < fill_w:
			draw_line(Vector2(seg_x, bar_y), Vector2(seg_x, bar_y + bar_h), Color(0.05, 0.07, 0.09, 0.85), 1.0)
			seg_x += 24.0


# =========================================================================
# PIXEL ART TEXTURE GENERATORS (14x14)
# =========================================================================

static func _ensure_textures() -> void:
	if _tex_heart_full != null:
		return

	_tex_heart_full = _gen_heart_texture("full")
	_tex_heart_half = _gen_heart_texture("half")
	_tex_heart_empty = _gen_heart_texture("empty")
	_tex_heart_flash = _gen_heart_texture("flash")

	_tex_hunger_full = _gen_hunger_texture("full")
	_tex_hunger_half = _gen_hunger_texture("half")
	_tex_hunger_empty = _gen_hunger_texture("empty")


static func _gen_heart_texture(type: String) -> ImageTexture:
	var img: Image = Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var outline: Color = Color(0.08, 0.09, 0.12, 0.98)
	var bg_dark: Color = Color(0.24, 0.08, 0.10, 0.92)
	var red_deep: Color = Color(0.68, 0.08, 0.12, 1.0)
	var red_mid: Color = Color(0.90, 0.14, 0.18, 1.0)
	var red_light: Color = Color(0.98, 0.38, 0.42, 1.0)
	var glint: Color = Color(1.0, 1.0, 1.0, 1.0)

	if type == "flash":
		red_deep = Color(0.85, 0.88, 0.95, 1.0)
		red_mid = Color(0.98, 0.99, 1.0, 1.0)
		red_light = Color(1.0, 1.0, 1.0, 1.0)

	# Heart 14x14 matrix:
	# Rows:
	# y=1:  ..XX.. ..XX..
	# y=2: .XXXX. .XXXX.
	# y=3: XXXXXX XXXXXX
	# y=4: XXXXXXXXXXXXX
	# y=5: XXXXXXXXXXXXX
	# y=6: XXXXXXXXXXXXX
	# y=7: .XXXXXXXXXXX.
	# y=8: ..XXXXXXXXX..
	# y=9: ...XXXXXXX...
	# y=10: ....XXXXX....
	# y=11: .....XXX.....
	# y=12: ......X......

	# 1. Draw heart container background
	for y in range(1, 13):
		var x_ranges: Array = []
		if y == 1: x_ranges = [[2, 4], [8, 10]]
		elif y == 2: x_ranges = [[1, 5], [7, 11]]
		elif y == 3: x_ranges = [[0, 5], [7, 12]]
		elif y == 4 or y == 5 or y == 6: x_ranges = [[0, 12]]
		elif y == 7: x_ranges = [[1, 11]]
		elif y == 8: x_ranges = [[2, 10]]
		elif y == 9: x_ranges = [[3, 9]]
		elif y == 10: x_ranges = [[4, 8]]
		elif y == 11: x_ranges = [[5, 7]]
		elif y == 12: x_ranges = [[6, 6]]

		for rng in x_ranges:
			for x in range(rng[0], rng[1] + 1):
				img.set_pixel(x, y, outline)

	# 2. Fill interior
	for y in range(2, 12):
		var in_x: Array = []
		if y == 2: in_x = [[2, 4], [8, 10]]
		elif y == 3: in_x = [[1, 4], [8, 11]]
		elif y == 4 or y == 5: in_x = [[1, 11]]
		elif y == 6: in_x = [[1, 11]]
		elif y == 7: in_x = [[2, 10]]
		elif y == 8: in_x = [[3, 9]]
		elif y == 9: in_x = [[4, 8]]
		elif y == 10: in_x = [[5, 7]]
		elif y == 11: in_x = [[6, 6]]

		for rng in in_x:
			for x in range(rng[0], rng[1] + 1):
				if type == "empty":
					img.set_pixel(x, y, bg_dark)
				elif type == "half":
					if x <= 6:
						img.set_pixel(x, y, red_mid)
					else:
						img.set_pixel(x, y, bg_dark)
				else:
					img.set_pixel(x, y, red_mid)

	# 3. Add highlights & bevels for full/half
	if type != "empty":
		# Left lobe glint
		img.set_pixel(2, 3, glint)
		img.set_pixel(3, 3, red_light)
		img.set_pixel(2, 4, red_light)

		# Right lobe highlight (full only)
		if type == "full" or type == "flash":
			img.set_pixel(8, 3, red_light)
			img.set_pixel(9, 3, red_light)

		# Bottom-right shadow
		if type == "full":
			img.set_pixel(8, 7, red_deep)
			img.set_pixel(7, 8, red_deep)
			img.set_pixel(6, 9, red_deep)
			img.set_pixel(5, 10, red_deep)

	return ImageTexture.create_from_image(img)


static func _gen_hunger_texture(type: String) -> ImageTexture:
	var img: Image = Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var outline: Color = Color(0.08, 0.09, 0.12, 0.98)
	var bg_dark: Color = Color(0.20, 0.14, 0.08, 0.92)
	var bone_col: Color = Color(0.92, 0.90, 0.85, 1.0)
	var bone_shadow: Color = Color(0.68, 0.65, 0.58, 1.0)
	var m_roast: Color = Color(0.85, 0.44, 0.14, 1.0)
	var m_shade: Color = Color(0.52, 0.22, 0.06, 1.0)
	var m_hi: Color = Color(0.98, 0.72, 0.28, 1.0)

	# Drumstick outline
	# Bone sticking up-right (x: 9..12, y: 1..5)
	# Meat bulb in lower-left (x: 1..9, y: 4..12)

	# Bone outline
	img.set_pixel(10, 1, outline)
	img.set_pixel(11, 1, outline)
	img.set_pixel(9, 2, outline)
	img.set_pixel(12, 2, outline)
	img.set_pixel(9, 3, outline)
	img.set_pixel(12, 3, outline)
	img.set_pixel(10, 4, outline)
	img.set_pixel(11, 4, outline)

	# Meat bulb outline
	for y in range(4, 13):
		var rng: Array = [2, 8]
		if y == 4: rng = [4, 7]
		elif y == 5: rng = [3, 9]
		elif y == 6 or y == 7: rng = [1, 9]
		elif y == 8: rng = [1, 9]
		elif y == 9: rng = [2, 8]
		elif y == 10: rng = [3, 7]
		elif y == 11: rng = [4, 6]
		elif y == 12: rng = [5, 5]

		img.set_pixel(rng[0], y, outline)
		img.set_pixel(rng[1], y, outline)

	# Fill interior
	if type == "empty":
		for y in range(5, 12):
			for x in range(2, 9):
				if img.get_pixel(x, y).a == 0.0:
					img.set_pixel(x, y, bg_dark)
		img.set_pixel(10, 2, bg_dark)
		img.set_pixel(11, 2, bg_dark)
		img.set_pixel(10, 3, bg_dark)
		img.set_pixel(11, 3, bg_dark)
	else:
		# Bone fill
		img.set_pixel(10, 2, bone_col)
		img.set_pixel(11, 2, bone_col)
		img.set_pixel(10, 3, bone_col)
		img.set_pixel(11, 3, bone_shadow)

		# Meat fill
		for y in range(5, 12):
			for x in range(2, 9):
				if img.get_pixel(x, y).a == 0.0:
					if type == "half" and x < 5:
						img.set_pixel(x, y, bg_dark)
					else:
						img.set_pixel(x, y, m_roast)

		# Highlights on bulb
		img.set_pixel(5, 6, m_hi)
		img.set_pixel(6, 6, m_hi)
		img.set_pixel(5, 7, m_hi)

		# Charred bottom-left shadow
		img.set_pixel(2, 7, m_shade)
		img.set_pixel(3, 9, m_shade)
		img.set_pixel(4, 10, m_shade)

	return ImageTexture.create_from_image(img)
