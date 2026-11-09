class_name CorpseEntity
extends LootBag

var species: String = "wolf"
var lifetime: float = 240.0
var resident_id: String = ""
var settlement_id: String = ""
var faction_id: String = ""

func _ready() -> void:
	keep_empty = true
	super._ready()
	add_to_group("corpses")

func _process(delta: float) -> void:
	if GameManager.is_paused():
		return
	lifetime -= delta
	if lifetime < 15.0:
		modulate.a = clampf(lifetime / 15.0, 0.0, 1.0)
	if lifetime <= 0.0:
		queue_free()

func _draw() -> void:
	var texture: Texture2D = AnimalRig.sprite_for(species)
	if texture != null:
		var width: float = 29.0 if species in ["chicken", "hare", "cat", "fish", "spider"] else (58.0 if species in ["cow", "horse", "moose", "bear", "donkey"] else 46.0)
		var height: float = width * texture.get_height() / texture.get_width() * 0.6
		draw_set_transform(Vector2.ZERO, -0.14)
		draw_texture_rect(texture, Rect2(-width * 0.5, -height * 0.5, width, height), false, Color(0.72, 0.69, 0.66))
		draw_set_transform(Vector2.ZERO)
		return
	if not species.contains("wolf") and species not in ["cow", "sheep", "chicken", "deer", "hare", "boar", "bear", "donkey", "horse", "dog", "cat"]:
		draw_set_transform(Vector2(-16, 5), PI * 0.5, Vector2(0.8, 0.8))
		preload("res://scripts/entities/pawn_art.gd").draw_pawn(self, Vector2.ZERO, Vector2.RIGHT, null)
		draw_set_transform(Vector2.ZERO)
		return
	var animal: bool = species in ["cow", "sheep", "chicken", "deer", "hare", "boar", "bear", "donkey", "horse", "dog", "cat"] or species.contains("wolf")
	var outline: Color = Color("211f1c")
	var fur: Color = Color("6d6e67") if species.contains("wolf") else Color("79634b")
	var small: bool = species in ["hare", "chicken", "cat"]
	var body_scale: float = 0.65 if small else 1.0
	draw_set_transform(Vector2.ZERO, -0.18, Vector2.ONE * body_scale)
	if animal:
		# A side-lying silhouette: tail, torso, folded legs, neck and muzzle.
		draw_polyline(PackedVector2Array([Vector2(-16, 0), Vector2(-26, -3), Vector2(-30, 0)]), outline, 7.0, true)
		draw_polyline(PackedVector2Array([Vector2(-16, 0), Vector2(-26, -3), Vector2(-30, 0)]), fur, 4.0, true)
		for x: float in [-10.0, 7.0]:
			draw_polyline(PackedVector2Array([Vector2(x, 0), Vector2(x + 3, 9), Vector2(x + 10, 10)]), outline, 5.0, true)
			draw_polyline(PackedVector2Array([Vector2(x, 0), Vector2(x + 3, 8), Vector2(x + 9, 9)]), fur.darkened(0.15), 3.0, true)
		draw_set_transform(Vector2.ZERO, -0.18, Vector2(body_scale, body_scale * 0.48))
		draw_circle(Vector2(0,-2), 21, outline)
		draw_circle(Vector2(0,-2), 18.5, fur)
		draw_set_transform(Vector2.ZERO, -0.18, Vector2.ONE * body_scale)
		draw_circle(Vector2(20, -4), 8, outline)
		draw_circle(Vector2(20, -4), 6.5, fur)
		draw_colored_polygon(PackedVector2Array([Vector2(15,-9),Vector2(16,-17),Vector2(22,-10)]), fur.darkened(0.25))
		draw_line(Vector2(24,-3),Vector2(32,0), fur.darkened(0.1), 7.0, true)
		draw_circle(Vector2(32,0), 2.0, outline)
		draw_line(Vector2(21,-5), Vector2(24,-4), outline, 1.3, true)
	else:
		draw_style_box(_body_style(outline), Rect2(-20,-8,38,15))
		draw_style_box(_body_style(Color("665c4d")), Rect2(-18,-6,34,11))
		draw_circle(Vector2(23,-2), 7, Color("9b8066"))
	draw_set_transform(Vector2.ZERO)
	if not items.is_empty() or gold > 0:
		draw_circle(Vector2(0, -20), 2.0, Color("b7ad75"))

func _body_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	return style
