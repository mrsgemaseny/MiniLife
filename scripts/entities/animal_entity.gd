class_name AnimalEntity
extends CharacterBody2D

# Represents domestic, wild, and pack animals (Cow, Sheep, Chicken, Donkey, Horse, Deer, Hare, Boar, Bear, Dog, Cat)
# Full adherence to ANIMALS_AND_FAUNA.md: non-lethal gathering, zero clutter, single meat & leather pool.

enum State { IDLE, WANDER, GRAZING, SLEEPING, FLEE, ATTACK }

@export var animal_type: String = "cow"
@export var display_name: String = "Animal"
@export var move_speed: float = 45.0
@export var stats: StatsComponent
@export var pack_inventory: InventoryComponent
@export var has_pack: bool = false

var spawn_uid: String = ""
var spawn_chunk: Vector2i = Vector2i.ZERO
var _threat: Node2D = null
var _attack_timer: float = 0.0

var current_state: State = State.IDLE
var is_permanently_dead: bool = false
var last_harvest_day: int = -1
var is_sheared: bool = false

var _state_timer: float = 2.0
var _wander_dir: Vector2 = Vector2.ZERO
var _target_velocity: Vector2 = Vector2.ZERO
var _egg_timer: float = 120.0

# Animation parameters (Walking, Grazing, Sleeping)
var _walk_phase: float = 0.0
var _walk_blend: float = 0.0
var _facing_left: bool = false
var _eat_timer: float = 0.0
var _eat_duration: float = 4.0
var _sleep_breath_phase: float = 0.0
var _zzz_timer: float = 0.0
var _zzz_particles: Array[Dictionary] = []
var _grass_particles: Array[Dictionary] = []

func _ready() -> void:
	y_sort_enabled = true
	add_to_group("animal")
	add_to_group("animals")
	add_to_group("fauna")
	add_to_group("combatant")
	add_to_group("interactable")

	if stats == null:
		stats = StatsComponent.new()

	_init_animal_type()
	queue_redraw()

func _init_animal_type() -> void:
	match animal_type:
		"cow":
			display_name = "Cow"
			stats.set_max("health", 80.0)
			stats.health = 80.0
			move_speed = 36.0
		"sheep":
			display_name = "Sheep"
			stats.set_max("health", 45.0)
			stats.health = 45.0
			move_speed = 40.0
		"pig":
			display_name = "Domestic Pig"
			stats.set_max("health", 70.0)
			stats.health = 70.0
			move_speed = 42.0
		"chicken":
			display_name = "Chicken"
			stats.set_max("health", 20.0)
			stats.health = 20.0
			move_speed = 50.0
		"donkey":
			display_name = "Pack Donkey" if has_pack else "Donkey"
			stats.set_max("health", 100.0)
			stats.health = 100.0
			move_speed = 55.0
			if has_pack:
				if pack_inventory == null:
					pack_inventory = InventoryComponent.new()
					pack_inventory.max_slots = 12
					pack_inventory.ensure_slots_capacity()
			else:
				pack_inventory = null
		"horse":
			display_name = "Riding Horse"
			stats.set_max("health", 120.0)
			stats.health = 120.0
			move_speed = 110.0
		"deer":
			display_name = "Wild Deer"
			stats.set_max("health", 50.0)
			stats.health = 50.0
			move_speed = 92.0
		"moose":
			display_name = "Forest Moose"
			stats.set_max("health", 180.0)
			stats.health = 180.0
			move_speed = 88.0
		"hare":
			display_name = "Wild Hare"
			stats.set_max("health", 18.0)
			stats.health = 18.0
			move_speed = 96.0
		"boar":
			display_name = "Wild Boar"
			stats.set_max("health", 90.0)
			stats.health = 90.0
			move_speed = 80.0
		"bear":
			display_name = "Forest Bear"
			stats.set_max("health", 220.0)
			stats.health = 220.0
			move_speed = 65.0
		"wolf":
			display_name = "Timber Wolf"
			stats.set_max("health", 65.0)
			stats.health = 65.0
			move_speed = 95.0
		"direwolf":
			display_name = "Warg"
			stats.set_max("health", 120.0)
			stats.health = 120.0
			move_speed = 100.0
		"fox":
			display_name = "Red Fox"
			stats.set_max("health", 35.0)
			stats.health = 35.0
			move_speed = 85.0
		"dog":
			display_name = "Village Dog"
			stats.set_max("health", 60.0)
			stats.health = 60.0
			move_speed = 70.0
		"cat":
			display_name = "Tavern Cat"
			stats.set_max("health", 25.0)
			stats.health = 25.0
			move_speed = 65.0
		"spider":
			display_name = "Megaspider"
			stats.set_max("health", 90.0)
			stats.health = 90.0
			move_speed = 75.0
		"fish":
			display_name = "River Fish"
			stats.set_max("health", 15.0)
			stats.health = 15.0
			move_speed = 40.0
		_:
			display_name = animal_type.capitalize()
			stats.set_max("health", 50.0)
			stats.health = 50.0

