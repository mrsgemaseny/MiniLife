extends Node2D

const Surface = preload("res://scripts/alife/settlements/city_street_plan.gd").Surface
const Materials = preload("res://scripts/systems/world/settlement_materials.gd")
const PROP_ROOT: String = "res://assets/sprites/expansion/settlements_2026_11_04/regions/"
const STREET_MATERIALS: Array[int] = [
	Materials.Kind.GRAVEL, Materials.Kind.COBBLE, Materials.Kind.FLAGSTONE, Materials.Kind.FLAGSTONE,
]

var _paving: Dictionary = {}
var _props: Dictionary = {}
var _fog_state: Callable
var _forum_inlay: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	z_index = -6
	SignalBus.fog_batch_updated.connect(_on_fog_changed)


func configure(info: Dictionary, fog_state: Callable) -> void:
	var street_plan: Dictionary = info.get("streets", {})
	_paving = street_plan.get("paving", {})
	_forum_inlay = street_plan.get("forum_inlay", Vector2i(-1, -1))
	_fog_state = fog_state
	for prop: Sprite2D in _props.values():
		prop.queue_free()
	_props.clear()
	var placements: Dictionary = street_plan.get("props", {})
	for tile: Vector2i in placements:
		var texture: Texture2D = load(PROP_ROOT + placements[tile] + ".tres") as Texture2D
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		var large: bool = placements[tile] in ["market_stall", "cargo_handcart"]
		sprite.scale = Vector2.ONE * (58.0 if large else 33.0) / maxf(texture.get_width(), texture.get_height())
		sprite.offset.y = -texture.get_height() * 0.37
		sprite.position = Config.world_to_iso(tile)
		sprite.z_as_relative = false
		add_child(sprite)
		_props[tile] = sprite
	_update_props()
	queue_redraw()


func _on_fog_changed(changes: Array) -> void:
	for change: Dictionary in changes:
		var tile: Vector2i = change["pos"]
		if _paving.has(tile) or _props.has(tile):
			_update_props()
			queue_redraw()
			return


func _update_props() -> void:
	for tile: Vector2i in _props:
		var fog: int = _fog_state.call(tile)
		_props[tile].visible = fog != 0
		_props[tile].modulate = Color("c0b3a0") if fog == 2 else Color("68646b")


func _draw() -> void:
	for tile: Vector2i in _paving:
		var fog: int = _fog_state.call(tile)
		if fog != 0:
			_draw_paving(tile, int(_paving[tile]), fog == 1)


func _draw_paving(tile: Vector2i, surface: int, visited: bool) -> void:
	var tint: Color = Color("72717c") if visited else Color.WHITE
	var material: int = Materials.Kind.MOSAIC if tile == _forum_inlay else STREET_MATERIALS[surface]
	var period: int = 2 if surface in [Surface.FLAGSTONE, Surface.FORUM] else 1
	if tile == _forum_inlay:
		period = 1
		tint *= Color("aaa49a")
	elif surface == Surface.FORUM:
		tint *= Color("ded8cb")
	Materials.draw_ground(self, tile, material, period, tint)
