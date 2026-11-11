# MiniLife — World Implementation Directive

> This document is a strict implementation directive for an AI agent.
> Read every section fully before writing a single line of code.
> No improvisation. No additions. No removals. Implement exactly what is written.

---

## PART 1 — POLITICAL STRUCTURE

### 1.1 States

Implement exactly 8 states. No more, no less.

```
Type        Count   Notes
Kingdom       3     One dominant, two others
Duchy         3     Mid-tier power
County        2     Small but influential
```

**Kingdom 1 — The Dominant Kingdom**
- Largest territory, strongest military
- Culture: heavy cavalry, chivalric code, strict vassal hierarchy
- Controls the Papal Territory — this is their primary political weapon
- All other states form coalitions against them out of fear, not alliance
- Status: actively at war, pushing for unification under their banner

**Kingdom 2 and Kingdom 3**
- Leave names and details as `[TO BE DEFINED BY AUTHOR]`
- Do not invent lore for these — placeholder only

**Duchies 1-3 and Counties 1-2**
- Leave as `[TO BE DEFINED BY AUTHOR]`
- Implement the data structures but do not fill in lore

### 1.2 The Church — Papal State

- One religion, one God, one Pope
- No internal schism — the Church is unified
- The Papal Territory is physically adjacent to Kingdom 1's capital
- The Pope's blessing is required for any ruler to claim legitimate sovereignty
- Without blessing: a man with a sword and a crown
- With blessing: a lawful ruler, voice of heaven on earth
- The Pope can: grant or deny blessing, call mobilization, declare a crusade
- This is a political weapon, not just spiritual authority
- The Pope does NOT command armies directly
- Implement as a separate faction entity with unique interaction rules

---

## PART 2 — CITIES AND SETTLEMENTS

### 2.1 The Fortress City (The Count's City)

**Identity**
- Second largest city in the world after the capital
- Local map size: 1000x1000 tiles
- Controlled by The Count — the most influential lord in the world
- The only settlement that repelled the Imperial Army

**Current State (Month 1 after the fall)**
- Half the buildings are in ruins
- Walls are damaged but standing
- Population is sparse — the city is vast and mostly empty
- People are starving
- Few workers, few soldiers
- But: no one dares attack it

**The Count**
- Mid height, body like forged steel, mind like a scholar
- Personally commanded the defense, personally led the counterattack
- First impression: immediately clear he is a lord — his manner and speech draw respect
- External policy: open and warm — he has no need for enemies, his strength is his reputation
- Internal policy: spies and traitors are never forgiven, never pardoned
- Core paradox: most respected man in the world, fewest resources of any lord

**What the player can do here**
- Take restoration quests: repair buildings, gather food, bring workers
- These quests matter more than combat quests — this city needs hands, not swords
- High reputation here unlocks dialogue with The Count
- The Count does not leave the city

### 2.2 The Capital

- Largest city in the world
- Location of the Papal Territory and the Church
- Seat of the old Empire — now contested
- Do NOT define who controls it — leave as active conflict zone
- Implement as a special settlement type with unique faction tension rules

### 2.3 Standard Settlement Types

Implement the following settlement types. Each has a defined item/service availability profile.

```
Type            Available
Village         Food (cheap), basic tools, rumors, local quests
Town            Maps, supplies, workshops, mid-tier quests
Fortress        Weapons and armor (cheap), military quests, garrison NPCs
Free Settlement Neutral trading, no questions asked, refuge for fugitives
Ruins           Loot only, no services, enemy presence
Capital         Everything — but contested, dangerous, politically complex
```

### 2.4 Free Settlements

- Exist outside the lord and church system
- Each has its own rules and its own relationship with surrounding states
- Can trade with enemies of all factions — neutrality is their business model
- Can shelter fugitives without questions
- Player can do things here that are impossible inside any kingdom
- Do not assign permanent allegiance to any state

---

## PART 3 — LORE ENTITIES

### 3.1 The Wandering Armies

**Who they are**
- Former Imperial military units, still organized, still disciplined
- Led by veteran commanders — not bandits, real armies with structure
- They destroyed what they served and cannot return

