class_name PoiDecoration
extends Node2D

const ROOT: String = "res://assets/sprites/expansion/settlements_2026_11_04/regions/"
const TRADE: Array[String] = ["cargo_crates", "sealed_barrels", "grain_sacks", "cloth_bolts", "trader_chest", "apple_basket", "bread_basket", "fish_tub", "cargo_handcart", "tent_bundle", "travel_packs", "balance_scales", "bronze_stack", "iron_stack", "plank_bundle", "wool_bales"]
const CAMP: Array[String] = ["expedition_tent", "fur_bedroll", "cooking_tripod", "meat_drying_rack", "waterskin_cup", "firewood_stack", "chopping_block", "fishing_kit", "medicine_chest", "direction_signpost", "map_compass", "lean_to", "herb_basket", "travel_toolkit", "adventurer_chest"]
const BANDIT_CAMP: Array[String] = ["expedition_tent", "fur_bedroll", "cooking_tripod", "meat_drying_rack", "firewood_stack", "chopping_block", "lean_to", "adventurer_chest", "broken_cart", "discarded_armor", "broken_weapon_rack", "cargo_crates", "sealed_barrels"]
const RUINS: Array[String] = ["broken_column", "stone_chest", "broken_cart", "broken_pottery", "old_signpost", "standing_stone", "discarded_armor", "old_vault", "broken_weapon_rack", "broken_bridge"]
const FARM: Array[String] = ["feeding_trough", "hay_bale", "wheat_sheaves", "beehive", "rain_barrel", "grain_quern", "spinning_wheel", "loom", "linen_rack", "kindling_block", "produce_basket", "seedling_pots", "wattle_fence", "farm_wheelbarrow"]
const WORKSHOP: Array[String] = ["anvil_stump", "forge_bellows", "hot_crucible", "charcoal_bucket", "smith_tool_rack", "stitching_frame", "tanning_rack", "sewing_basket", "masonry_blocks", "herb_mortar", "herb_drying_rack", "medicine_jars", "carpenter_chest", "sawhorse_plank", "pottery_set", "cauldron_ladle"]

var _props: Dictionary = {}

func _ready() -> void:
	y_sort_enabled = true
	SignalBus.fog_updated.connect(_on_fog_updated)
	SignalBus.fog_batch_updated.connect(_on_fog_batch_updated)

func populate(seed_value: int, info: Dictionary, passable: Callable, fog_state: Callable) -> void:
	if info.is_empty() or not _props.is_empty():
		return
	var anchor: Vector2i = info.get("origin", info.get("tile_pos", Vector2i.ZERO))
	var size: int = int(info.get("size", 5)) if info.has("settlement_id") else 5
	if bool(info.get("is_ruin", false)):
		var dims: Array = info.get("ruin_data", {}).get("size", [5, 5])
		size = mini(int(dims[0]), int(dims[1]))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ (anchor.x * 73856093) ^ (anchor.y * 19349663)
	var pool: Array[String] = CAMP.duplicate()
	var id: String = str(info.get("poi_id", ""))
	if id == "abandoned_camp" or id in PoiGenerator.BANDIT_IDS:
		size = 7
		pool = BANDIT_CAMP.duplicate()
	if info.has("settlement_id") or id == "merchant_outpost":
		pool = TRADE.duplicate()
		pool.append_array(FARM)
		pool.append_array(WORKSHOP)
	elif bool(info.get("is_ruin", false)) or id in ["ruins", "cave", "dungeon"]:
		pool = RUINS.duplicate()
	var occupied: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("structures"):
		if node is Node2D:
			occupied[Config.iso_to_world(node.global_position)] = true
	# Small decorative props only: existing buildings, doors and functional stations remain authoritative.
	var wanted: int = 10 if info.has("settlement_id") else (8 if id == "abandoned_camp" or id in PoiGenerator.BANDIT_IDS else 5)
	for attempt: int in range(100):
		if _props.size() >= wanted:
			break
		var tile := anchor + Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		if _props.has(tile) or occupied.has(tile) or not bool(passable.call(tile)):
			continue
		# Keep the central route and space around doors clear of visual clutter.
		if tile.x == anchor.x + size / 2 or tile.y == anchor.y + size / 2:
			continue
		var asset_id: String = pool[rng.randi_range(0, pool.size() - 1)]
		var texture: Texture2D = load(ROOT + asset_id + ".tres")
		if texture == null:
			continue
		var prop := Sprite2D.new()
		prop.name = asset_id + "_%d_%d" % [tile.x, tile.y]
		prop.texture = texture
		prop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var scale_factor: float = minf(38.0 / texture.get_width(), 42.0 / texture.get_height())
		prop.scale = Vector2.ONE * scale_factor
		prop.offset = Vector2(0.0, -texture.get_height() * 0.5)
		prop.position = Config.world_to_iso(tile)
		prop.set_meta("decoration_id", asset_id)
		add_child(prop)
		_props[tile] = prop
		_on_fog_updated(tile, int(fog_state.call(tile)))

func _on_fog_updated(tile: Vector2i, state: int) -> void:
	if not _props.has(tile):
		return
	var prop: Sprite2D = _props[tile]
	prop.visible = state > 0
	prop.modulate = Color(0.52, 0.52, 0.58) if state == 1 else Color.WHITE

func _on_fog_batch_updated(changes: Array) -> void:
	for change: Dictionary in changes:
		_on_fog_updated(change.get("pos", Vector2i.ZERO), int(change.get("state", 0)))
