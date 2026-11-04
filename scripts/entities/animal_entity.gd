class_name AnimalEntity
extends CharacterBody2D

# Represents domestic, wild, and pack animals (Cow, Sheep, Chicken, Donkey, Horse, Deer, Hare, Boar, Bear, Dog, Cat)
# Full adherence to ANIMALS_AND_FAUNA.md: non-lethal gathering, zero clutter, single meat & leather pool.

enum State { IDLE, WANDER, GRAZING, SLEEPING, FLEE }

@export var animal_type: String = "cow"
@export var display_name: String = "Animal"
@export var move_speed: float = 45.0
@export var stats: StatsComponent
@export var pack_inventory: InventoryComponent
@export var has_pack: bool = false

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
	if is_night and current_state != State.SLEEPING and current_state != State.FLEE:
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
			if player_inv.has_item("empty_bottle", 1):
				player_inv.remove_item("empty_bottle", 1)
				player_inv.add_item("milk", 1)
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

			last_harvest_day = current_day
			is_sheared = true
			player_inv.add_item("wool", 2)
			SignalBus.notification_posted.emit("Sheared sheep (+2 Sheep Wool).")
			queue_redraw()
		"chicken":
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
		_:
			drops.append({"item_id": "food_raw", "count": 1})

	if drops.is_empty():
		return

	var bag: LootBag = LootBag.new()
	bag.items = drops
	bag.global_position = global_position
	if get_parent() != null:
		get_parent().add_child(bag)

func _draw_vector_z(pos: Vector2, sz: float, col: Color) -> void:
	draw_line(pos, pos + Vector2(sz, 0.0), col, 1.4)
	draw_line(pos + Vector2(sz, 0.0), pos + Vector2(0.0, sz), col, 1.4)
	draw_line(pos + Vector2(0.0, sz), pos + Vector2(sz, sz), col, 1.4)

