class_name InteriorZone
extends Node2D

const ZONE_DEFS: Dictionary = {
	"collapsed_tower_depths": {
		"name": "Collapsed Tower Depths",
		"ruin_id": "collapsed_tower",
		"width": 7,
		"height": 7,
		"floor_type": "dark_flagstone",
		"entrance_offset": Vector2i(3, 6),
		"exit_offset": Vector2i(3, 6),
		"chests": [Vector2i(3, 2)],
		"traps": [Vector2i(2, 4), Vector2i(4, 4)],
		"boss_spawn": Vector2i(3, 3)
	},
	"underground_vault_interior": {
		"name": "Ancient Underground Vault",
		"ruin_id": "underground_vault",
		"width": 6,
		"height": 5,
		"floor_type": "iron_reinforced_tile",
		"entrance_offset": Vector2i(2, 4),
		"exit_offset": Vector2i(2, 4),
		"chests": [Vector2i(1, 1), Vector2i(4, 1)],
		"traps": [Vector2i(2, 2)],
		"boss_spawn": Vector2i(3, 2)
	},
	"village_hut_interior": {
		"name": "Abandoned Village Hut",
		"ruin_id": "old_village",
		"width": 5,
		"height": 5,
		"floor_type": "wooden_planks",
		"entrance_offset": Vector2i(2, 4),
		"exit_offset": Vector2i(2, 4),
		"chests": [Vector2i(3, 1)],
		"traps": [],
		"boss_spawn": Vector2i(-1, -1)
	}
}

var active_zone_id: String = ""
var active_zone_name: String = ""
var is_inside: bool = false
var _saved_world_tile: Vector2i = Vector2i.ZERO
var _interior_origin_tile: Vector2i = Vector2i(500, 500)
var _active_def: Dictionary = {}

func _ready() -> void:
	y_sort_enabled = true
	visible = false
	z_index = 5

func is_player_inside() -> bool:
	return is_inside

func get_current_room_info() -> Dictionary:
	if not is_inside or _active_def.is_empty():
		return {}
	return {
		"zone_id": active_zone_id,
		"zone_name": active_zone_name,
		"width": int(_active_def.get("width", 6)),
		"height": int(_active_def.get("height", 6)),
		"exit_offset": _active_def.get("exit_offset", Vector2i(2, 4)),
		"chests": _active_def.get("chests", []),
		"traps": _active_def.get("traps", []),
		"floor_type": str(_active_def.get("floor_type", "dark_flagstone"))
	}

func enter_zone(zone_id: String, outside_tile: Vector2i) -> bool:
	if not ZONE_DEFS.has(zone_id):
		return false
	_active_def = (ZONE_DEFS[zone_id] as Dictionary).duplicate(true)
	active_zone_id = zone_id
	active_zone_name = str(_active_def.get("name", zone_id))
	_saved_world_tile = outside_tile
	is_inside = true
	visible = true

	var exit_ofs: Vector2i = _active_def.get("exit_offset", Vector2i(2, 4))
	var interior_entry_tile: Vector2i = _interior_origin_tile + exit_ofs
	var interior_world_pos: Vector2 = Config.world_to_iso(interior_entry_tile)

	SignalBus.player_teleport_requested.emit(interior_world_pos)
	SignalBus.interior_entered.emit(active_zone_id, active_zone_name)
	queue_redraw()
	return true

func exit_zone() -> void:
	if not is_inside:
		return
	var exiting_id: String = active_zone_id
	is_inside = false
	visible = false
	active_zone_id = ""
	active_zone_name = ""

	var return_pos: Vector2 = Config.world_to_iso(_saved_world_tile + Vector2i(0, 1))
	SignalBus.player_teleport_requested.emit(return_pos)
	SignalBus.interior_exited.emit(exiting_id)
	queue_redraw()

func check_interaction(player_tile: Vector2i) -> void:
	if not is_inside or _active_def.is_empty():
		return
	var exit_tile: Vector2i = _interior_origin_tile + (_active_def.get("exit_offset", Vector2i(2, 4)) as Vector2i)
	if player_tile == exit_tile:
		exit_zone()

