class_name AnimalRig
extends RefCounted

static var _textures: Dictionary = {}

static func sprite_for(species: String) -> Texture2D:
	if _textures.has(species):
		return _textures[species]
	var path: String = "res://assets/sprites/world/fauna/transparent_v2/" + species + ".tres"
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_textures[species] = texture
	return texture

static func ellipse(canvas: Node2D, center: Vector2, size: Vector2, color: Color, facing: float) -> void:
	canvas.draw_set_transform(Vector2(center.x * facing, center.y), 0.0, Vector2(size.x, size.y))
	canvas.draw_circle(Vector2.ZERO, 1.0, Color("24221e"))
	canvas.draw_circle(Vector2.ZERO, 0.87, color)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1))

static func draw_animal(canvas: Node2D, species: String, phase: float, walking: float, facing: float, grazing: bool, sleeping: bool) -> void:
	var texture: Texture2D = sprite_for(species)
	if texture != null:
		var small: bool = species in ["chicken", "hare", "cat", "fish", "spider"]
		var large: bool = species in ["cow", "horse", "moose", "bear", "donkey"]
		var width: float = 29.0 if small else (58.0 if large else 46.0)
		var height: float = width * texture.get_height() / texture.get_width()
		var bob: float = -absf(sin(phase)) * walking * 1.2
		var breath: float = 1.0 + (sin(Time.get_ticks_msec() * 0.002) * 0.015 if sleeping else 0.0)
		canvas.draw_set_transform(Vector2(0.0, bob), 0.04 if grazing else 0.0, Vector2(facing, breath))
		canvas.draw_texture_rect(texture, Rect2(-width * 0.5, -height, width, height), false)
		canvas.draw_set_transform(Vector2.ZERO)
		return
	var color: Color = Color("8b7455")
	match species:
		"fox": color = Color("b9652b")
		"wolf", "direwolf": color = Color("777b73")
		"sheep": color = Color("c5bfa9")
		"cow": color = Color("a59579")
		"pig": color = Color("b18b7a")
		"boar", "bear", "moose": color = Color("61503c")
		"cat": color = Color("8c8372")
	var small: bool = species in ["chicken", "hare", "cat"]
	var large: bool = species in ["cow", "horse", "moose", "bear", "donkey"]
	var length: float = 9.0 if small else (20.0 if large else 15.0)
	var body_y: float = -7.0 if sleeping or small else -15.0
	var bob: float = sin(phase * 2) * walking
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing,1))
	# Limbs move independently of the torso instead of sliding a single image.
	if not sleeping:
		for i in range(4):
			var x: float = (-0.65 if i < 2 else 0.6) * length + (2.0 if i % 2 == 0 else -2.0)
			var stride: float = sin(phase + (PI if i % 2 == 0 else 0.0)) * walking * 4.0
			var foot: Vector2 = Vector2(x + stride, 1)
			canvas.draw_line(Vector2(x, body_y), foot, Color("29251f"), 4.5, true)
			canvas.draw_line(Vector2(x, body_y), foot, color.darkened(0.15 if i % 2 == 0 else 0.3), 2.5, true)
	if species in ["fox", "wolf", "cat", "dog", "direwolf"]:
		var tail: Vector2 = Vector2(-length - 10, body_y + sin(phase)*walking*3)
		canvas.draw_line(Vector2(-length + 2, body_y), tail, color.darkened(0.15), 7, true)
		if species == "fox":
			canvas.draw_circle(tail, 3, Color("d5ccac"))
	ellipse(canvas, Vector2(0,body_y+bob), Vector2(length,8 if small else 11), color, facing)
	if species == "sheep":
		for i in range(7):
			var fleece: Vector2 = Vector2(-length+4+i*4, body_y-5+bob)
			canvas.draw_circle(fleece, 4.5, color.lightened(0.12))
	if species == "cow":
		canvas.draw_circle(Vector2(-7,body_y-2+bob),4.5,Color("504534"))
		canvas.draw_circle(Vector2(6,body_y+2+bob),3.5,Color("504534"))
	if species in ["horse", "donkey"]:
		canvas.draw_polyline(PackedVector2Array([Vector2(length*0.5,body_y-7),Vector2(length*0.8,body_y-14),Vector2(length,body_y-12)]),color.darkened(0.4),4,true)
	var head: Vector2 = Vector2(length * 0.8, body_y - (2 if small else 5) + (10 if grazing else 0) + bob)
	ellipse(canvas, head, Vector2(6 if small else 8, 6 if small else 9), color.lightened(0.08), facing)
	canvas.draw_colored_polygon(PackedVector2Array([head+Vector2(-4,-5),head+Vector2(-5,-13 if species == "hare" else -10),head+Vector2(1,-5)]), color.darkened(0.2))
	if species == "hare":
		canvas.draw_line(head+Vector2(1,-3),head+Vector2(3,-14),color.lightened(0.1),3.5,true)
	if species in ["cow", "sheep"]:
		canvas.draw_polyline(PackedVector2Array([head+Vector2(-3,-6),head+Vector2(-8,-9),head+Vector2(-6,-13)]),Color("c5b899"),2.5,true)
		canvas.draw_polyline(PackedVector2Array([head+Vector2(3,-6),head+Vector2(7,-9),head+Vector2(6,-12)]),Color("c5b899"),2.5,true)
	if species in ["moose", "deer"]:
		for side: float in [-1.0,1.0]:
			var base: Vector2 = head+Vector2(side*3,-7)
			canvas.draw_polyline(PackedVector2Array([base,base+Vector2(side*5,-8),base+Vector2(side*8,-12)]), Color("aa9570"), 2, true)
			canvas.draw_line(base+Vector2(side*5,-8),base+Vector2(side*10,-5),Color("aa9570"),2,true)
	if species == "chicken":
		canvas.draw_colored_polygon(PackedVector2Array([head+Vector2(5,-1),head+Vector2(11,1),head+Vector2(5,3)]),Color("be913a"))
	else:
		canvas.draw_line(head+Vector2(4,2),head+Vector2(10,4),color.darkened(0.2),5,true)
	if sleeping:
		canvas.draw_line(head+Vector2(2,-2),head+Vector2(5,-1),Color("22221e"),1.2,true)
	else:
		canvas.draw_circle(head+Vector2(4,-2),1.2,Color("1a1916"))
	canvas.draw_set_transform(Vector2.ZERO)