func _draw() -> void:
	var outline_col: Color = Color(0.10, 0.11, 0.14, 0.96)
	var is_sleeping: bool = (current_state == State.SLEEPING)
	var is_grazing: bool = (current_state == State.GRAZING)

	# Animation timing variables
	var breath: float = sin(_sleep_breath_phase) * 1.3 if is_sleeping else 0.0
	var walk_bob: float = sin(_walk_phase * 2.0) * 1.5 * _walk_blend if not is_sleeping else 0.0
	var leg_a: float = sin(_walk_phase) * 4.8 * _walk_blend if not is_sleeping else 0.0
	var leg_b: float = -sin(_walk_phase) * 4.8 * _walk_blend if not is_sleeping else 0.0
	var head_eat_y: float = 6.0 + sin(_eat_timer * 11.0) * 1.8 if is_grazing else 0.0
	var flip: float = -1.0 if _facing_left else 1.0

	# Ground shadow with breathing variance
	var shadow_rad: float = 12.0
	if animal_type in ["chicken", "hare"]:
		shadow_rad = 7.0
	elif animal_type in ["horse", "bear", "cow"]:
		shadow_rad = 16.0
	draw_colored_polygon(IsoMath.diamond_polygon(Vector2(0.0, 3.0), shadow_rad, shadow_rad * 0.5), Color(0.0, 0.0, 0.0, 0.32))

	match animal_type:
		"cow":
			var hide_col: Color = Color(0.92, 0.90, 0.86)
			var spot_col: Color = Color(0.18, 0.18, 0.22)
			# 4 Legs
			if not is_sleeping:
				draw_rect(Rect2(-10.0 * flip + leg_a, -4.0, 3.2, 7.0), hide_col.darkened(0.2), true)
				draw_rect(Rect2(-5.0 * flip + leg_b, -4.0, 3.2, 7.0), hide_col.darkened(0.1), true)
				draw_rect(Rect2(4.0 * flip + leg_b, -4.0, 3.2, 7.0), hide_col.darkened(0.2), true)
				draw_rect(Rect2(8.0 * flip + leg_a, -4.0, 3.2, 7.0), hide_col, true)
			else:
				# Tucked hooves
				draw_rect(Rect2(-9.0 * flip, -1.0, 5.0, 3.0), hide_col.darkened(0.3), true)
				draw_rect(Rect2(5.0 * flip, -1.0, 5.0, 3.0), hide_col.darkened(0.3), true)

			# Torso
			var body_w: float = 24.0 + (breath if is_sleeping else 0.0)
			var body_h: float = 14.0 + (breath * 0.5 if is_sleeping else 0.0)
			var body_rect: Rect2 = Rect2(-12.0 * flip if not _facing_left else -12.0, -18.0 + walk_bob, body_w, body_h)
			draw_rect(body_rect, hide_col, true)
			draw_rect(body_rect, outline_col, false, 1.4)
			# Spots
			draw_circle(Vector2(-4.0 * flip, -12.0 + walk_bob), 4.2, spot_col)
			draw_circle(Vector2(4.0 * flip, -14.0 + walk_bob), 3.4, spot_col)

			# Tail
			var tail_sway: float = sin(_walk_phase * 1.5 + _eat_timer * 2.0) * 3.0
			draw_line(Vector2(-12.0 * flip, -15.0 + walk_bob), Vector2((-16.0 + tail_sway) * flip, -7.0 + walk_bob), hide_col, 1.6)

			# Head
			var head_pos: Vector2 = Vector2(10.0 * flip, -21.0 + walk_bob + head_eat_y)
			draw_rect(Rect2(head_pos.x - 4.5, head_pos.y - 4.5, 9.0, 9.0), hide_col, true)
			draw_rect(Rect2(head_pos.x - 4.5, head_pos.y - 4.5, 9.0, 9.0), outline_col, false, 1.2)
			# Horns
			draw_line(head_pos + Vector2(-2.0 * flip, -4.5), head_pos + Vector2(-4.0 * flip, -8.0), Color(0.85, 0.82, 0.72), 2.0)
			draw_line(head_pos + Vector2(2.0 * flip, -4.5), head_pos + Vector2(4.0 * flip, -8.0), Color(0.85, 0.82, 0.72), 2.0)
			# Pink snout
			draw_rect(Rect2(head_pos.x + 3.0 * flip - 2.0, head_pos.y + 0.5, 5.0, 4.0), Color(0.92, 0.65, 0.70), true)
			# Eye
			if is_sleeping:
				draw_line(head_pos + Vector2(-1.0 * flip, -1.0), head_pos + Vector2(1.5 * flip, -1.0), outline_col, 1.3)
			else:
				draw_circle(head_pos + Vector2(0.5 * flip, -1.0), 1.1, outline_col)

		"sheep":
			var wool_col: Color = Color(0.95, 0.94, 0.90) if not is_sheared else Color(0.82, 0.78, 0.72)
			var skin_col: Color = Color(0.22, 0.22, 0.25)
			# Legs
			if not is_sleeping:
				draw_rect(Rect2(-7.0 * flip + leg_a, -4.0, 2.8, 6.0), skin_col, true)
				draw_rect(Rect2(-2.0 * flip + leg_b, -4.0, 2.8, 6.0), skin_col, true)
				draw_rect(Rect2(3.0 * flip + leg_b, -4.0, 2.8, 6.0), skin_col, true)
				draw_rect(Rect2(7.0 * flip + leg_a, -4.0, 2.8, 6.0), skin_col, true)

			# Fluffy cloud wool body
			var wool_rad: float = 10.5 if not is_sheared else 7.5
			var body_center: Vector2 = Vector2(0.0, -12.0 + walk_bob - breath * 0.4)
			draw_circle(body_center, wool_rad + (breath * 0.5 if is_sleeping else 0.0), wool_col)
			draw_arc(body_center, wool_rad + (breath * 0.5 if is_sleeping else 0.0), 0.0, TAU, 16, outline_col, 1.4)
			if not is_sheared:
				draw_circle(body_center + Vector2(-4.0 * flip, -2.0), 5.0, wool_col.darkened(0.04))
				draw_circle(body_center + Vector2(3.0 * flip, -2.0), 5.5, wool_col.darkened(0.04))

			# Sheep head
			var shead_pos: Vector2 = Vector2(8.5 * flip, -13.0 + walk_bob + head_eat_y)
			draw_circle(shead_pos, 4.8, skin_col)
			# Ears
			draw_line(shead_pos + Vector2(-1.5 * flip, -3.5), shead_pos + Vector2(-4.5 * flip, -1.0), skin_col, 1.8)
			# Eye
			if is_sleeping:
				draw_line(shead_pos + Vector2(0.5 * flip, -1.0), shead_pos + Vector2(2.5 * flip, -1.0), Color.WHITE, 1.2)
			else:
				draw_circle(shead_pos + Vector2(1.5 * flip, -1.0), 1.0, Color.WHITE)

		"chicken":
			var c_body_col: Color = Color(0.96, 0.96, 0.96)
			var pecking_y: float = abs(sin(_eat_timer * 9.0)) * 5.0 if is_grazing else 0.0
			var c_pos: Vector2 = Vector2(0.0, -8.0 + walk_bob - breath * 0.5)

			# Feet
			if not is_sleeping:
				draw_line(Vector2(-2.0 * flip + leg_a * 0.5, -2.0), Vector2(-2.0 * flip + leg_a * 0.5, 1.0), Color(0.94, 0.65, 0.18), 1.6)
				draw_line(Vector2(2.0 * flip + leg_b * 0.5, -2.0), Vector2(2.0 * flip + leg_b * 0.5, 1.0), Color(0.94, 0.65, 0.18), 1.6)

			# Body
			draw_circle(c_pos, 5.8 + (breath * 0.3 if is_sleeping else 0.0), c_body_col)
			draw_arc(c_pos, 5.8 + (breath * 0.3 if is_sleeping else 0.0), 0.0, TAU, 14, outline_col, 1.2)

			# Tiny wing
			draw_arc(c_pos + Vector2(-1.0 * flip, 0.0), 3.2, 0.0, PI, 8, outline_col.lightened(0.3), 1.2)

			# Head & Comb
			var chead_pos: Vector2 = c_pos + Vector2(4.5 * flip, -4.5 + pecking_y)
			draw_circle(chead_pos, 3.2, c_body_col)
			draw_circle(chead_pos + Vector2(-0.5 * flip, -3.2), 1.8, Color(0.88, 0.18, 0.18)) # Comb
			draw_line(chead_pos + Vector2(1.0 * flip, 0.5), chead_pos + Vector2(4.5 * flip, 1.0), Color(0.94, 0.65, 0.18), 1.8) # Beak
			if is_sleeping:
				draw_line(chead_pos + Vector2(0.0, -1.0), chead_pos + Vector2(1.8 * flip, -1.0), outline_col, 1.1)
			else:
				draw_circle(chead_pos + Vector2(1.0 * flip, -0.8), 0.9, outline_col)

		"horse":
			var coat_col: Color = Color(0.50, 0.28, 0.14)
			var mane_col: Color = Color(0.18, 0.12, 0.08)
			# 4 Legs
			if not is_sleeping:
				for idx in [0, 1, 2, 3]:
					var lx: float = [-12.0, -6.0, 6.0, 12.0][idx] * flip
					var l_stride: float = leg_a if idx % 2 == 0 else leg_b
					draw_line(Vector2(lx, -8.0), Vector2(lx + l_stride, 2.0), coat_col, 3.0)
					draw_rect(Rect2(lx + l_stride - 1.5, 1.0, 3.0, 2.5), mane_col, true) # Hoof
			else:
				# Tucked legs in sleep
				draw_rect(Rect2(-11.0 * flip, -1.0, 6.0, 3.0), coat_col.darkened(0.2), true)
				draw_rect(Rect2(7.0 * flip, -1.0, 6.0, 3.0), coat_col.darkened(0.2), true)

			# Torso
			var hbody_rect: Rect2 = Rect2(-14.0 * flip if not _facing_left else -14.0, -22.0 + walk_bob, 28.0, 15.0 + breath)
			draw_rect(hbody_rect, coat_col, true)
			draw_rect(hbody_rect, outline_col, false, 1.4)

			# Flowing Tail
			var tail_anim: float = sin(_walk_phase * 1.5) * 4.0
			draw_line(Vector2(-14.0 * flip, -18.0 + walk_bob), Vector2((-19.0 + tail_anim) * flip, -8.0 + walk_bob), mane_col, 2.4)

			# Neck and Head
			var hhead_y: float = -28.0 + walk_bob + head_eat_y
			draw_line(Vector2(9.0 * flip, -18.0 + walk_bob), Vector2(14.0 * flip, hhead_y), coat_col, 5.0)
			draw_rect(Rect2(12.0 * flip - 3.0, hhead_y - 4.0, 8.5, 6.5), coat_col, true)
			draw_rect(Rect2(12.0 * flip - 3.0, hhead_y - 4.0, 8.5, 6.5), outline_col, false, 1.2)
			# Mane
			draw_line(Vector2(8.0 * flip, -20.0 + walk_bob), Vector2(13.0 * flip, hhead_y - 2.0), mane_col, 2.2)
			# Ears
			draw_line(Vector2(13.0 * flip, hhead_y - 4.0), Vector2(14.0 * flip, hhead_y - 8.0), coat_col, 2.0)
			# Eye
			if is_sleeping:
				draw_line(Vector2(14.0 * flip, hhead_y - 1.0), Vector2(16.5 * flip, hhead_y - 1.0), outline_col, 1.3)
			else:
				draw_circle(Vector2(15.0 * flip, hhead_y - 1.0), 1.2, outline_col)

		"donkey":
			var d_fur: Color = Color(0.56, 0.57, 0.60)
			# 4 Legs
			if not is_sleeping:
				for idx in [0, 1, 2, 3]:
					var dlx: float = [-10.0, -5.0, 4.0, 9.0][idx] * flip
					var dl_stride: float = leg_a if idx % 2 == 0 else leg_b
					draw_line(Vector2(dlx, -6.0), Vector2(dlx + dl_stride, 2.0), d_fur, 2.6)
			# Torso
			var d_rect: Rect2 = Rect2(-11.0 * flip if not _facing_left else -11.0, -17.0 + walk_bob, 22.0, 12.0 + breath)
			draw_rect(d_rect, d_fur, true)
			draw_rect(d_rect, outline_col, false, 1.3)

			# Pack saddlebag (only rendered if player equipped pack saddle)
			if has_pack:
				draw_rect(Rect2(-5.0 * flip - 3.0, -17.0 + walk_bob, 10.0, 8.0), Color(0.48, 0.30, 0.16), true)
				draw_rect(Rect2(-5.0 * flip - 3.0, -17.0 + walk_bob, 10.0, 8.0), outline_col, false, 1.1)

			# Head and Long Ears
			var dhead_y: float = -21.0 + walk_bob + head_eat_y
			draw_rect(Rect2(8.0 * flip - 2.0, dhead_y - 3.5, 7.5, 6.5), d_fur, true)
			draw_rect(Rect2(8.0 * flip - 2.0, dhead_y - 3.5, 7.5, 6.5), outline_col, false, 1.2)
			# Long ears
			draw_line(Vector2(9.0 * flip, dhead_y - 3.0), Vector2(10.0 * flip, dhead_y - 11.0), d_fur, 2.2)
			draw_line(Vector2(11.0 * flip, dhead_y - 3.0), Vector2(13.0 * flip, dhead_y - 10.0), d_fur, 2.2)
			# Snout & Eye
			draw_rect(Rect2(13.0 * flip - 1.5, dhead_y + 0.5, 3.5, 3.0), Color(0.85, 0.85, 0.82), true)
			if is_sleeping:
				draw_line(Vector2(10.0 * flip, dhead_y - 0.5), Vector2(12.0 * flip, dhead_y - 0.5), outline_col, 1.2)
			else:
				draw_circle(Vector2(11.0 * flip, dhead_y - 0.5), 1.1, outline_col)

		"deer":
			var deer_coat: Color = Color(0.68, 0.44, 0.24)
			# Slender legs
			if not is_sleeping:
				for idx in [0, 1, 2, 3]:
					var rlx: float = [-10.0, -5.0, 5.0, 10.0][idx] * flip
					var rl_stride: float = leg_a if idx % 2 == 0 else leg_b
					draw_line(Vector2(rlx, -7.0), Vector2(rlx + rl_stride, 2.0), deer_coat, 2.0)
					draw_rect(Rect2(rlx + rl_stride - 1.0, 1.0, 2.0, 2.0), Color(0.12, 0.12, 0.14), true) # Hoof
			# Torso
			var r_rect: Rect2 = Rect2(-11.0 * flip if not _facing_left else -11.0, -18.0 + walk_bob, 22.0, 11.0 + breath)
			draw_rect(r_rect, deer_coat, true)
			draw_rect(r_rect, outline_col, false, 1.2)
			# White tail patch
			draw_circle(Vector2(-11.0 * flip, -16.0 + walk_bob), 2.4, Color.WHITE)

			# Elegant Neck & Head
			var rhead_y: float = -24.0 + walk_bob + head_eat_y
			draw_line(Vector2(7.0 * flip, -15.0 + walk_bob), Vector2(11.0 * flip, rhead_y), deer_coat, 3.2)
			draw_rect(Rect2(9.0 * flip - 2.0, rhead_y - 3.0, 7.0, 5.5), deer_coat, true)
			# Branching Antlers
			var antler_col: Color = Color(0.28, 0.18, 0.10)
			draw_line(Vector2(10.0 * flip, rhead_y - 3.0), Vector2(10.0 * flip, rhead_y - 10.0), antler_col, 1.8)
			draw_line(Vector2(10.0 * flip, rhead_y - 7.0), Vector2(14.0 * flip, rhead_y - 10.0), antler_col, 1.4)
			draw_line(Vector2(10.0 * flip, rhead_y - 5.0), Vector2(7.0 * flip, rhead_y - 8.0), antler_col, 1.4)
			# Eye
			if is_sleeping:
				draw_line(Vector2(11.0 * flip, rhead_y - 0.5), Vector2(13.0 * flip, rhead_y - 0.5), outline_col, 1.1)
			else:
				draw_circle(Vector2(12.0 * flip, rhead_y - 0.5), 1.1, outline_col)

		"hare":
			var hare_col: Color = Color(0.60, 0.45, 0.32)
			var h_pos: Vector2 = Vector2(0.0, -6.0 + walk_bob - breath * 0.4)
			# Little feet
			if not is_sleeping:
				draw_rect(Rect2(-4.0 * flip + leg_a * 0.4, -1.0, 2.5, 3.0), hare_col.darkened(0.15), true)
				draw_rect(Rect2(3.0 * flip + leg_b * 0.4, -1.0, 2.5, 3.0), hare_col.darkened(0.15), true)
			# Small Body
			draw_circle(h_pos, 5.5 + (breath * 0.3 if is_sleeping else 0.0), hare_col)
			draw_arc(h_pos, 5.5 + (breath * 0.3 if is_sleeping else 0.0), 0.0, TAU, 12, outline_col, 1.1)
			# Puffy tail
			draw_circle(h_pos + Vector2(-5.5 * flip, -1.0), 1.8, Color.WHITE)
			# Head & Long Ears
			var hare_head: Vector2 = h_pos + Vector2(4.5 * flip, -2.5 + head_eat_y * 0.6)
			draw_circle(hare_head, 3.0, hare_col)
			draw_line(hare_head + Vector2(-0.5 * flip, -2.5), hare_head + Vector2(-0.5 * flip, -9.5), hare_col, 1.8)
			draw_line(hare_head + Vector2(1.0 * flip, -2.5), hare_head + Vector2(1.5 * flip, -9.0), hare_col, 1.8)
			if is_sleeping:
				draw_line(hare_head + Vector2(0.5 * flip, 0.0), hare_head + Vector2(2.0 * flip, 0.0), outline_col, 1.0)
			else:
				draw_circle(hare_head + Vector2(1.2 * flip, 0.0), 0.9, outline_col)

		"boar":
			var boar_col: Color = Color(0.38, 0.26, 0.18)
			# 4 Sturdy Legs
			if not is_sleeping:
				for idx in [0, 1, 2, 3]:
					var blx: float = [-10.0, -5.0, 4.0, 9.0][idx] * flip
					var bl_stride: float = leg_a if idx % 2 == 0 else leg_b
					draw_rect(Rect2(blx + bl_stride, -3.0, 3.2, 5.5), boar_col.darkened(0.2), true)
			# Hunched Torso
			var boar_rect: Rect2 = Rect2(-12.0 * flip if not _facing_left else -12.0, -17.0 + walk_bob, 24.0, 14.0 + breath)
			draw_rect(boar_rect, boar_col, true)
			draw_rect(boar_rect, outline_col, false, 1.4)
			# Bristly spine
			draw_line(Vector2(-9.0 * flip, -17.0 + walk_bob), Vector2(5.0 * flip, -17.0 + walk_bob), Color(0.22, 0.14, 0.09), 2.2)

			# Thick Head & White Tusks
			var bhead_y: float = -18.0 + walk_bob + head_eat_y
			draw_rect(Rect2(8.0 * flip - 2.0, bhead_y - 2.0, 9.0, 8.0), boar_col, true)
			draw_rect(Rect2(8.0 * flip - 2.0, bhead_y - 2.0, 9.0, 8.0), outline_col, false, 1.2)
			# Tusk
			draw_line(Vector2(14.0 * flip, bhead_y + 4.0), Vector2(16.0 * flip, bhead_y + 0.5), Color(0.95, 0.95, 0.90), 2.0)
			# Eye
			if is_sleeping:
				draw_line(Vector2(10.0 * flip, bhead_y), Vector2(12.0 * flip, bhead_y), outline_col, 1.2)
			else:
				draw_circle(Vector2(11.0 * flip, bhead_y), 1.1, Color(0.85, 0.20, 0.20))

		"bear":
			var bear_col: Color = Color(0.30, 0.18, 0.10)
			# Heavy Paws
			if not is_sleeping:
				for idx in [0, 1, 2, 3]:
					var plx: float = [-12.0, -6.0, 6.0, 12.0][idx] * flip
					var pl_stride: float = leg_a if idx % 2 == 0 else leg_b
					draw_rect(Rect2(plx + pl_stride, -4.0, 4.5, 7.0), bear_col.darkened(0.2), true)
			# Massive Torso
			var bear_rect: Rect2 = Rect2(-15.0 * flip if not _facing_left else -15.0, -22.0 + walk_bob, 30.0, 18.0 + breath)
			draw_rect(bear_rect, bear_col, true)
			draw_rect(bear_rect, outline_col, false, 1.5)

			# Round Head
			var bear_head_y: float = -23.0 + walk_bob + head_eat_y
			draw_circle(Vector2(12.0 * flip, bear_head_y), 6.5, bear_col)
			draw_arc(Vector2(12.0 * flip, bear_head_y), 6.5, 0.0, TAU, 14, outline_col, 1.3)
			# Round Ears
			draw_circle(Vector2(9.0 * flip, bear_head_y - 6.0), 2.2, bear_col.darkened(0.15))
			draw_circle(Vector2(13.5 * flip, bear_head_y - 6.0), 2.2, bear_col.darkened(0.15))
			# Snout & Eye
			draw_circle(Vector2(16.5 * flip, bear_head_y + 1.5), 2.8, Color(0.22, 0.14, 0.08))
			if is_sleeping:
				draw_line(Vector2(12.0 * flip, bear_head_y - 1.0), Vector2(14.5 * flip, bear_head_y - 1.0), outline_col, 1.4)
			else:
				draw_circle(Vector2(13.0 * flip, bear_head_y - 1.0), 1.3, outline_col)

		"dog":
			var dog_col: Color = Color(0.70, 0.48, 0.24)
			# Legs
			if not is_sleeping:
				draw_rect(Rect2(-8.0 * flip + leg_a, -4.0, 2.5, 6.0), dog_col, true)
				draw_rect(Rect2(-3.0 * flip + leg_b, -4.0, 2.5, 6.0), dog_col, true)
				draw_rect(Rect2(3.0 * flip + leg_b, -4.0, 2.5, 6.0), dog_col, true)
				draw_rect(Rect2(7.0 * flip + leg_a, -4.0, 2.5, 6.0), dog_col, true)
			# Torso
			var d_rect: Rect2 = Rect2(-9.0 * flip if not _facing_left else -9.0, -15.0 + walk_bob, 18.0, 11.0 + breath)
			draw_rect(d_rect, dog_col, true)
			draw_rect(d_rect, outline_col, false, 1.2)
			# Wagging Tail
			var tail_wag: float = sin(Time.get_ticks_msec() * 0.012) * 4.0 if not is_sleeping else 0.0
			draw_line(Vector2(-9.0 * flip, -13.0 + walk_bob), Vector2((-13.0 + tail_wag) * flip, -18.0 + walk_bob), dog_col, 2.0)
			# Head & Floppy Ears
			var dhead_y: float = -18.0 + walk_bob + head_eat_y
			draw_circle(Vector2(7.0 * flip, dhead_y), 4.5, dog_col)
			draw_circle(Vector2(5.0 * flip, dhead_y - 3.0), 2.4, dog_col.darkened(0.2)) # Ear
			draw_rect(Rect2(9.0 * flip - 1.0, dhead_y, 3.5, 3.0), dog_col.darkened(0.3), true) # Muzzle
			if is_sleeping:
				draw_line(Vector2(6.5 * flip, dhead_y - 1.0), Vector2(8.5 * flip, dhead_y - 1.0), outline_col, 1.2)
			else:
				draw_circle(Vector2(7.5 * flip, dhead_y - 1.0), 1.1, outline_col)

		"cat":
			var cat_col: Color = Color(0.78, 0.44, 0.16)
			# Legs
			if not is_sleeping:
				draw_rect(Rect2(-6.0 * flip + leg_a, -3.0, 2.0, 5.0), cat_col, true)
				draw_rect(Rect2(5.0 * flip + leg_b, -3.0, 2.0, 5.0), cat_col, true)
			# Torso
			var cat_rect: Rect2 = Rect2(-7.5 * flip if not _facing_left else -7.5, -12.0 + walk_bob, 15.0, 9.0 + breath)
			draw_rect(cat_rect, cat_col, true)
			draw_rect(cat_rect, outline_col, false, 1.1)
			# Curled Tail
			draw_arc(Vector2(-8.0 * flip, -12.0 + walk_bob), 4.5, -PI * 0.5, PI * 0.5, 8, cat_col, 1.8)
			# Head with pointed ears
			var chead_y: float = -14.0 + walk_bob + head_eat_y
			draw_circle(Vector2(6.0 * flip, chead_y), 3.8, cat_col)
			# Pointed Ears
			draw_line(Vector2(4.5 * flip, chead_y - 3.0), Vector2(4.5 * flip, chead_y - 6.5), cat_col, 1.8)
			draw_line(Vector2(7.0 * flip, chead_y - 3.0), Vector2(7.0 * flip, chead_y - 6.5), cat_col, 1.8)
			if is_sleeping:
				draw_line(Vector2(5.5 * flip, chead_y - 0.5), Vector2(7.5 * flip, chead_y - 0.5), outline_col, 1.0)
			else:
				draw_circle(Vector2(6.5 * flip, chead_y - 0.5), 1.0, Color(0.20, 0.85, 0.30)) # Green cat eyes

		_:
			var def_col: Color = Color(0.56, 0.38, 0.22)
			var g_rect: Rect2 = Rect2(-10.0 * flip if not _facing_left else -10.0, -15.0 + walk_bob, 20.0, 11.0 + breath)
			draw_rect(g_rect, def_col, true)
			draw_rect(g_rect, outline_col, false, 1.3)

	# Active Grass chewing particles
	for gp in _grass_particles:
		draw_circle(gp["pos"], 1.3, gp["color"])

	# Active floating "Zzz" particles in Sleeping State
	for zp in _zzz_particles:
		var p_life: float = float(zp["life"])
		var p_max: float = float(zp["max_life"])
		var p_alpha: float = clampf(p_life / 0.5, 0.0, 1.0) * minf(1.0, (p_max - p_life) / 0.25)
		var z_color: Color = Color(0.78, 0.86, 1.0, p_alpha * 0.95)
		_draw_vector_z(zp["pos"], float(zp["size"]), z_color)