func _physics_process(delta: float) -> void:
	if is_permanently_dead or GameManager.is_paused():
		return

	# Chicken egg laying
	if animal_type == "chicken":
		_egg_timer -= delta
		if _egg_timer <= 0.0:
			_egg_timer = randf_range(90.0, 180.0)
			_lay_egg()

	# Day/Night sleep transitions
	var is_night: bool = GameManager.is_night()
	if is_night and current_state not in [State.SLEEPING, State.FLEE, State.ATTACK]:
		current_state = State.SLEEPING
		_target_velocity = Vector2.ZERO
		_zzz_timer = randf_range(0.2, 0.8)
	elif not is_night and current_state == State.SLEEPING:
		current_state = State.IDLE
		_state_timer = randf_range(1.5, 3.5)
		_zzz_particles.clear()

	# Wool regrowth check for sheep
	if animal_type == "sheep" and is_sheared:
		if GameManager.get_day() > last_harvest_day:
			is_sheared = false
			queue_redraw()

	_state_timer -= delta
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if current_state == State.ATTACK and is_instance_valid(_threat):
		var distance: float = global_position.distance_to(_threat.global_position)
		if distance > 260.0:
			current_state = State.IDLE
		elif distance > 28.0:
			velocity = global_position.direction_to(_threat.global_position) * move_speed
			move_and_slide()
		elif _attack_timer <= 0.0:
			_attack_timer = 1.4
			SignalBus.damage_requested.emit(_threat, 22.0 if animal_type == "bear" else 12.0, "physical", self)
		queue_redraw()
		return

	match current_state:
		State.IDLE:
			_target_velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				var roll: float = randf()
				if roll < 0.45:
					# Start grazing / eating
					current_state = State.GRAZING
					_eat_timer = 0.0
					_eat_duration = randf_range(3.0, 6.0)
					_state_timer = _eat_duration
				else:
					# Start wandering
					var angle: float = randf() * TAU
					_wander_dir = Vector2(cos(angle), sin(angle) * 0.5).normalized()
					_state_timer = randf_range(2.5, 5.0)
					current_state = State.WANDER

		State.WANDER:
			_target_velocity = _wander_dir * move_speed
			if _state_timer <= 0.0:
				_target_velocity = Vector2.ZERO
				_state_timer = randf_range(2.0, 4.0)
				current_state = State.IDLE

		State.GRAZING:
			_target_velocity = Vector2.ZERO
			_eat_timer += delta
			# Occasionally emit tiny grass chew particle
			if fmod(_eat_timer, 0.6) < delta * 1.5 and randf() < 0.5:
				_spawn_grass_particle()
			if _state_timer <= 0.0:
				current_state = State.IDLE
				_state_timer = randf_range(1.5, 3.5)

		State.SLEEPING:
			_target_velocity = Vector2.ZERO
			_sleep_breath_phase += delta * 2.2
			_zzz_timer -= delta
			if _zzz_timer <= 0.0:
				_zzz_timer = randf_range(1.2, 1.8)
				_spawn_zzz_particle()

			# Gentle wake-up if running player comes right next to sleeping wild animal
			var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
			if player != null and is_instance_valid(player):
				var p_dist: float = global_position.distance_to(player.global_position)
				if p_dist < 26.0 and animal_type in ["deer", "hare", "boar", "bear"]:
					current_state = State.FLEE
					_state_timer = 4.0
					_zzz_particles.clear()

		State.FLEE:
			var threat: Node2D = get_tree().get_first_node_in_group("player") as Node2D
			if threat != null and is_instance_valid(threat):
				var away: Vector2 = (global_position - threat.global_position).normalized()
				_target_velocity = away * (move_speed * 1.55)
				if global_position.distance_to(threat.global_position) > 280.0 or _state_timer <= 0.0:
					current_state = State.IDLE
					_state_timer = randf_range(2.0, 4.0)
			else:
				current_state = State.IDLE

	# Smooth movement integration
	velocity = velocity.lerp(_target_velocity, clampf(delta * 6.5, 0.0, 1.0))
	if velocity.length_squared() > 1.0:
		move_and_slide()

	# Facing orientation and walking animation
	var cur_speed: float = velocity.length()
	if abs(velocity.x) > 1.5:
		_facing_left = (velocity.x < 0.0)

	_walk_blend = lerpf(_walk_blend, 1.0 if cur_speed > 3.0 else 0.0, delta * 7.0)
	if cur_speed > 3.0:
		_walk_phase += cur_speed * delta * 0.16

	# Update active particle lifecycles
	_update_particles(delta)
	queue_redraw()

