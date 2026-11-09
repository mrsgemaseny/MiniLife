from pathlib import Path
import difflib
print('*** Begin Patch')
for p in Path('scripts/entities').glob('*.gd'):
 old=p.read_text(encoding='utf-8-sig'); new=old
 ranges={
 'resource_node.gd':('\t# Ground shadow firmly anchored', '\tif growth_stage == "stump":'),
 'structure_entity.gd':('\t# Ground shadow (never for floors', '\t# 1. High-fidelity'),
 'projectile.gd':('\t# 1. Ground shadow while airborne', '\tif is_jav:'),
 'animal_entity.gd':('\t# Ground shadow with breathing variance', '\t# 1. High-fidelity'),
 'player.gd':('\t# Isometric ground shadow', '\t# Cardinal body views'),
 }
 if p.name in ranges:
  a,b=ranges[p.name]
  if a in new and b in new[new.index(a):]:
   start=new.index(a); end=new.index(b,start);new=new[:start]+new[end:]
 if p.name in ['npc_base.gd','enemy_base.gd','loot_bag.gd']:
  new=''.join(l for l in new.splitlines(True) if not ('draw_' in l and 'Color(0.0, 0.0, 0.0,' in l))
 if p.name=='corpse.gd':
  new=new.replace('\tdraw_ellipse_shadow()\n','')
  a=new.index('func draw_ellipse_shadow()');b=new.index('func _body_style',a);new=new[:a]+new[b:]
 if new!=old:
  print('*** Update File: '+str(p))
  print(''.join(list(difflib.unified_diff(old.splitlines(True),new.splitlines(True)))[2:]),end='')
print('*** End Patch')
