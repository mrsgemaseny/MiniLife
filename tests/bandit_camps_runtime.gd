extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var seed_value: int = Config.DEFAULT_WORLD_SEED
	var plan: Dictionary = PoiGenerator._build_bandit_plan(seed_value)
	assert(plan.size() == 12)
	var kinds: Dictionary = {}
	for chunk: Vector2i in plan:
		var info: Dictionary = plan[chunk]
		kinds[info["poi_id"]] = true
		assert(info == PoiGenerator.get_bandit_camp_for_chunk(seed_value, chunk))
		assert(DataRegistry.get_poi(info["poi_id"]).has("camp_tier"))
	assert(kinds.size() == 4)
	var all_bandits: Dictionary = {}
	for poi_id: String in PoiGenerator.BANDIT_IDS:
		for id: String in DataRegistry.get_poi(poi_id).get("enemy_pool", []):
			all_bandits[id] = true
	all_bandits["bandit_axe_chief"] = true
	assert(all_bandits.size() == 13)
	for id: String in all_bandits:
		var def: Dictionary = DataRegistry.get_enemy(id)
		assert(not def.is_empty() and int(def.get("bandit_tier", 0)) > 0)
		var sprite_name: String = str(def.get("sprite", id.trim_prefix("bandit_")))
		var sprite: Texture2D = load("res://assets/sprites/enemies/bandits/" + sprite_name + ".png") as Texture2D
		assert(sprite != null and sprite.get_width() <= 256)
		assert(sprite.get_image().get_pixel(0, 0).a < 0.1)
	var unique_chests: Dictionary = {}
	for i: int in range(40):
		for tier: int in range(1, 5):
			var roll: Dictionary = BanditLoot.roll(tier, i * 17 + 90, true)
			assert(roll == BanditLoot.roll(tier, i * 17 + 90, true))
			assert(roll["items"].size() >= 4 + tier)
			assert(roll["gold"] > 0)
			for id: String in roll["items"]:
				assert(not DataRegistry.get_item(id).is_empty())
			unique_chests[str(roll["items"])] = true
	assert(unique_chests.size() > 80)
	for id: String in ["bandit_scout", "bandit_raider", "bandit_veteran", "bandit_chief"]:
		var def: Dictionary = DataRegistry.get_enemy(id)
		assert(def.has("bandit_tier") and def.has("ai_profile"))
		var drops: Dictionary = BanditLoot.roll(int(def["bandit_tier"]), hash(id))
		assert(BanditLoot.as_drops(drops).size() >= 3)
	var manager := StorageManager.new()
	var chest := Vector2i(10, 10)
	var first: Dictionary = BanditLoot.roll(4, 435, true)
	manager.populate_chest_loot(chest, "Chief's Camp", first["gold"], first["items"])
	var saved: Dictionary = manager.to_dict()
	var restored := StorageManager.new()
	restored.from_dict(saved)
	restored.populate_chest_loot(chest, "Rerolled", 0, {"stone": 1})
	assert(restored.to_dict() == saved)
	var buildings := BuildingSystem.new()
	add_child(buildings)
	var world: Node2D = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	var site_chunk: Vector2i = plan.keys()[0]
	var site: Dictionary = plan[site_chunk]
	world._load_chunk(site_chunk)
	assert(world._loaded_chunks.has(site_chunk))
	var alive: int = 0
	for entity: Node in world._spawned_entities_by_chunk.get(site_chunk, []):
		if entity is EnemyBase and entity.faction_id == "bandits":
			alive += 1
	assert(alive >= 3)
	var site_chest: Vector2i = site["tile_pos"] + Vector2i(5, 2)
	var site_storage: StorageManager = BuildingSystem.instance.get_storage_manager()
	assert(site_storage.get_container_gold(site_chest) > 0)
	assert(not site_storage.get_or_create_container(site_chest).to_dict().is_empty())
	var spawned_ids: Dictionary = {}
	for chunk: Vector2i in plan:
		if not world._loaded_chunks.has(chunk):
			world._load_chunk(chunk)
		for entity: Node in world._spawned_entities_by_chunk.get(chunk, []):
			if entity is EnemyBase and entity.faction_id == "bandits":
				spawned_ids[entity.enemy_id] = true
	assert(spawned_ids.size() == 13)
	var chief_variants: Dictionary = {}
	for info: Dictionary in plan.values():
		if info["poi_id"] == "bandit_chief_camp":
			chief_variants[int(info["camp_variant"])] = true
	assert(chief_variants.size() == 2)
	print("BANDIT_CAMPS_PASS: sites, ranks, deterministic varied loot, valid items, chest persistence")
	get_tree().quit()