**Why they wander**
- New kings will not accept them — they are living symbols of the old regime
- Common people hate them
- Lords fear them
- Peaceful life is no longer possible for the commanders — they know this

**Commander types — implement as 3 distinct archetypes**

```
Archetype       Behavior
BROKEN          Raids and takes whatever he can. No negotiation. Hostile on sight.
DISCIPLINED     Maintains order in his troops. Avoids unnecessary violence.
                Can be reasoned with under specific conditions.
SEEKING         Secretly wants a way out. Will respond to the right player.
```

**Late-game unique event — COMMANDER ENCOUNTER**

Trigger conditions (ALL must be true):
- Player has Tier 5 armor (full set)
- Player combat skill >= threshold (define threshold as constant)
- Player speech skill >= threshold
- Player leadership skill >= threshold
- Player initiates encounter with a DISCIPLINED or SEEKING commander

Event flow:
1. Commander recognizes the player as a worthy opponent
2. Dialogue opens — negotiation or challenge
3. Player can challenge to single combat
4. If player wins:
   - Option A: Take command of the army → player becomes a military power
   - Option B: Disband the army → pay each soldier enough for a new life
5. Each option has permanent world consequences — implement both

### 3.2 Merchants

- Travel between settlements despite danger
- Solo or small groups
- Carry: maps, location tips, materials, tools
- Information is a commodity — maps cost money, tips cost money
- Implement merchant as a special NPC type with inventory: maps + tips + goods
- Tips reveal specific POI locations on the fog of war map

### 3.3 Guilds — Post-Collapse State

- Guilds existed under the Empire
- After the collapse: not yet reformed
- Month 1: only early seeds exist — a group of mercenaries taking contracts, traders banding together
- No formal guild structure yet
- Player can interact with these proto-guilds
- Future consideration: player can help establish a guild → massive influence gain
- Do NOT implement full guild system now — implement the proto-guild NPCs and the hook

---

## PART 4 — PLAYER PROGRESSION AND QUESTS

### 4.1 Starting Conditions

```
Item            Count
Stone pickaxe     1
Stone axe         1
Money             0
Reputation        0
Honor             0
Skills            all at minimum
```

Player is nobody. No backstory. No special origin. No chosen one narrative.

### 4.2 First Days — Survival Loop

- Forest, resource gathering, basic survival
- No human contact yet
- Player discovers the world through interaction, not cutscenes

### 4.3 First Story Event — THE SOLDIERS

Trigger: after N days in the wilderness (define N as a constant, suggested 3-5)

Event:
- A military unit passes near the player
- They do not explain who they are or who they serve
- They order the player to appear at the nearby village
- Player has no real choice — comply or die

Implementation notes:
- Do not reveal the faction of these soldiers at this point
- This is intentional — the player learns later
- Soldiers leave after delivering the order

### 4.4 Village Quest Chain

**NPC: Village Elder**
- Old man, no combat skill, has authority and management experience
- Needs workers and fighters — takes what he can get

**Quest categories:**

```
Category        Reward
Resource        Money
Combat          Money + Village Reputation
Pursuit         Money + Village Reputation + Speech XP
```

**Quest chain structure:**
- 3-5 quests available at start
- After completion: cooldown before new quests appear
- Player is free to leave at any time — no forced stay
- Village Reputation carries over when player returns later

**XP from village quests:**
- Combat quests → combat skills
- Pursuit quests → speech + athletics
- All quests → general experience

### 4.5 Reputation System

Implement TWO separate reputation tracks:

**Track 1: Settlement Reputation**
- Per-settlement value
- Increased by completing quests for that settlement
- Unlocks: better quest rewards, access to restricted NPCs, discounts

**Track 2: World Reputation**
- Global value
- Increased by significant actions visible to the wider world
- High world reputation: low-tier bandits avoid the player
- Affects how lords and important NPCs receive the player on first meeting

### 4.6 Honor System

Honor is NOT settlement reputation. Honor is character.

Rules:
- Cannot be gained through simple tasks or casual conversation
- Gained through meaningful decisions with real consequences
- Lost through betrayal, cowardice, or dishonorable acts
- Reference model: Arthur Morgan in Red Dead Redemption 2
- Honor affects: NPC dialogue options, quest availability, some faction reactions

