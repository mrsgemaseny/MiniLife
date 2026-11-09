import json
T=json.load(open('data/tech_tree.json',encoding='utf-8'));R=json.load(open('data/recipes.json',encoding='utf-8'));S=json.load(open('data/structures.json',encoding='utf-8'))
raw={'wood','stone','herb','wool','raw_leather','coal','clay','copper_ore','tin_ore','iron_ore','healing_herb','vigor_herb','fire_herb','food_raw','fish','berries','wheat'}
items=set(raw);tech={'herbs_gathering'};stations={''}
for _ in range(100):
 before=(len(items),len(tech),len(stations))
 for t in T:
  if set(t.get('prerequisites',[]))<=tech and set(t.get('costs',{}))<=items:tech.add(t['id'])
 for s in S:
  if s.get('tech_required','') in tech|{''} and all(i['item_id'] in items for i in s.get('materials',[])):stations.add(s['id'])
 for r in R:
  if r.get('tech_required','') in tech|{''} and r.get('station','') in stations and all(i['item_id'] in items for i in r['inputs']):items.add(r['output']['item_id'])
 if before==(len(items),len(tech),len(stations)):break
print('BLOCKED TECH',[(t['id'],set(t.get('prerequisites',[]))-tech,set(t.get('costs',{}))-items) for t in T if t['id'] not in tech])
print('BLOCKED RECIPE',[(r['id'],set(i['item_id'] for i in r['inputs'])-items,r.get('tech_required'),r.get('station')) for r in R if r['output']['item_id'] not in items])

assert len({r['id'] for r in R}) == len(R), "duplicate recipe IDs"
assert len({t['id'] for t in T}) == len(T), "duplicate tech IDs"
assert all(r.get('tech_required','') in {t['id'] for t in T}|{''} for r in R)
assert all(t['id'] in tech for t in T), "unreachable research"
assert all(r['output']['item_id'] in items for r in R), "unreachable output"
print('PASS: unique IDs, valid research references, reachable research and recipes')

# Validate each age separately: later materials cannot mask an early deadlock.
tech_ids = {t['id'] for t in T}
assert all(p in tech_ids for t in T for p in t.get('prerequisites', []))
assert all(s.get('tech_required','') in tech_ids|{''} for s in S)
items = {'wood','stone','herb','wool','raw_leather','coal','clay','healing_herb','vigor_herb','fire_herb','food_raw','fish','berries','wheat'}
tech = {'herbs_gathering'}
stations = {''}
for level in range(2, 10):
 if level >= 4: items |= {'copper_ore','tin_ore'}
 if 'bronze_pickaxe' in items: items.add('iron_ore')
 for _ in range(100):
  before = (len(items),len(tech),len(stations))
  for t in T:
   if t.get('min_level',2)<=level and set(t.get('prerequisites',[]))<=tech and set(t.get('costs',{}))<=items: tech.add(t['id'])
  for station in S:
   if station.get('min_level',2)<=level and station.get('tech_required','') in tech|{''} and all(i['item_id'] in items for i in station.get('materials',[])):stations.add(station['id'])
  for r in R:
   if r.get('tech_required','') in tech|{''} and r.get('station','') in stations and all(i['item_id'] in items for i in r['inputs']):items.add(r['output']['item_id'])
  if 'bronze_pickaxe' in items:items.add('iron_ore')
  if before == (len(items),len(tech),len(stations)):break
 if level==2: assert {'stone_axe','stone_pickaxe','charcoal'}<=items and 'furnace' in stations
 if level==3: assert {'plank_crafting','primitive_archery','herbalism_medicine','wool_clothing'}<=tech
 if level==4: assert {'leather_armor','gambeson','wooden_shield'}<=items
 if level==5: assert {'bronze_pickaxe','iron_ore'}<=items and 'iron_smelting' in tech
 if level==6: assert {'iron_helmet','iron_greaves','iron_lamellar'}<=items
 if level==9: assert {'steel_sword','steel_plate_armor'}<=items
print('PASS: age-by-age bootstrap, leather, bronze mining, iron and steel dependencies')
