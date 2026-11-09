class_name FlatPawnArt
extends RefCounted

const INK: Color = Color("25251f")

static func material(id: String) -> Color:
	if id.begins_with("bronze_"): return Color("9f824d")
	if id.begins_with("steel_") and not id.contains("brigandine"): return Color("8c9090")
	if id.contains("brigandine"): return Color("774e47")
	if id.contains("iron") or id.contains("chainmail"): return Color("717473")
	if id == "quality_clothing": return Color("59634b")
	if id == "arming_doublet": return Color("884f48")
	if id == "gambeson" or id == "wool_shirt" or id == "wool_wraps": return Color("b4a68c")
	return Color("796147")

static func polygon(canvas: Node2D, offset: Vector2, points: Array, color: Color, width: float = 1.5) -> void:
	var vertices: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		vertices.append(point + offset)
	canvas.draw_colored_polygon(vertices, color)
	vertices.append(vertices[0])
	canvas.draw_polyline(vertices, INK, width, true)

static func line(canvas: Node2D, offset: Vector2, from: Vector2, to: Vector2, color: Color = INK, width: float = 1.0) -> void:
	canvas.draw_line(offset + from, offset + to, color, width, true)

static func draw_pawn(canvas: Node2D, offset: Vector2, facing: Vector2, equipment: EquipmentComponent, clothing_tint: Color, head_lift: float) -> void:
	var side: bool = absf(facing.x) > absf(facing.y)
	var back: bool = not side and facing.y < 0
	var sign_x: float = -1.0 if facing.x < 0 else 1.0
	var chest: String = equipment.get_item_id("chest") if equipment != null else ""
	var clothing: String = equipment.get_item_id("clothing") if equipment != null else ""
	var body_id: String = chest if not chest.is_empty() else clothing
	var body_color: Color = material(body_id) * clothing_tint
	var w: float = 11.5 if side else 15.0
	# Rounded shoulders above straight sides and a flat hem. The head overlaps the dome.
	var body_outline: Array[Vector2] = [Vector2(-w, 0)]
	for step: int in range(17):
		var angle: float = PI + PI * float(step) / 16.0
		body_outline.append(Vector2(cos(angle) * w, -22.0 + sin(angle) * 15.0))
	body_outline.append(Vector2(w, 0))
	polygon(canvas, offset, body_outline, body_color, 1.8)
	var metal: bool = body_id.contains("iron") or body_id.contains("steel") or body_id.contains("bronze")
	var mail: bool = body_id.contains("mail") or body_id.contains("hauberk")
	var lamellar: bool = body_id.contains("lamellar") or body_id.contains("scale")
	var brigandine: bool = body_id.contains("brigandine")
	if metal and not mail and not brigandine:
		polygon(canvas, offset, [Vector2(-w*0.65,-24), Vector2(w*0.65,-24), Vector2(w*0.78,-17), Vector2(w*0.55,-10), Vector2(0,-8), Vector2(-w*0.55,-10), Vector2(-w*0.78,-17)], body_color.lightened(0.08), 1.0)
		if not side:
			line(canvas, offset, Vector2(0,-23), Vector2(0,-10), body_color.darkened(0.35))
		for x: float in [-1.0,1.0]:
			polygon(canvas, offset, [Vector2(x*w*0.6,-25),Vector2(x*w*0.92,-23),Vector2(x*w*0.92,-18),Vector2(x*w*0.65,-18)],body_color,1.0)
	if mail:
		for y: int in range(-22,-7,4):
			for x: int in range(-6,7,4):
				canvas.draw_arc(offset+Vector2(x,y),1.2,0,PI,5,INK,0.65,true)
	elif lamellar:
		for y: int in [-19,-14,-9]:
			line(canvas,offset,Vector2(-w*0.65,y),Vector2(w*0.65,y))
	elif body_id.contains("plate_armor"):
		for y: int in [-17,-12,-4]:
			line(canvas,offset,Vector2(-w*0.6,y),Vector2(0,y+1.5))
			line(canvas,offset,Vector2(0,y+1.5),Vector2(w*0.6,y))
	elif body_id == "steel_cuirass":
		line(canvas,offset,Vector2(-w*0.65,-18),Vector2(0,-15))
		line(canvas,offset,Vector2(0,-15),Vector2(w*0.65,-18))
	elif body_id == "boiled_leather_cuirass":
		for x: float in [-1.0,1.0]:
			polygon(canvas,offset,[Vector2(x,-22),Vector2(x*7,-22),Vector2(x*7,-17),Vector2(x,-15)],body_color.lightened(0.07),0.8)
	elif brigandine:
		for y: int in [-21,-16,-11]:
			for x: int in [-6,0,6]:
				canvas.draw_circle(offset+Vector2(x,y),0.7,Color("b7aaa0"))
	elif body_id == "gambeson" or body_id == "arming_doublet":
		for x: int in [-6,0,6]:
			line(canvas,offset,Vector2(x,-23),Vector2(x,-7),body_color.darkened(0.25),0.8)
	# The lower equipment is a hem treatment, never separately drawn feet/legs.
	if equipment != null:
		var legs: String = equipment.get_item_id("legs")
		var feet: String = equipment.get_item_id("feet")
		if not legs.is_empty():
			line(canvas,offset,Vector2(-w*0.73,-4),Vector2(w*0.73,-4),material(legs),2.0)
		if not feet.is_empty():
			line(canvas,offset,Vector2(-w*0.52,-1.7),Vector2(w*0.52,-1.7),material(feet).darkened(0.2),1.5)
	line(canvas,offset,Vector2(-w*0.85,-7),Vector2(w*0.85,-7),Color("514536"),2)
	if not back and not side:
		canvas.draw_rect(Rect2(offset+Vector2(-1.4,-8.2),Vector2(2.8,2.4)),Color("b5aa8c"))
	# Lift the entire head layer, including any helmet.
	offset.y -= head_lift
	var head: String = equipment.get_item_id("head") if equipment != null else ""
	if head.is_empty():
		var center: Vector2 = offset + Vector2(2.0 * sign_x if side else 0.0, -36.0)
		var hair: Color = Color("65503a")
		canvas.draw_circle(center, 10.5, INK, true, -1.0, true)
		canvas.draw_circle(center, 9.0, hair if back else Color("dbb48b"), true, -1.0, true)
		if not back:
			var fringe: PackedVector2Array = PackedVector2Array()
			for step: int in range(13):
				var angle: float = PI + PI * float(step) / 12.0
				fringe.append(center + Vector2.from_angle(angle) * 9.3)
			fringe.append(center + Vector2(3.5, 1.0 if side and sign_x < 0.0 else -3.5))
			fringe.append(center + Vector2(-3.5, 1.0 if side and sign_x > 0.0 else -3.5))
			canvas.draw_colored_polygon(fringe, hair)
			canvas.draw_circle(center + Vector2(4.5 * sign_x, 1.2), 0.95, INK, true, -1.0, true)
			if not side:
				canvas.draw_circle(center + Vector2(-4.5, 1.2), 0.95, INK, true, -1.0, true)
		return
	var head_color: Color = material(head)
	var great: bool = head == "iron_great_helm"
	var hood: bool = head == "wool_hood" or head == "chainmail_coif"
	var armet: bool = head == "steel_helmet"
	var outline: Array = [Vector2(-10,-24),Vector2(-12,-33),Vector2(-10,-41),Vector2(-5,-45),Vector2(0,-47),Vector2(6,-44),Vector2(10,-40),Vector2(12,-33),Vector2(10,-25),Vector2(0,-22)]
	if great: outline = [Vector2(-10,-44),Vector2(0,-46),Vector2(10,-44),Vector2(11,-24),Vector2(0,-22),Vector2(-11,-24)]
	if armet and side:
		outline = [Vector2(-9,-24),Vector2(-11,-34),Vector2(-8,-42),Vector2(-2,-46),Vector2(6,-44),Vector2(10,-38),Vector2(14,-35),Vector2(10,-31),Vector2(9,-25),Vector2(0,-22)]
		for index: int in range(outline.size()):
			outline[index] = Vector2(outline[index].x * sign_x, outline[index].y)
	polygon(canvas,offset,outline,head_color,1.8)
	if hood:
		if not back:
			var center: Vector2 = offset+Vector2(3*sign_x if side else 0,-33)
			canvas.draw_circle(center,7.3,INK)
			canvas.draw_circle(center,5.8,Color("cba77c"))
			canvas.draw_circle(center+Vector2(2*sign_x,-0.5),0.8,INK)
			if not side: canvas.draw_circle(center+Vector2(-2,-0.5),0.8,INK)
		return
	line(canvas,offset,Vector2(0,-43),Vector2(0,-37),head_color.lightened(0.25))
	if back:
		line(canvas,offset,Vector2(-8,-28),Vector2(8,-28),head_color.darkened(0.3))
	elif armet or great:
		var shift: float = sign_x*4 if side else 0
		line(canvas,offset,Vector2(-7+shift,-35),Vector2(7+shift,-35),INK,2)
		if armet:
			line(canvas,offset,Vector2(-9,-38),Vector2(0,-35))
			line(canvas,offset,Vector2(0,-35),Vector2(10,-38))
		for x: int in [-5,-2,2,5]:
			line(canvas,offset,Vector2(x+shift,-31.5),Vector2(x+shift,-28),INK,0.8)
	else:
		polygon(canvas,offset,[Vector2(-7,-34),Vector2(7,-34),Vector2(6,-26),Vector2(-6,-26)],Color("cba77c"),1)
		line(canvas,offset,Vector2(0,-35),Vector2(0,-30),INK,1.5)
