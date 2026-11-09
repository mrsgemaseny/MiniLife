# MiniLife expansion art

Generated using built-in imagegen. Six transparent PNG source sheets, 92 named AtlasTexture resources in `regions/`. IDs and measured pixel regions: `manifest.json`.

Common prompt: game-ready isometric medieval colony survival props; orthographic slightly top-down view; simplified cartoon cutouts; bold dark organic outlines; earthy muted palette; broad 2–3 tone shading; readable at 48–64 pixels; no realistic microtextures, text, grid, terrain bases, or cast ground shadows; isolated complete objects in equal cells with transparent margins.

Prompt sets, objects in row-major order:

- town_buildings, 4×3: thatched cottage; green-awning merchant shop; stone smithy; red-canopy market stall; raised granary; stone watchtower; burgundy-roof tavern; stable; roofed well; covered caravan wagon; bell shrine; wooden gatehouse.
- trade_props, 4×4: cargo crates; sealed barrels; grain sacks; burgundy cloth bolts; trader chest; apples; bread; salted fish; cargo handcart; tent bundle; travel packs; brass scales; bronze stack; iron stack; tied planks; wool bales.
- camp_props, 4×4: expedition tent; fur bedroll; stone-ring campfire; cooking tripod; meat drying rack; waterskin and cup; firewood; chopping block; fishing kit; medicine chest; blank signpost; map and compass; lean-to; herb basket; toolkit stool; adventurer chest.
- ruin_props, 4×4: broken arch; broken column; cracked stone chest; broken cart; collapsed well; crumbling wall; broken pottery; sarcophagus; old signpost; abstract standing stone; stone hatch; ruined tower; discarded armor; old vault; broken weapon rack; bridge fragment.
- farm_props, 4×4: chicken coop; trough; hay bale; gate; wheat sheaves; beehive; rain barrel; grain quern; spinning wheel; loom; linen rack; kindling block; produce; seedling pots; wattle fence; wheelbarrow.
- workshop_props, 4×4: anvil; bellows; crucible; charcoal bucket; smith tools; stitching frame; tanning rack; sewing basket; masonry blocks; herb mortar; drying herbs; medicine jars; carpenter chest; sawhorse; pottery; cauldron.

Workshop follow-up edit: remove white background and all cast shadows; preserve all sixteen objects, colors, layout, positions and size; transparent alpha between objects and inside frames; preserve outlines.

These are prepared art resources, not additional gameplay mechanics. Source sheets are intentionally retained; load individual `.tres` resources and preserve their aspect ratio when placing them.
