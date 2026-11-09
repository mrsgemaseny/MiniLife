# Transparent fauna sprites

Prepared with built-in imagegen from the existing domestic and predator reference sheets. Two PNG atlases, eighteen named `.tres` regions, consumed by `AnimalRig` for animals and beasts in `EnemyBase`.

Prompt set: preserve the existing simple cartoon animals, colors, silhouettes and right-facing poses; remove all text and white background; actual transparent alpha including gaps between limbs; retain opaque white animal markings; 3×3 cells, no shadows, no realism. Domestic order: cow, sheep, pig, chicken, horse, unladen donkey, deer, moose, hare. Wild order: wolf, direwolf, bear, boar, fox, dog, cat, spider, fish.

`tools/prepare_fauna_art.gd` creates named AtlasTexture regions. It selects the main connected silhouette inside each cell to omit fragments from neighbouring rows. Runtime draws cached textures with preserved aspect ratio; no pixel processing occurs during gameplay.
