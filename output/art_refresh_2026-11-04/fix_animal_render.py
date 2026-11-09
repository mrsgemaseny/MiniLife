from pathlib import Path
import difflib
p=Path('scripts/entities/animal_entity.gd'); old=p.read_text(encoding='utf-8-sig')
a=old.index('func _draw()');b=old.index('\nfunc is_alive()',a)
new=old[:a]+'''func _draw() -> void:
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

'''+old[b:]
print('*** Begin Patch\n*** Update File: '+str(p));print(''.join(list(difflib.unified_diff(old.splitlines(True),new.splitlines(True)))[2:]),end='');print('*** End Patch')