### 4.7 Status System

Implement a status ladder. Each status unlocks new interaction categories.

```
Status          Unlock condition
Nobody          Start
Known           First quest chain completed
Respected       Settlement reputation threshold reached
Notable         World reputation threshold reached
Vassal          Pledge to a lord (irreversible — world sees this immediately)
Champion        Win a significant combat event
Commander       Complete the Commander Encounter event (Part 3.1)
```

**Vassal status is permanent and immediately visible.**
Any settlement belonging to an enemy faction will know the player's allegiance
on first arrival. No hiding it. This is by design — make the pledge meaningful.

---

## PART 5 — INFORMATION AND EXPLORATION

### 5.1 Fog of War

- Three states: UNEXPLORED / VISITED / VISIBLE
- Already implemented — do not change the system

### 5.2 Map Items

- Maps are purchasable from merchants and some settlement vendors
- Each map reveals a specific area of the fog of war
- Maps are specific — not "reveal everything", but "reveal this region"
- Implement as inventory items with an on-use effect: reveal tiles

### 5.3 Tips and Rumors

- Purchasable from merchants
- Each tip marks a specific POI on the map
- POI types: ruins, hidden settlements, resource deposits, enemy camps
- Tips are one-time items — consumed on use

### 5.4 Information Economy

```
Source          What they sell
Merchant        Maps, tips, goods
Village Elder   Local rumors (free, low quality)
Tavern NPC      Mid-range tips (cost money)
Important NPC   High-value information (requires reputation or quest)
```

---

## PART 6 — WORLD STATE AT GAME START

The following conditions are TRUE at the moment the player enters the world.
Implement these as the initial world simulation state.

```
Condition                                           Value
Months since Empire fell                            1
Imperial information spread                         Incomplete — remote villages may not know
Belief that Emperor is dead                         Low — most people don't believe it yet
Active wars between states                          YES
Wandering armies present                            YES
Regular armies avoiding Imperial remnants           YES
Kings seeking Papal recognition                     YES
Guilds reformed                                     NO — proto-guilds only
Factions stable                                     NO — weak and shifting
Roads safe for travel                               NO — bandits and wandering armies present
Merchants traveling                                 YES — small groups, dangerous routes
Free settlements operating                          YES
```

---

## PART 7 — IMPLEMENTATION CONSTRAINTS

### Non-negotiable rules

1. Do not invent lore not present in this document
2. Placeholder fields marked `[TO BE DEFINED BY AUTHOR]` must remain as placeholders
3. The player starts as nobody — no special traits, no backstory
4. The Vassal status is irreversible and immediately visible world-wide
5. The Commander Encounter event requires ALL trigger conditions — no shortcuts
6. Honor and Reputation are separate systems — never merge them
7. Free settlements have no permanent faction allegiance — ever
8. The Church has one Pope, one religion, no schism — do not add complexity here
9. The capital is a contested zone — do not assign it to any faction at game start
10. Merchants travel despite danger — do not make them stationary

### Data structures to implement

```
Faction         { id, name, type, territory[], diplomacy{}, ideology }
Settlement      { id, type, faction_id, reputation_map{}, quest_pool[], status }
Commander       { id, archetype, army_size, location, encounter_triggered }
Merchant        { id, inventory[], route[], current_location }
Quest           { id, type, settlement_id, reward{money, rep, xp}, status }
PlayerStatus    { settlement_rep{}, world_rep, honor, status_ladder, vassal_id }
Map             { item_id, reveals_region }
Tip             { item_id, marks_poi_id }
```

### Quest chain constraint

Every quest chain must follow this structure:

```
1. Hook       — something pulls the player in (order, request, discovery)
2. Action     — player does the thing
3. Resolution — world reacts, player gets reward + consequence
4. Ripple     — something changes in the world as a result (even if small)
```

The Ripple is mandatory. Every quest must change something, even if minor.
A fetch quest that changes nothing is not acceptable.

---

## END OF DIRECTIVE

Implement exactly this. When something is marked `[TO BE DEFINED BY AUTHOR]` — stop and leave it empty.
When something is ambiguous — implement the most conservative interpretation.
Do not ask for confirmation mid-implementation. Complete the full directive in one pass.
