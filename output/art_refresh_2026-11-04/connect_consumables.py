from pathlib import Path
import difflib
p=Path('scripts/entities/player.gd'); old=p.read_text(encoding='utf-8-sig'); new=old
a=new.index('func use_held_consumable()'); b=new.index('func use_slot_item(',a)
new=new[:a]+'''func use_held_consumable() -> bool:
	return _begin_consuming(active_hotbar_index)

func _begin_consuming(slot_index: int) -> bool:
	if is_dead or _attack_cooldown > 0.0:
		return false
	var id: String = str(inventory.get_slot(slot_index).get("item_id", ""))
	if id.is_empty():
		return false
	var action: ItemActionComponent = get_node_or_null("ItemAction") as ItemActionComponent
	if action == null:
		action = ItemActionComponent.new()
		action.name = "ItemAction"
		add_child(action)
	var started: bool = action.begin("Use " + str(DataRegistry.get_item(id).get("name", id)), 0.35, func() -> void:
		if ConsumableUse.consume(self, slot_index, id):
			_attack_cooldown = 0.4
			queue_redraw()
	)
	if started:
		SignalBus.ui_close_all_requested.emit()
	return started


'''+new[b:]
a=new.index('\telif item_type == "consumable"'); b=new.index('\telif equipment.can_equip',a)
new=new[:a]+'\telif item_type in ["consumable", "food", "medical", "medicine"]:\n\t\t_begin_consuming(slot_index)\n'+new[b:]
new=new.replace('func _tick_auto_attack(_delta: float) -> void:', 'func _tick_auto_attack(_delta: float) -> void:\n\tif bool(get_meta("item_action_busy", false)):\n\t\treturn',1)
new=new.replace('func _unhandled_input(event: InputEvent) -> void:', 'func _unhandled_input(event: InputEvent) -> void:\n\tif bool(get_meta("item_action_busy", false)) and event.is_action_pressed("attack"):\n\t\treturn',1)
new=new.replace('var is_attack_pressed: bool = Input.is_action_pressed("attack")', 'var is_attack_pressed: bool = not bool(get_meta("item_action_busy", false)) and Input.is_action_pressed("attack")',1)
print('*** Begin Patch\n*** Update File: '+str(p));print(''.join(list(difflib.unified_diff(old.splitlines(True),new.splitlines(True)))[2:]),end='');print('*** End Patch')