func _spawn_zzz_particle() -> void:
	var head_y: float = -18.0 if animal_type != "chicken" and animal_type != "hare" else -11.0
	_zzz_particles.append({
		"pos": Vector2(randf_range(-3.0, 3.0), head_y),
		"life": 1.7,
		"max_life": 1.7,
		"size": 5.5 if randf() < 0.6 else 7.5,
		"sway": randf() * TAU
	})

func _spawn_grass_particle() -> void:
	var snout_x: float = -12.0 if _facing_left else 12.0
	_grass_particles.append({
		"pos": Vector2(snout_x + randf_range(-2.0, 2.0), -2.0),
		"vel": Vector2(randf_range(-6.0, 6.0), randf_range(-10.0, -3.0)),
		"life": 0.65,
		"color": Color(0.36, 0.65, 0.28, 0.9)
	})

func _update_particles(delta: float) -> void:
	# Advance Zzz floaters
	var kept_zzz: Array[Dictionary] = []
	for p in _zzz_particles:
		p["life"] -= delta
		p["pos"].y -= 13.0 * delta
		p["pos"].x += sin(float(p["life"]) * 4.0 + float(p["sway"])) * 7.0 * delta
		if float(p["life"]) > 0.0:
			kept_zzz.append(p)
	_zzz_particles = kept_zzz

	# Advance grass chew flecks
	var kept_grass: Array[Dictionary] = []
	for gp in _grass_particles:
		gp["life"] -= delta
		gp["pos"] += gp["vel"] * delta
		gp["vel"].y += 35.0 * delta # Gravity
		if float(gp["life"]) > 0.0:
			kept_grass.append(gp)
	_grass_particles = kept_grass

func _lay_egg() -> void:
	var bag: LootBag = LootBag.new()
	bag.items = [{"item_id": "egg", "count": 1}]
	bag.global_position = global_position
	if get_parent() != null:
		get_parent().add_child(bag)

