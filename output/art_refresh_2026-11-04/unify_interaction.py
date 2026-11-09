from pathlib import Path
import difflib
def emit(p,old,new):
 if old==new:return
 print('*** Update File: '+p)
 print(''.join(list(difflib.unified_diff(old.splitlines(True),new.splitlines(True)))[2:]),end='')
print('*** Begin Patch')
p='scripts/entities/player.gd';old=Path(p).read_text(encoding='utf-8-sig');s=old
a=s.index('func perform_interact()');b=s.index('func _get_held_placeable_structure()',a)
s=s[:a]+'''func perform_interact(allow_nearest: bool = true) -> void:
	if is_dead or GameManager.is_paused() or bool(get_meta("item_action_busy", false)):
		return
	var target: Node2D = InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
	if target == null and allow_nearest:
		target = InteractionPicker.nearest(get_tree(), self)
	if target == null:
		return
	if not InteractionPicker.in_reach(self, target):
		SignalBus.notification_posted.emit("Too far away. Move closer to the selected object.")
		return
	if target.is_in_group("interactable") and target.has_method("interact"):
		target.call("interact", self)

'''+s[b:]
a=s.index('func _get_structure_under_cursor()');b=s.index('func _try_place_block_from_hand()',a)
s=s[:a]+'''func _get_structure_under_cursor() -> StructureEntity:
	var target: Node2D = InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
	return target as StructureEntity if target is StructureEntity and InteractionPicker.in_reach(self,target) else null

func _has_direct_interactable_under_cursor() -> bool:
	var target: Node2D = InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
	return target != null and target.is_in_group("interactable")

'''+s[b:]
a=s.index('func _get_enemy_under_cursor()');b=s.index('func perform_attack()',a)
s=s[:a]+'''func _get_enemy_under_cursor() -> Node2D:
	var target: Node2D = InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
	if target != null and target.is_in_group("combatant") and (not target.has_method("is_alive") or bool(target.call("is_alive"))):
		return target
	return null

'''+s[b:]
a=s.index('\t\t# 1. Check for player structures under cursor');b=s.index('\n\t\tif candidate_struct != null:',a)
s=s[:a]+'''		var selected: Node2D = InteractionPicker.pick(get_tree(), mouse_world, self)
		if selected is StructureEntity and InteractionPicker.in_reach(self,selected) and Input.is_key_pressed(KEY_CTRL) and selected.is_player_built:
			candidate_struct = selected as StructureEntity
		elif selected is ResourceNode and InteractionPicker.in_reach(self,selected):
			candidate_res = selected as ResourceNode
'''+s[b:]
needle='\t\tif struct_under_cursor != null:\n'
s=s.replace(needle,needle+'\t\t\tif not Input.is_key_pressed(KEY_CTRL):\n\t\t\t\tperform_interact(false)\n\t\t\t\tget_viewport().set_input_as_handled()\n\t\t\t\treturn\n',1)
a=s.index('\telif event.is_action_pressed("interact") or');b=s.index('\nfunc _read_movement_input()',a)
s=s[:a]+'''	elif event.is_action_pressed("interact") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		var target: Node2D = InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
		if target != null:
			perform_interact(false)
		elif _is_holding_placeable_block() and event is InputEventMouseButton:
			_try_place_block_from_hand()
		elif not event is InputEventMouseButton:
			perform_interact(true)
		get_viewport().set_input_as_handled()
'''+s[b:]
emit(p,old,s)
p='scripts/ui/hud.gd';old=Path(p).read_text(encoding='utf-8-sig');s=old
a=s.index('\tvar candidate: Node2D = null',s.index('func _update_world_hover_inspect'));b=s.index('\n\tif candidate != null:',a)
s=s[:a]+'''	var player: Node = get_tree().get_first_node_in_group("player")
	var candidate: Node2D = InteractionPicker.pick(get_tree(), mouse_world, player)
	var candidate_top_offset: float = -40.0
'''+s[b:]
s=s.replace('if _hover_timer >= 1.0:', 'if _hover_timer >= 0.2:')
emit(p,old,s)
print('*** End Patch')
