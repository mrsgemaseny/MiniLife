# LOCKED FILES & PROTECTED ASSETS — MINILIFE
Дата фиксации: 2026-11-04

СТРОЖАЙШИЙ ЗАПРЕТ: Файлы из данного реестра категорически запрещено удалять, откатывать, перезаписывать или произвольно модифицировать. Они представляют собой зафиксированный визуальный и программный канон проекта, утвержденный пользователем.

---

## 1. СТРОГО ЗАФИКСИРОВАННЫЙ ВИЗУАЛЬНЫЙ КАНОН И АРТ-РЕФЕРЕНСЫ
Категорически запрещено изменять, удалять или перегенерировать:

- `ART_STYLE_REFERENCE.md` — документ-спецификация визуального канона брони и снаряжения.
- `assets/references/armor_style_reference.png` — утвержденный графический эталон стиля снаряжения (сетка 3x3).
- `output/art_refresh_2026-11-04/` — архив генерации, манифест связок (`manifest.json`), бэкапы (`backup/`) и лог интеграции (`integration.log`).

---

## 2. ЗАФИКСИРОВАННЫЕ СПРАЙТЫ ЭКИПИРОВКИ (73 PNG)
Путь: `assets/sprites/items/`
Все 73 спрайта отрисованы в едином утвержденном стиле (160x160 RGBA с прозрачностью). Запрещено заменять их процедурными заглушками или другими версиями:

### Оружие ближнего боя (Melee):
1. `stone_sword.png`
2. `stone_dagger.png`
3. `stone_axe.png`
4. `wooden_club.png`
5. `wooden_spear.png`
6. `spear.png`
7. `bronze_sword.png`
8. `bronze_dagger.png`
9. `bronze_axe.png`
10. `bronze_spear.png`
11. `iron_sword.png`
12. `iron_dagger.png`
13. `iron_axe.png`
14. `iron_spear.png`
15. `war_hammer.png`
16. `iron_war_pick.png`
17. `steel_sword.png`
18. `steel_dagger.png`
19. `steel_axe.png`
20. `steel_war_pick.png`

### Оружие дальнего боя и боеприпасы (Ranged & Ammo):
21. `primitive_bow.png`
22. `hunting_bow.png`
23. `crossbow.png`
24. `heavy_crossbow.png`
25. `javelins.png`
26. `arrow.png`
27. `bronze_arrow.png`
28. `iron_arrow.png`
29. `iron_bolt.png`
30. `steel_arrow.png`

### Инструменты и быт (Tools):
31. `stone_pickaxe.png`
32. `bronze_pickaxe.png`
33. `iron_pickaxe.png`
34. `steel_pickaxe.png`
35. `torch.png`
36. `fishing_rod.png`
37. `shears.png`

### Щиты (Shields):
38. `wooden_shield.png`
39. `iron_shield.png`

### Шлемы и головные уборы (Head Armor):
40. `wool_hood.png`
41. `leather_helmet.png`
42. `bronze_helmet.png`
43. `chainmail_coif.png`
44. `iron_helmet.png`
45. `steel_helmet.png`

### Нательный слой и одежда (Underarmor / Clothing):
46. `wool_shirt.png`
47. `gambeson.png`
48. `simple_chainmail.png`
49. `quality_clothing.png`
50. `arming_doublet.png`

### Основная броня корпуса (Chest / Main Armor):
51. `leather_armor.png`
52. `boiled_leather_cuirass.png`
53. `leather_lamellar.png`
54. `bronze_cuirass.png`
55. `bronze_lamellar.png`
56. `iron_hauberk.png`
57. `iron_lamellar.png`
58. `iron_scale_armor.png`
59. `iron_armor.png`
60. `iron_plate_armor.png`
61. `iron_brigandine.png`
62. `steel_cuirass.png`
63. `steel_brigandine.png`
64. `steel_plate_armor.png`

### Защита ног и обувь (Legs & Boots):
65. `wool_wraps.png`
66. `leather_greaves.png`
67. `bronze_greaves.png`
68. `iron_greaves.png`
69. `steel_greaves.png`
70. `leather_boots.png`
71. `bronze_boots.png`
72. `iron_boots.png`
73. `steel_boots.png`

---

## 3. ЗАЩИЩЕННЫЕ КОМПОНЕНТЫ И ЛОГИКА (`scripts/`)
Запрещено удалять, нарушать сигнатуры или ломать изоляцию следующих модулей:

- `scripts/components/consumable_use.gd` — логика потребления еды/зелий с защитой от утери пустой бутыли (`empty_bottle`) при переполнении инвентаря.
- `scripts/components/item_action.gd` — компонент прогресса длительных действий с предметами.
- `scripts/entities/player.gd`:
  - Механика фокуса цели по ЛКМ (`_locked_target`).
  - Механика автодоводки к цели (`_attack_order_movement`).
  - Проверка блокировки действий (`status_effects.is_action_blocked()`).
  - Отрисовка маркерного кольца вокруг захваченного врага в `_draw()`.
- `scripts/systems/combat_system.gd` — фильтрация ударов по `ordered_target`.
- `scripts/components/status_effects.gd` — метод `is_action_blocked()`.
- `scripts/ui/item_icon_factory.gd` — маппинг всех 73 утвержденных текстур.

---

## 4. ЗАЩИЩЕННЫЕ КОНФИГУРАЦИИ ДАННЫХ И ДОКУМЕНТАЦИЯ
- `data/items.json`:
  - Запись `iron_brigandine` (Т4).
  - Записи линеек обуви (`leather_boots`, `bronze_boots`, `iron_boots`, `steel_boots`).
- `data/recipes.json`:
  - Рецепт `forge_iron_brigandine`.
  - 4 рецепта крафта обуви.
- `data/tech_tree.json`:
  - Привязка разблокировки бригантины и обуви к веткам технологий.
- `ITEMS_CATALOG.md` — зафиксированные статьи о бригантине и обуви.
- `COMBAT_SYSTEM.md` — зафиксированные пункты о принудительном фокусе цели (`ordered_target`).
- `journal/2026-11-04/minilife.md` — подтвержденный лог аудита и интеграции.