func _equip_pack_saddle() -> void:
	has_pack = true
	display_name = "Pack Donkey"
	if pack_inventory == null:
		pack_inventory = InventoryComponent.new()
		pack_inventory.max_slots = 12
		pack_inventory.ensure_slots_capacity()
	queue_redraw()

func interact(interactor: Node) -> void:
	if is_permanently_dead:
		return
	var player_inv: InventoryComponent = interactor.get("inventory") as InventoryComponent
	if player_inv == null:
		return

	var current_day: int = GameManager.get_day()

	match animal_type:
		"cow":
			# Milking requires an empty bottle
			if last_harvest_day == current_day:
				SignalBus.notification_posted.emit("This cow has already been milked today.")
				return
			if player_inv.has_item("empty_bottle", 1):
				if not player_inv.can_fit_item("milk", 1) and player_inv.get_item_count("empty_bottle") > 1:
					return
				player_inv.remove_item("empty_bottle", 1)
				player_inv.add_item("milk", 1)
				last_harvest_day = current_day
				SignalBus.notification_posted.emit("Milked cow into bottle (+1 Fresh Milk).")
			else:
				SignalBus.notification_posted.emit("Need an empty bottle to milk the cow.")
		"sheep":
			# Shearing requires shears
			var has_shears: bool = player_inv.has_item("shears", 1)
			if not has_shears and "equipment" in interactor and interactor.get("equipment") != null:
				var peq: EquipmentComponent = interactor.get("equipment") as EquipmentComponent
				if peq != null and peq.get_item_id("weapon") == "shears":
					has_shears = true

			if not has_shears:
				SignalBus.notification_posted.emit("Need Shears to shear the sheep's wool.")
				return

			if last_harvest_day == current_day or is_sheared:
				SignalBus.notification_posted.emit("Sheep has already been sheared today.")
				return

			if not player_inv.can_fit_item("wool", 2):
				return
			last_harvest_day = current_day
			is_sheared = true
			player_inv.add_item("wool", 2)
			SignalBus.notification_posted.emit("Sheared sheep (+2 Sheep Wool).")
			queue_redraw()
		"chicken":
			if last_harvest_day == current_day or not player_inv.can_fit_item("egg", 1):
				return
			last_harvest_day = current_day
			player_inv.add_item("egg", 1)
			SignalBus.notification_posted.emit("Gathered fresh egg (+1 Egg).")
		"donkey":
			if not has_pack:
				# Wild donkey: player must equip pack saddle or suitable materials first
				if player_inv.has_item("pack_saddle", 1):
					player_inv.remove_item("pack_saddle", 1)
					_equip_pack_saddle()
					SignalBus.notification_posted.emit("Equipped Pack Saddle on donkey (+12 storage slots).")
				elif player_inv.has_item("treated_leather", 2):
					player_inv.remove_item("treated_leather", 2)
					_equip_pack_saddle()
					SignalBus.notification_posted.emit("Equipped Treated Leather pack bags on donkey (+12 storage slots).")
				elif player_inv.has_item("tanned_leather", 1):
					player_inv.remove_item("tanned_leather", 1)
					_equip_pack_saddle()
					SignalBus.notification_posted.emit("Equipped Tanned Leather pack bags on donkey (+12 storage slots).")
				elif player_inv.has_item("cloth", 2) and player_inv.has_item("wood", 2):
					player_inv.remove_item("cloth", 2)
					player_inv.remove_item("wood", 2)
					_equip_pack_saddle()
					SignalBus.notification_posted.emit("Crafted pack harness from Cloth and Wood (+12 storage slots).")
				else:
					SignalBus.notification_posted.emit("Wild Donkey. Needs Pack Saddle, Treated Leather (2x), or Cloth (2x) + Wood (2x) to equip bags.")
				return

			# Open donkey pack storage (only when equipped)
			if pack_inventory == null:
				pack_inventory = InventoryComponent.new()
				pack_inventory.max_slots = 12
				pack_inventory.ensure_slots_capacity()

			SignalBus.notification_posted.emit("Opening pack donkey storage (+12 slots).")
			var player_tile: Vector2i = Config.iso_to_world(global_position)
			var smgr: StorageManager = null
			if BuildingSystem.instance != null:
				smgr = BuildingSystem.instance.get_storage_manager()
			if smgr != null:
				smgr.set_container_title(player_tile, "Pack Donkey Storage")
				var smgr_inv: InventoryComponent = smgr.get_or_create_container(player_tile)
				smgr_inv.max_slots = 12
				smgr_inv.ensure_slots_capacity()
				for i in range(mini(pack_inventory.slots.size(), smgr_inv.slots.size())):
					if not pack_inventory.slots[i].is_empty() and smgr_inv.slots[i].is_empty():
						smgr_inv.slots[i] = pack_inventory.slots[i].duplicate(true)
				pack_inventory = smgr_inv
			SignalBus.storage_container_opened.emit("donkey_pack", player_tile)
			SignalBus.chest_opened.emit("donkey_pack", player_tile)
		"dog":
			SignalBus.notification_posted.emit("The faithful dog barks joyfully.")
		"cat":
			SignalBus.notification_posted.emit("The tavern cat purrs comfortably.")
		_:
			SignalBus.notification_posted.emit("Interacted with %s." % display_name)

