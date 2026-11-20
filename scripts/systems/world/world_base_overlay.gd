class_name WorldBaseOverlay
extends RefCounted

const MAX_LOADED_BASES: int = 3
const TOKEN_TO_POINT_TYPE: Dictionary = {
	"settlement_castle": "castle",
	"settlement_city": "city",
	"settlement_fortress": "fortress",
	"settlement_village": "village",
	"settlement_village_2": "hamlet",
	"settlement_village_3": "city",
}
const SOLID_TOKENS: Array[String] = ["brick", "pillar", "stone_wall", "wood_wall", "water"]

var _seed: int = 0
var _enabled: bool = false
var _catalog: BaseTemplateCatalog = null
var _graph: WorldGraph = null
var _placements: Dictionary[Vector2i, Dictionary] = {}
var _empty_cells: Dictionary[Vector2i, bool] = {}
var _order: Array[Vector2i] = []


func setup(seed_value: int, generator_version: int) -> void:
	_seed = seed_value
	_enabled = generator_version >= 4
	_graph = WorldGraph.for_seed(seed_value) if _enabled else null
	_placements.clear()
	_empty_cells.clear()
	_order.clear()
	if _enabled and _catalog == null:
		_catalog = BaseTemplateCatalog.load_default()
		if _catalog == null:
			_enabled = false


func token_at(tile: Vector2i) -> String:
	if not _enabled or not WorldLayout.contains_tile(tile):
		return ""
	var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(tile)
	var placement: Dictionary = placement_for_cell(cell)
	if placement.is_empty():
		return ""
	var local: Vector2i = tile - cell * GlobalLandscapeMap.CELL_TILES - (placement["offset"] as Vector2i)
	return (placement["template"] as PackedBaseTemplate).block_at(local)


func placement_for_cell(cell: Vector2i) -> Dictionary:
	if not _enabled or _empty_cells.has(cell):
		return {}
	if _placements.has(cell):
		return _placements[cell]
	var site: Dictionary = _graph.site_for_cell(cell)
	var point_type: String = str(TOKEN_TO_POINT_TYPE.get(site.get("token", ""), ""))
	if point_type.is_empty():
		_empty_cells[cell] = true
		return {}
	var source: String = _catalog.choose(point_type, _seed, cell)
	if source.is_empty():
		_empty_cells[cell] = true
		return {}
	var template: PackedBaseTemplate = PackedBaseTemplate.load_from_source(source)
	if template == null:
		_empty_cells[cell] = true
		return {}
	var offset: Vector2i = (site["tile"] as Vector2i) - cell * GlobalLandscapeMap.CELL_TILES - Vector2i(500, 500)
	offset.x = clampi(offset.x, -template.bounds.position.x, 1000 - template.bounds.end.x)
	offset.y = clampi(offset.y, -template.bounds.position.y, 1000 - template.bounds.end.y)
	var placement: Dictionary = {"template": template, "offset": offset, "site": site}
	_placements[cell] = placement
	_order.append(cell)
	if _order.size() > MAX_LOADED_BASES:
		_placements.erase(_order.pop_front())
	return placement


static func is_solid(token: String) -> bool:
	return SOLID_TOKENS.has(token)
