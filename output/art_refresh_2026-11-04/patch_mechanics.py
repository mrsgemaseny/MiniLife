from pathlib import Path
import difflib

def emit(path, new):
    old = Path(path).read_text(encoding='utf-8-sig')
    if old == new: return
    diff = list(difflib.unified_diff(old.splitlines(True), new.splitlines(True), n=3))
    print('*** Update File: ' + path)
    print(''.join(diff[2:]), end='')

print('*** Begin Patch')
p = 'scripts/entities/player.gd'
s = Path(p).read_text(encoding='utf-8-sig')
s = s.replace('var _locked_target: Node2D = null', 'var _locked_target: Node2D = null\nvar item_action: ItemActionComponent = null')
s = s.replace('\t_setup_torch_light()','\titem_action = ItemActionComponent.new()\n\tadd_child(item_action)\n\t_setup_torch_light()',1)
start = s.index('func use_held_consumable()')
end = s.index('\nfunc use_slot_item(', start)
s = s[:start] + '''func use_held_consumable() -> bool:
	return _start_consuming(active_hotbar_index)

func _start_consuming(slot_index: int) -> bool:
	if is_dead or _attack_cooldown > 0.0:
		return false
	var id: String = str(inventory.get_slot(slot_index).get("item_id", ""))
	if id.is_empty():
		return false
	return item_action.begin("Use " + str(DataRegistry.get_item(id).get("name", id)), 0.35, func() -> void:
		ConsumableUse.consume(self, slot_index, id)
		_attack_cooldown = 0.4
	)

func start_item_action(label: String, seconds: float, completion: Callable, stamina_cost: float = 0.0) -> bool:
	_locked_target = null
	return item_action.begin(label, seconds, completion, stamina_cost)

func get_defense() -> float:
	return equipment.get_defense() + (15.0 if status_effects.has_effect("ironskin") else 0.0)

func select_ammunition() -> String:
	var choices: Array[String] = ["iron_bolt"] if equipment.get_item_id("weapon").contains("crossbow") else ["steel_arrow", "iron_arrow", "bronze_arrow", "arrow"]
	for id: String in choices:
		if inventory.has_item(id, 1):
			return id
	return ""

''' + s[end:]
start = s.index('\telif item_type == "consumable"')
end = s.index('\telif equipment.can_equip', start)
s = s[:start] + '\telif item_type in ["consumable", "food", "medical", "medicine"]:\n\t\t_start_consuming(slot_index)\n' + s[end:]
s = s.replace('if not inventory.has_item("arrow", 1):', 'if select_ammunition().is_empty():')
s = s.replace('\t\t_last_fired_projectile_id = "arrow"\n\t\tinventory.remove_item("arrow", 1)', '\t\t_last_fired_projectile_id = select_ammunition()\n\t\tinventory.remove_item(_last_fired_projectile_id, 1)')
# Capture weapon stats before the last thrown javelin unequips its weapon.
s = s.replace('\t# Consumption of ammo', '\tvar w_stats: Dictionary = equipment.get_weapon_stats()\n\t# Consumption of ammo')
s = s.replace('\n\tvar w_stats: Dictionary = equipment.get_weapon_stats()\n\tvar base_dmg:', '\n\tvar base_dmg:')
s = s.replace('\tvar skill_lvl: int = skills.get_level("ranged")', '\tif not is_jav:\n\t\tbase_dmg += float(DataRegistry.get_item(_last_fired_projectile_id).get("stats", {}).get("damage", 0.0))\n\tvar skill_lvl: int = skills.get_level("ranged")')
s = s.replace(' * charge_ratio\n\tif stats.stamina < stam_cost:', ' * charge_ratio * equipment.get_stamina_cost_multiplier()\n\tif stats.stamina < stam_cost:')
s = s.replace('stats.stamina < Config.STAMINA_COST_ATTACK:', 'stats.stamina < Config.STAMINA_COST_ATTACK * equipment.get_stamina_cost_multiplier():')
s = s.replace('stats.modify("stamina", -Config.STAMINA_COST_ATTACK)', 'stats.modify("stamina", -Config.STAMINA_COST_ATTACK * equipment.get_stamina_cost_multiplier())')
s = s.replace('var is_attack_pressed: bool = Input.is_action_pressed("attack")', 'var is_attack_pressed: bool = not bool(get_meta("item_action_busy", false)) and Input.is_action_pressed("attack")')
s = s.replace('if not is_mining_channel and not status_effects.is_action_blocked():', 'if not bool(get_meta("item_action_busy", false)) and not is_mining_channel and not status_effects.is_action_blocked():')
s = s.replace('\tif event.is_action_pressed("attack"):\n', '\tif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and item_action.remaining > 0.0:\n\t\titem_action.cancel()\n\t\tget_viewport().set_input_as_handled()\n\t\treturn\n\tif event.is_action_pressed("attack"):\n\t\tif bool(get_meta("item_action_busy", false)):\n\t\t\treturn\n\t\tif _is_holding_consumable():\n\t\t\tuse_held_consumable()\n\t\t\tget_viewport().set_input_as_handled()\n\t\t\treturn\n\t\tif _try_use_world_item():\n\t\t\tget_viewport().set_input_as_handled()\n\t\t\treturn\n',1)
s = s.replace('\t\tif _has_direct_interactable_under_cursor():', '\t\tif _try_use_world_item():\n\t\t\tget_viewport().set_input_as_handled()\n\t\t\treturn\n\t\tif _has_direct_interactable_under_cursor():',1)
emit(p,s)
print('*** End Patch')
