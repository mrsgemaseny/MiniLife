extends Node

const VALDEN: Vector2i = Vector2i(7, 14)
const NO_TILE: Vector2i = Vector2i(-1, -1)
const SEEDS: Array[int] = [12345, 42819, 98765]
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var representatives: Dictionary[String, Vector2i] = _check_catalog()
	if _check(representatives.size() == 7, "The catalog does not cover all WorldStudio settlement types"):
		var scene: Node = load("res://scenes/main.tscn").instantiate()
		add_child(scene)
		var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
		var slot: String = "__settlement_catalog_" + Crypto.new().generate_random_bytes(16).hex_encode()
		GameManager.start_new_game(SEEDS[0], slot)
		scene.get_node("UILayer/MainMenu").close_menu()
		await _check_streaming(scene, save_system, slot, representatives)
		save_system.delete_slot(slot)
	if failures == 0:
		print("SETTLEMENT_BASE_CATALOG_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check_catalog() -> Dictionary[String, Vector2i]:
	var sites: Dictionary[Vector2i, Dictionary] = WorldData.political_settlements()
	var bases: Dictionary[Vector2i, SettlementBase] = WorldData.settlement_bases()
	var representatives: Dictionary[String, Vector2i] = {}
	var layouts: Dictionary = {}
	var checked_layouts: Dictionary = {}
	_check(bases.size() == sites.size(), "One or more authored sites have no PixelBuilder base")
	for seed_value: int in SEEDS:
		var terrain: TerrainGenerator = TerrainGenerator.new(seed_value)
		var legacy: TerrainGenerator = TerrainGenerator.new(seed_value, TerrainGenerator.AUTHORED_POLITICS_GENERATOR_VERSION)
		for site: Dictionary in terrain.get_graph().settlement_sites:
			var cell: Vector2i = site["cell"]
			var tile: Vector2i = site["tile"]
			var type: String = sites[cell]["type"]
			var base: SettlementBase = bases.get(cell)
			if not _check(base != null, "No base in cell %s" % str(cell)):
				continue
			if cell == VALDEN:
				_check(base.first_generator_version == 4 and base.anchor == Vector2i(527, 512) \
					and terrain.get_settlement_block(tile) == legacy.get_settlement_block(tile), "The original Valden assignment changed")
				continue
			var origin: Vector2i = tile - base.anchor
			var world_bounds: Rect2i = Rect2i(origin + base.bounds.position, base.bounds.size)
			_check(GlobalLandscapeMap.cell_bounds(cell).encloses(world_bounds) and terrain.settlement_base_entry(cell) == tile \
				and terrain.is_dry_land(tile) and not terrain.get_settlement_block(tile).is_empty() \
				and legacy.get_settlement_block(tile).is_empty(), "Wrong, blocked, or unversioned placement in cell %s" % str(cell))
			if not checked_layouts.has(base):
				_check(_has_open_approach(base), "An authored entrance is cut off from the exterior")
				checked_layouts[base] = true
			if not layouts.has(type):
				layouts[type] = {}
			layouts[type][base] = true
			if not representatives.has(type):
				representatives[type] = cell
	_check(layouts.get("castle", {}).size() > 1 and layouts.get("city", {}).size() > 1 \
		and layouts.get("village", {}).size() > 1, "Settlements lost their authored layout variation")
	_check(layouts.get("village_2", {}).size() == 4, "Farmsteads do not use all four orientations")
	return representatives


func _has_open_approach(base: SettlementBase) -> bool:
	var pending: Array[Vector2i] = [base.anchor]
	var visited: Dictionary[Vector2i, bool] = {base.anchor: true}
	var index: int = 0
	while index < pending.size():
		var tile: Vector2i = pending[index]
		index += 1
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = tile + step
			if not base.bounds.has_point(next):
				return true
			if visited.has(next):
				continue
			visited[next] = true
			var block: String = base.block_at(next)
			if block != "door" and SettlementBase.is_walkable(block):
				pending.append(next)
	return false


func _check_streaming(scene: Node, save_system: SaveSystem, slot: String, representatives: Dictionary[String, Vector2i]) -> void:
	var map: GlobalMapUI = scene.get_node("UILayer/GlobalMapUI")
	var world: WorldSystem = scene.get_node("World")
	var terrain: TerrainGenerator = world.get_terrain()
	map.open_panel()
	for type: String in representatives:
		var cell: Vector2i = representatives[type]
		_check(map._find_landing_tile(cell) == terrain.settlement_base_entry(cell), "Map did not select the open entrance for " + type)
	var city: Vector2i = representatives["city"]
	map._selected_region = city
	map._enter_selected_chunk()
	await get_tree().process_frame
	var entry: Vector2i = terrain.settlement_base_entry(city)
	if not _check(GameManager.get_player_tile() == entry, "Entering the city did not move the player to its entrance"):
		return
	var wall: Vector2i = _nearby_wall(terrain, entry)
	if not _check(wall != NO_TILE and not world.is_passable(wall), "The city has no solid authored wall near its entry"):
		return
	if not _check(await _wait_for_wall(wall), "The city wall did not stream as a structure"):
		return
	var chunk: Vector2i = Config.tile_to_chunk(wall)
	var delta: String = SaveSystem._chunk_file_path(slot, chunk)
	_check(save_system.save_slot(slot) and not FileAccess.file_exists(delta), "The city base appeared in an unchanged chunk delta")
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(WorldLayout.start_tile()))
	await get_tree().process_frame
	_check(not _has_wall(wall), "An authored wall remained loaded outside its chunk")
	if _check(save_system.load_slot(slot) and WorldSimulation.last_load_error.is_empty(), "The city save did not reload"):
		_check(await _wait_for_wall(wall) and not FileAccess.file_exists(delta), "The city wall did not regenerate from its base")


func _nearby_wall(terrain: TerrainGenerator, anchor: Vector2i) -> Vector2i:
	for radius: int in range(1, 23):
		for x: int in range(-radius, radius + 1):
			for y: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var tile: Vector2i = anchor + Vector2i(x, y)
				if SettlementBase.structure_for(terrain.get_settlement_block(tile)) in ["wall", "wood_wall"]:
					return tile
	return NO_TILE


func _wait_for_wall(tile: Vector2i) -> bool:
	var limit: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < limit and not _has_wall(tile):
		await get_tree().process_frame
	return _has_wall(tile)


func _has_wall(tile: Vector2i) -> bool:
	return get_tree().get_nodes_in_group(StructureEntity._wall_group(tile)).any(
		func(node: Node) -> bool: return node is StructureEntity and node.is_settlement_base and not node.is_queued_for_deletion())


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error(message)
	return condition
