# Wearable sprites v3

Created with the built-in imagegen tool, not API/CLI. Selected outputs copied into this project. Existing item PNGs used as references and never overwritten. Rejected initial generations are not referenced. Reference models were checked after user correction; the steel armet is not a great helm.

## Assets and final prompt specifications

All prompts: production transparent medieval MiniLife wearable atlas, FOUR columns: SOUTH FRONT / EAST RIGHT PROFILE / NORTH BACK / WEST LEFT PROFILE. True alpha, isolated sprites with generous gutters, bold dark outlines, muted hand-painted materials, no background/shadow/text/grid. Match existing item references rather than redesigning. Back views have no face or front buckles. Front/side/back frames measured by alpha bounds rather than assuming equal generated cell sizes.

### heads_matched_v3.png

References: items/steel_helmet.png, items/wool_hood.png, items/chainmail_coif.png, characters/generated/pawn_simple.png.

FOUR rows, 16 complete replacement heads. Row1 EXISTING STEEL ARMET: pointed hinged visor, eye slit, vertical vent slots, temple pivot, articulated gorget; NOT cylindrical. Row2 NEW QUALITY IRON GREAT HELM: flat cylindrical enclosed helm, narrow slit, riveted nasal strip, intentionally distinct from armet. Row3 BROWN stitched wool hood with shoulder collar, simple tan face and two dot eyes. Row4 iron chainmail coif with same simple face. Round compact pawn proportions, no torso or empty inventory hole. No face or visor on the back.

### torsos_matched_v3.png

References: items/boiled_leather_cuirass.png, items/iron_plate_armor.png, items/steel_cuirass.png, items/steel_plate_armor.png, items/steel_brigandine.png.

SEVEN rows. Row1 embossed muscular brown boiled leather cuirass, leather skirt. Row2 iron chainmail hauberk, beige undersleeves, brown belt. Row3 smooth iron breastplate with riveted edges, rounded layered shoulders, leather skirt. Row4 riveted rectangular iron plates on brown vest, burgundy short sleeves, belt and segmented skirt. Row5 STEEL chevron breastplate with burgundy sleeves, layered small shoulders, belt and fauld. Row6 full STEEL articulated plate, segmented sleeves and gauntlets at sides, chevron breastplate and fauld. Row7 BURGUNDY steel brigandine, silver rivets, brown leather shoulders, NEVER blue cloth. Compact hollow torsos only, no heads/neck/legs/body filling openings. Same reference construction across all views.

### lower_matched_v3.png

References: items/wool_wraps.png, items/leather_greaves.png, items/bronze_greaves.png, items/steel_greaves.png, items/steel_boots.png.

NINE rows of naturally worn pairs, orthographic not inventory 3/4. Row1 beige wool wraps over brown boots. Row2 dark brown leather greaves with front LACES and side buckles. Row3 bronze anatomical greaves, round knee cops, muscle contours and embossed shin. Row4 dark iron tall shin greaves, rivet borders and ankle straps. Row5 STEEL articulated greaves with ROUND knee cops and pronounced shin RIDGE. Row6 short brown leather boots with folded cuffs/buckles. Row7 short bronze plated boots, toe plates and ankle straps. Row8 dark iron plated short boots and rivets. Row9 pale steel articulated plated boots with dark leather soles, no laces. Front/back show paired legs, profile shows narrow overlapping pair, knees straight, consistent baseline. No heads/torso/arms.

## Runtime packaging

- Existing clothing.png, armor_basic.png, armor_advanced.png and heads_basic.png supply the remaining matching designs.
- wearable_regions_v3.json: measured frame bounds, rebuilt by tools/build_wearable_regions.gd in the authoring project. That tool also extracts the new great-helm inventory icon from its own new atlas; no existing icon is modified. It is not an export/runtime script.
- New great-helm icon: assets/sprites/items/iron_great_helm.png.
- Preview of all 36 items plus six full sets: output/wearable_catalogue.png.