func take_damage(amount: float, _damage_type: String = "physical", source: Node = null) -> void:
	if is_permanently_dead:
		return
	stats.modify("health", -amount)
	_state_timer = 4.5
	_zzz_particles.clear()
	current_state = State.FLEE
	if source is Node2D and animal_type in ["bear", "boar", "moose"]:
		_threat = source as Node2D
		current_state = State.ATTACK
	queue_redraw()
	if stats.health <= 0.0:
		_handle_death(source)

func _handle_death(killer: Node) -> void:
	is_permanently_dead = true
	_spawn_slaughter_drops()
	var killer_id: String = "player" if (killer != null and killer.is_in_group("player")) else "world"
	SignalBus.entity_died.emit(self, killer_id)
	queue_free()

func _spawn_slaughter_drops() -> void:
	# Dogs and cats are strictly untouchable (0 drop per ANIMALS_AND_FAUNA.md)
	if animal_type in ["dog", "cat"]:
		return

	var drops: Array[Dictionary] = []
	match animal_type:
		"cow":
			drops.append({"item_id": "food_raw", "count": 3})
			drops.append({"item_id": "raw_leather", "count": 2})
		"sheep":
			drops.append({"item_id": "food_raw", "count": 2})
			if not is_sheared:
				drops.append({"item_id": "wool", "count": 1})
		"chicken":
			drops.append({"item_id": "food_raw", "count": 1})
			drops.append({"item_id": "feather", "count": 2})
		"donkey", "horse":
			drops.append({"item_id": "raw_leather", "count": 2})
		"deer":
			drops.append({"item_id": "food_raw", "count": 2})
			drops.append({"item_id": "raw_leather", "count": 1})
		"hare":
			drops.append({"item_id": "food_raw", "count": 1})
			drops.append({"item_id": "raw_leather", "count": 1})
		"boar":
			drops.append({"item_id": "food_raw", "count": 3})
			drops.append({"item_id": "raw_leather", "count": 2})
		"bear":
			drops.append({"item_id": "food_raw", "count": 4})
			drops.append({"item_id": "raw_leather", "count": 3})
		"pig":
			drops.append({"item_id": "food_raw", "count": 3})
			drops.append({"item_id": "raw_leather", "count": 2})
		"moose":
			drops.append({"item_id": "food_raw", "count": 5})
			drops.append({"item_id": "raw_leather", "count": 4})
		"fox":
			drops.append({"item_id": "food_raw", "count": 1})
			drops.append({"item_id": "raw_leather", "count": 2})
		"wolf", "direwolf":
			drops.append({"item_id": "food_raw", "count": 2})
			drops.append({"item_id": "raw_leather", "count": 3})
		"fish":
			drops.append({"item_id": "food_raw", "count": 1})
		_:
			drops.append({"item_id": "food_raw", "count": 1})

	var bag: CorpseEntity = CorpseEntity.new()
	bag.species = animal_type
	bag.items = drops
	bag.global_position = global_position
	if get_parent() != null:
		get_parent().add_child(bag)