func _draw() -> void:
	if not is_inside or _active_def.is_empty():
		return

	var w: int = int(_active_def.get("width", 6))
	var h: int = int(_active_def.get("height", 6))
	var floor_type: String = str(_active_def.get("floor_type", "dark_flagstone"))
	var hw: float = float(Config.HALF_TILE.x)
	var hh: float = float(Config.HALF_TILE.y)

	var floor_col: Color = Color(0.18, 0.20, 0.24) if floor_type == "dark_flagstone" else (
		Color(0.24, 0.22, 0.20) if floor_type == "iron_reinforced_tile" else Color(0.36, 0.26, 0.17)
	)
	var wall_col: Color = Color(0.14, 0.15, 0.18)
	var wall_top_col: Color = Color(0.26, 0.28, 0.32)

	# Draw floor tiles inside room
	for ry in range(h):
		for rx in range(w):
			var tile: Vector2i = _interior_origin_tile + Vector2i(rx, ry)
			var center: Vector2 = Config.world_to_iso(tile)
			var top_pt: Vector2 = center + Vector2(0.0, -hh)
			var right_pt: Vector2 = center + Vector2(hw, 0.0)
			var bot_pt: Vector2 = center + Vector2(0.0, hh)
			var left_pt: Vector2 = center + Vector2(-hw, 0.0)
			var poly: PackedVector2Array = PackedVector2Array([top_pt, right_pt, bot_pt, left_pt])

			var is_wall: bool = (rx == 0 or rx == w - 1 or ry == 0 or ry == h - 1)
			var exit_ofs: Vector2i = _active_def.get("exit_offset", Vector2i(2, 4))
			if is_wall and Vector2i(rx, ry) == exit_ofs:
				is_wall = false

			if is_wall:
				# 3D Extruded Dungeon Wall
				var wall_h: float = 24.0
				var w_top: Vector2 = top_pt + Vector2(0.0, -wall_h)
				var w_right: Vector2 = right_pt + Vector2(0.0, -wall_h)
				var w_bot: Vector2 = bot_pt + Vector2(0.0, -wall_h)
				var w_left: Vector2 = left_pt + Vector2(0.0, -wall_h)

				# Wall front left & right facets
				var facet_l: PackedVector2Array = PackedVector2Array([left_pt, bot_pt, w_bot, w_left])
				var facet_r: PackedVector2Array = PackedVector2Array([bot_pt, right_pt, w_right, w_bot])
				draw_colored_polygon(facet_l, wall_col.darkened(0.2))
				draw_colored_polygon(facet_r, wall_col.darkened(0.35))
				draw_polyline(facet_l, Color(0.05, 0.06, 0.08), 1.2, true)
				draw_polyline(facet_r, Color(0.05, 0.06, 0.08), 1.2, true)

				var cap_poly: PackedVector2Array = PackedVector2Array([w_top, w_right, w_bot, w_left])
				draw_colored_polygon(cap_poly, wall_top_col)
				draw_polyline(cap_poly, Color(0.08, 0.09, 0.12), 1.2, true)
			else:
				var tcol: Color = floor_col
				if ((rx + ry) % 2) == 1:
					tcol = tcol.lightened(0.06)
				draw_colored_polygon(poly, tcol)
				draw_polyline(poly, Color(0.10, 0.12, 0.15, 0.65), 1.0, true)

	# Draw exit ladder / doorway marker
	var exit_pt: Vector2 = Config.world_to_iso(_interior_origin_tile + (_active_def.get("exit_offset", Vector2i(2, 4)) as Vector2i))
	draw_circle(exit_pt, 6.0, Color(0.85, 0.70, 0.25, 0.85))
	draw_arc(exit_pt, 8.5, 0.0, TAU, 16, Color(0.96, 0.88, 0.42, 0.90), 1.4)

	# Draw loot chests
	for cofs in _active_def.get("chests", []):
		var cpos: Vector2 = Config.world_to_iso(_interior_origin_tile + (cofs as Vector2i))
		draw_rect(Rect2(cpos.x - 7, cpos.y - 12, 14, 10), Color(0.42, 0.28, 0.16), true)
		draw_rect(Rect2(cpos.x - 7, cpos.y - 12, 14, 10), Color(0.82, 0.68, 0.32), false, 1.2)
		draw_circle(cpos + Vector2(0, -7), 1.5, Color(0.95, 0.85, 0.40))
