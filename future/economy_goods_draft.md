# Экономика поселений: 40 товаров и базовые цены — черновик E3

Базовые цены ниже взяты из последней записи каждого ID в `data/items.json` и выражены в серебре, как `MarketPricing.quote()`. Это цена справочника, не итоговая цена покупки или продажи: рынок меняет её по запасам, достатку поселения и навыку торговли. Производители, биомы и потребители — проектная схема, **не включённая пока в `SettlementEconomy`**. В коде сейчас производятся только абстрактная еда, шерсть, руда, камень, доски, ткань и железные слитки; все другие связи из таблицы требуют реализации и баланса.

Коды типов поселений: `village`, `town`, `city`, `fortress`. Биомы взяты из текущей глобальной карты: `plains`, `forest`, `mountains`, `desert`. Берег реки/озера — возможный модификатор местного производства, но не отдельный тип глобальной клетки. «Любой» означает, что ремесло не зависит напрямую от биома, если есть материалы. Ни одно производство не должно возникать без входных ресурсов.

| ID товара | Базовая цена, серебро | Производство: тип | Биом / условие | Основной спрос | Статус |
| --- | ---: | --- | --- | --- | --- |
| `wood` | 4 | village, town | forest; рубка | city, fortress | проект |
| `plank` | 8 | village, town, city | любой; wood | city, fortress | уже в симуляции |
| `stone` | 5 | village, town, fortress | mountains; карьер | city, fortress | уже в симуляции |
| `iron_ore` | 12 | town, fortress | mountains; шахта | town, city, fortress | уже в симуляции |
| `copper_ore` | 10 | town, fortress | mountains; шахта | town, city | проект |
| `coal` | 8 | town, fortress | mountains; шахта | town, city, fortress | проект |
| `tin_ore` | 10 | town, fortress | mountains; шахта | town, city | проект |
| `iron_ingot` | 28 | town, city, fortress | любой; iron_ore, топливо | кузницы всех типов | уже в симуляции |
| `bronze_ingot` | 24 | town, city | любой; copper_ore, tin_ore | кузницы всех типов | проект |
| `wool` | 4 | village | plains; овцы | town, city | уже в симуляции |
| `cloth` | 10 | town, city | любой; wool | village, town, city, fortress | уже в симуляции |
| `raw_leather` | 10 | village, town | plains, forest; скот/дичь | town, city, fortress | проект |
| `treated_leather` | 24 | town, city | любой; raw_leather | town, city, fortress | проект |
| `herb` | 6 | village | plains, forest | town, city, fortress | проект |
| `berries` | 4 | village | forest, plains | village, town | проект |
| `food_raw` | 8 | village, town | plains, forest; скот/дичь | town, city, fortress | проект |
| `cooked_food` | 18 | village, town, city | любой; food_raw, топливо | все типы | проект |
| `bread` | 12 | village, town, city | любой; flour, топливо | все типы | еда на рынке, рецепт отдельно |
| `bandage` | 15 | town, city, fortress | любой; cloth | все типы | проект |
| `medicine` | 35 | town, city | любой; herb | все типы | проект |
| `wheat` | 3 | village | plains; поля | town, city, fortress | проект |
| `flour` | 7 | village, town | любой; wheat, мельница | town, city, fortress | проект |
| `fish` | 6 | village, town | у реки/озера | все типы | проект |
| `stone_axe` | 20 | village, town | любой; stone, wood | village, town | предмет и рецепт есть |
| `stone_pickaxe` | 22 | village, town | любой; stone, wood | village, town | предмет и рецепт есть |
| `bronze_axe` | 48 | town, city | любой; bronze_ingot | village, town, city | предмет и рецепт есть |
| `bronze_pickaxe` | 52 | town, city | любой; bronze_ingot | village, town, fortress | предмет и рецепт есть |
| `iron_axe` | 75 | town, city, fortress | любой; iron_ingot | village, town, fortress | предмет и рецепт есть |
| `iron_pickaxe` | 85 | town, city, fortress | любой; iron_ingot | town, fortress | предмет и рецепт есть |
| `wooden_club` | 12 | village, town | любой; wood | village, town | предмет и рецепт есть |
| `stone_sword` | 24 | village, town | любой; stone, wood | village, town | предмет и рецепт есть |
| `bronze_sword` | 65 | town, city | любой; bronze_ingot | town, city, fortress | предмет и рецепт есть |
| `iron_sword` | 85 | town, city, fortress | любой; iron_ingot | town, city, fortress | предмет и рецепт есть |
| `iron_spear` | 110 | town, city, fortress | любой; iron_ingot, wood | town, city, fortress | предмет и рецепт есть |
| `hunting_bow` | 60 | village, town | forest; wood и тетива | village, town, fortress | предмет и рецепт есть |
| `arrow` | 2 | village, town | любой; wood, металл | village, town, fortress | предмет и рецепт есть |
| `iron_arrow` | 8 | town, city, fortress | любой; iron_ingot, wood | town, city, fortress | предмет и рецепт есть |
| `javelins` | 25 | village, town, fortress | любой; wood, наконечник | town, fortress | предмет и рецепт есть |
| `leather_armor` | 30 | town, city | любой; обработанная кожа | town, city, fortress | предмет и рецепт есть |
| `torch` | 6 | village, town, city | любой; wood, топливо | все типы | две записи ID; цена последней |

## Правило для реализации

Сначала добавлять отдельные запасы только для товаров, которые реально потребляют здания, игрок или караваны. Произведённое количество должно зависеть от рабочих, доступного сырья, биома и типа поселения. Потребление еды нельзя второй раз списывать через `bread`: сейчас `settlement.food` уже убывает по населению и на рынке показывается как хлеб. Для каждого нового товара нужна проверка баланса массы и стоимости рецепта; в `items_price_review.md` перечислены 90 действующих рецептов с наценкой вне целевых 20–50%. Повторные ID `torch`, `silver_coin`, `gold_coin` нужно разрешить до автоматической загрузки экономической таблицы.