static var _fauna_tex_cache: Dictionary = {}

static func _get_fauna_texture(type_id: String) -> Texture2D:
	if _fauna_tex_cache.has(type_id):
		return _fauna_tex_cache[type_id]
	var path: String = "res://assets/sprites/world/fauna/%s.png" % type_id
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var global_p: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(global_p):
			var img: Image = Image.load_from_file(global_p)
			if img != null:
				tex = ImageTexture.create_from_image(img)
	_fauna_tex_cache[type_id] = tex
	return tex


func _draw_vector_z(pos: Vector2, sz: float, col: Color) -> void:
	draw_line(pos, pos + Vector2(sz, 0.0), col, 1.4)
	draw_line(pos + Vector2(sz, 0.0), pos + Vector2(0.0, sz), col, 1.4)
	draw_line(pos + Vector2(0.0, sz), pos + Vector2(sz, sz), col, 1.4)

func _draw() -> void:
	AnimalRig.draw_animal(self, animal_type, _walk_phase, _walk_blend, -1.0 if _facing_left else 1.0, current_state == State.GRAZING, current_state == State.SLEEPING)
	var hovered: bool = get_local_mouse_position().distance_to(Vector2(0,-18)) < 28.0
	var injured: bool = stats.health < stats.max_health
	if injured or hovered or current_state in [State.FLEE, State.ATTACK]:
		var ratio: float = clampf(stats.health / maxf(1.0, stats.max_health), 0.0, 1.0)
		draw_rect(Rect2(-20,-46,40,5), Color("28251f"))
		draw_rect(Rect2(-19,-45,38*ratio,3), Color("80a760") if ratio > 0.4 else Color("b96e50"))
	if hovered:
		var state: String = ["Idle", "Walking", "Grazing", "Sleeping", "Fleeing", "Attacking"][int(current_state)]
		var text: String = "%s  %d/%d HP" % [display_name, ceili(stats.health), ceili(stats.max_health)]
		var font: Font = ThemeDB.fallback_font
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string_outline(font,Vector2(-width/2,-66),text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,3,Color("191b17"))
		draw_string(font,Vector2(-width/2,-66),text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ece5d4"))
		draw_string(font,Vector2(-20,-52),state,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("d9cfb7"))
	if has_pack:
		draw_rect(Rect2(-7,-20,10,8),Color("59422b"))


func is_alive() -> bool:
	return not is_permanently_dead and stats != null and stats.health > 0.0

func spawn_state() -> Dictionary:
	return {"position": [global_position.x, global_position.y], "health": stats.health,
		"last_harvest_day": last_harvest_day, "is_sheared": is_sheared, "egg_timer": _egg_timer,
		"has_pack": has_pack, "pack": pack_inventory.to_dict() if pack_inventory != null else {}}

func restore_spawn_state(state: Dictionary) -> void:
	var pos: Array = state.get("position", [global_position.x, global_position.y])
	global_position = Vector2(float(pos[0]), float(pos[1]))
	stats.health = clampf(float(state.get("health", stats.health)), 0.0, stats.max_health)
	last_harvest_day = int(state.get("last_harvest_day", -1))
	is_sheared = bool(state.get("is_sheared", false))
	_egg_timer = float(state.get("egg_timer", 120.0))
	if bool(state.get("has_pack", false)) and animal_type == "donkey":
		_equip_pack_saddle()
	if pack_inventory != null:
		pack_inventory.from_dict(state.get("pack", {}))
