import json
from pathlib import Path
root=Path('data')
def read(n): return json.loads((root/(n+'.json')).read_text(encoding='utf-8'))
def save(n,x): (root/(n+'.json')).write_text(json.dumps(x,ensure_ascii=False,indent='\t')+'\n',encoding='utf-8')
ts=read('tech_tree'); rs=read('recipes'); ss=read('structures'); items=read('items'); t={e['id']:e for e in ts}
# Bootstrap knowledge is learned without a desk; four T1 research branches follow at L3.
bootstrap=['herbs_gathering','stone_harvesting','wood_harvesting','primitive_hearth','food_roasting','stone_tools','stone_weapons']
for e in ts:
 e['min_level']= {1:3,2:4,3:5,4:6,5:9}.get(e['tier'],3)
 if e['id'] in bootstrap: e['min_level']=2
for k in ['stone_tools','stone_weapons']: t[k]['tier']=1;t[k]['tier_label']='TIER I'
t['gambeson_crafting']['costs']={'cloth':6,'wool':2}
t['leather_armor_crafting']['costs']={'raw_leather':6,'cloth':4}
t['leather_armor_crafting']['prerequisites']=['material_refinement']
t['hunting_archery_shields']['costs']={'plank':6,'raw_leather':2}
t['material_refinement']['costs']={'wood':6,'raw_leather':2}
t['iron_smelting']['prerequisites']=['bronze_tools'];t['iron_smelting']['min_level']=5
t['clay_ore_smelter']['costs']={'stone':12,'charcoal':4}
t['steel_crucible_smelting']['prerequisites']=['iron_plate_armor']
# Higher quality textiles and tanning belong to the iron age.
ts.append(dict(id='advanced_materials',name='Advanced Textiles & Tanning',tier=4,tier_label='TIER IV',icon='tanned_leather',description='Quality cloth and tanned leather for iron-age equipment.',grid_x=3,grid_y=8,prerequisites=['iron_smelting','material_refinement'],costs={'cloth':6,'treated_leather':4},min_level=6,unlocks=[]))
# Preserve aliases for old save files, but use canonical IDs in current data.
alias={'carpentry_planks':'plank_crafting','iron_forging':'iron_weapons','pyrology_coal':'primitive_hearth'}
seen=set(); fixed=[]
for r in rs:
 if r['id'] in seen: continue
 seen.add(r['id']);fixed.append(r)
 r['tech_required']=alias.get(r.get('tech_required',''),r.get('tech_required',''))
 if r['id'] in ['craft_stone_axe','craft_stone_pickaxe','craft_plank','burn_charcoal','craft_torch']: r['tech_required']=''
 if r['id']=='craft_torch': r['inputs']=[{'item_id':'wood','count':1},{'item_id':'cloth','count':1}]
 if r['id'] in ['craft_cloth','craft_treated_leather','craft_cloth_from_wool']: r['skill_required']={}
 if r['id'] in ['craft_tanned_leather','craft_quality_cloth','craft_quality_clothing']: r['tech_required']='advanced_materials'
 if r['id']=='craft_arming_doublet':r['tech_required']='advanced_materials'
 if r['id']=='craft_wooden_shield':r['inputs']=[{'item_id':'plank','count':3},{'item_id':'raw_leather','count':1}]
 if r['id'] in ['craft_leather_helmet','craft_leather_greaves','craft_leather_boots','craft_boiled_leather_cuirass']:
  for i in r['inputs']:
   if i['item_id']=='treated_leather':i['item_id']='raw_leather'
 if r['id']=='craft_leather_lamellar':r['tech_required']='bronze_lamellar_crafting'
 if r['id'].startswith('forge_bronze'):r['station']='workbench'
 if r['id'].startswith('smelt_') and r['id']!='smelt_brick':r['station']='ore_smelter'
 if r['id'].startswith('forge_steel') and r['output']['item_id'] in ['steel_pickaxe','steel_axe','steel_sword','steel_dagger']:
  r['inputs']=[i for i in r['inputs'] if i['item_id']!='coal']
  for i in r['inputs']:
   if i['item_id']=='iron_ingot':i['item_id']='steel_ingot'
 if r['id']=='forge_iron_brigandine': continue
 if r['id']=='craft_shears': r['tech_required']='wool_clothing';r['inputs']=[{'item_id':'stone','count':2},{'item_id':'wood','count':1}]
 # Remove feather micro-material from ammunition.
 r['inputs']=[i for i in r['inputs'] if i['item_id']!='feather']
rs=[r for r in fixed if r['id']!='forge_iron_brigandine']
for s in ss:
 s['tech_required']=alias.get(s.get('tech_required',''),s.get('tech_required',''))
 if s['id'] in ['campfire','furnace']:s['tech_required']='';s['min_level']=2
 if s['id'] in ['workbench','research_table','storage']:s['min_level']=3
 if s['id']=='ore_smelter':s['tech_required']='clay_ore_smelter'
 if s['id']=='forge':s['tech_required']='iron_smelting'
 if s['id']=='water_mill':s['tech_required']='construction_masonry'
 if s['id']=='mechanical_water_mill':s['tech_required']='steel_weapons'
# UI unlock lists derive from actual recipe requirements.
for tech in ts:
 tech['unlocks']=[r['id'] for r in rs if r.get('tech_required')==tech['id']]+[s['id'] for s in ss if s.get('tech_required')==tech['id']]
for i in items:
 recipe=next((r for r in rs if r['output']['item_id']==i['id']),None)
 if recipe:i['craft_requirements']={v['item_id']:v['count'] for v in recipe['inputs']}
save('tech_tree',ts);save('recipes',rs);save('structures',ss);save('items',items)
