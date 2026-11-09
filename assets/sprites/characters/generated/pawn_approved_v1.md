# Approved pawn implementation

User-approved source: exec-dbf2d59b-83c2-46b3-a54b-3dd285c1a6c6.png, copied intact to pawn_approved_steel_v1.png. Four frames front/right/back/left. Approval applied to the reference image, not every later variant. Built-in imagegen was used to create the source; no API/CLI fallback.

Runtime: RasterPawnArt renders the complete approved frame, preserving aspect ratio, for steel armet + steel cuirass/plate. Other combinations use separate drawn layers. Old programmatic FlatPawnArt is retained but inactive. Source PNGs for existing inventory items are untouched.

New pawn_bodies_metal_v1.png: seven rows, four views per row. Final prompt specification: use the approved source as exact painterly style and compact short torso silhouette, narrow natural waist, small relaxed shoulders, short fauld, no bulging barrel/long abdomen; headless bodies only, NO arms/hands/legs/feet; consistent neckline and hem; front/right/back/left. Rows: short iron mail, long mail hauberk with beige sleeve edges, bronze anatomical cuirass, smooth riveted iron breastplate, rectangular riveted iron plate on brown foundation, steel chevron cuirass, steel plate body without arms/gauntlets. References: approved source + bronze_cuirass.png + iron_plate_armor.png + steel_plate_armor.png. True alpha, no text/grid/background/shadow. Source generated as exec-88911f35-a398-4294-b548-4a0c78bbd916.png.

Soft/scale attempts and their background-extraction revisions were rejected because they retained brown backgrounds. Not copied into runtime assets. Their replacement artwork is still pending; existing transparent body sheets remain in use for those types.

Measured frames in wearable_regions_v3.json are rebuilt by tools/build_wearable_regions.gd. This authoring-only script reads source PNGs and is not shipped as runtime logic. Preview: output/wearable_player_preview.png.
