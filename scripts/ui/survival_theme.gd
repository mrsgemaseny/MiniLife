class_name SurvivalTheme
extends RefCounted

static func ignore_pointer(root: Control) -> void:
	if root == null:
		return
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

static func box(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

static func apply_to(root: Control) -> void:
	if root is MinecraftSlot:
		return
	if root is Button:
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var background: Color = Color("353b31") if state == "hover" else Color("242922")
			var border: Color = Color("a2a77f") if state in ["hover", "pressed"] else Color("53594a")
			root.add_theme_stylebox_override(state, box(background, border))
		root.add_theme_font_size_override("font_size", 13)
		root.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if root.tooltip_text.is_empty():
			root.tooltip_text = root.text
	if root is Label and root.get_theme_font_size("font_size") < 12:
		root.add_theme_font_size_override("font_size", 12)
	for child: Node in root.get_children():
		if child is Control:
			apply_to(child)
