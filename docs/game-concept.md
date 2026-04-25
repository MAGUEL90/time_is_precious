# Time is Precious - Game Concept

Source of truth for high-level design decisions.

- Last updated: 2026-04-26
- Working version: v0.7 draft
- Legacy reference: `KONSEP GAME (UPDATED v0.6).txt` is kept temporarily until this document is reviewed and accepted as the main design doc.

## 1. High Concept

**Title:** Time is Precious  
**Genre:** 2D Top-Down Management RPG / Delegation Sim  
**Platform target:** PC and Android  
**Engine:** Godot 4.5.x

### Elevator Pitch

A once-prosperous Mesopotamian city collapsed under greed, corruption, and careless power.
The player returns to rebuild it within a limited time window by managing time, money, workers,
production, and social stability.

The heart of the game is a constant tradeoff:

- spend **time** to save **money**
- spend **money** to save **time**

The player does not become the strongest laborer, but the smartest organizer of labor,
knowledge, opportunity, and long-term growth.

## 2. World Premise

The city used to look rich, but its prosperity was unequal.
While elites enjoyed wealth and influence, lower-class citizens still suffered from debt,
poor living conditions, and lack of access to basic care.

That false prosperity eventually collapsed.

The player is a young person trying to restore the city, not just into a rich city again,
but into a livable and stable city.

This matters because many systems in the game are not just economic.
They are also social:

- workers need to survive
- trust has to be earned
- prosperity must reach ordinary citizens
- city growth should not repeat the old pattern of corruption and neglect

## 3. Player Fantasy

The player's core fantasy is:

> I am not the strongest worker.  
> I am the person who makes time, money, systems, and people work better.

### Early / Mid / Late Direction

- **Early game:** the player often works manually
- **Mid game:** the player balances manual work and delegation
- **Late game:** the player wins through planning, systems, negotiation, and city management

## 4. Core Design Pillars

### P1. Time Economy

Time is the core resource.
Almost every action should be readable as a trade between time and something else.

### P2. Delegation-Centric Growth

The long-term power fantasy is not raw labor.
It is assigning the right people, tools, and systems to the right work.

### P3. City-Level Management

The player is not only managing personal inventory.
The player is also managing the city:

- workforce
- stock of daily needs
- treasury
- production flow
- social stability

### P4. Smart Growth Over Raw Labor

The player can do many things manually, but long-term success should come from
good decisions, not repetitive effort.

### P5. Social Consequences Matter

The city is not just an economy machine.
Worker conditions, needs fulfillment, and trust in the city should shape how stable
or unstable the settlement becomes over time.

## 5. Core Gameplay Loop

1. Check city needs, chapter goals, quests, and economic opportunities.
2. Decide what the player does manually and what gets delegated.
3. Assign workers and resources.
4. Let jobs and processes run over time.
5. Collect, use, sell, or reinvest outputs.
6. Maintain worker conditions and city stability.
7. Unlock new systems, districts, professions, and story progress.

## 6. NPC Structure

The game uses **two main NPC layers**.

### 6.1 Unique NPCs

Unique NPCs are for:

- story progression
- quests
- guidance
- emotional anchors
- special support in scripted or limited contexts

Unique NPCs are **not** routine workforce by default.
They should stay present and reliable in the world so they do not conflict with quests,
dialogue, or story events.

Some unique NPCs may be tied to economics directly, such as merchants or finance-oriented
characters, but that is a specific role, not the default rule.

### 6.2 Regular NPCs

Regular NPCs are the city's main workforce.
They are the systemic population layer that makes the city feel alive.

They can:

- receive routine work assignments
- level up in professions
- be affected by city-provided needs
- become less efficient if conditions are poor
- eventually refuse work, disappear, steal, or contribute to unrest if city management fails

## 7. Unique NPC Direction: Gabbi

Gabbi is the current reference model for a unique NPC.

### Core Role

- childhood friend of the player
- early guide
- social bridge to lower-class citizens
- story support character
- emotional anchor for the city's human cost

### Important Rule

Gabbi is **not** a routine worker.
If she helps, it should be through:

- quest support
- event support
- story involvement
- special help tied to specific situations

This keeps her role stable and prevents overlap between story presence and routine labor systems.

## 8. City Resource Layer

The city should have its own shared resource pool, separate from the player's personal inventory.

### Early City Resources

- `food_stock`
- `clothing_stock`
- `city_treasury_shekel`

### Shelter

Shelter is still a core need, but it should come from a **housing / capacity system**
rather than from a simple stack of shelter items.

So the early needs model becomes:

- food: fulfilled from city stock
- clothing: fulfilled from city stock
- shelter: fulfilled from housing capacity / living conditions

## 9. Worker System (Regular NPCs)

Regular workers are defined by:

- fixed needs
- profession
- profession experience
- profession star level
- efficiency
- reliability
- wages
- tools

### 9.1 Fixed Needs for All Regular NPCs

All regular NPCs share the same core needs in early game:

- Food
- Clothing
- Shelter

There is **no needs sensitivity difference** between regular NPCs in the current direction.
The differentiation should come from profession, level, tools, and assignment, not from
individual needs tuning.

### 9.2 Professions

Initial regular professions:

1. Laborer
2. Crafter
3. Hauler
4. Farmer
5. Scavenger

### 9.3 Star Progression

Each profession levels separately:

- 1-star
- 2-star
- 3-star

Experience should be tracked **per profession**, not globally.

Example:

- a worker may be `Farmer 3-star`
- but still be `Hauler 1-star`

### 9.4 Rule for Leveling

- successful work grants profession experience
- workers can only star up if their basic needs are fulfilled

This creates a strong design message:

> A city that takes care of its people creates better workers.

## 10. Worker Parameters

Current minimum direction for regular workers:

- `profession`
- `profession_xp`
- `profession_star`
- `efficiency`
- `reliability`
- `assigned_workplace`
- `wage`
- `food_fulfilled`
- `clothing_fulfilled`
- `shelter_fulfilled`

Possible later additions:

- `morale`
- `absence_risk`
- `riot_risk`

## 11. Work Output Rules

Work output should be affected by:

- the job being performed
- worker profession
- star level
- tool quality / suitability
- needs fulfillment
- efficiency

### Output Direction

`final output = base job output x profession bonus x star bonus x tool bonus x needs multiplier x efficiency`

### Profession Flavor

- **Laborer:** better at general physical work
- **Crafter:** more stable output, potentially better material efficiency
- **Hauler:** better transport speed or carrying throughput
- **Farmer:** better farming speed and crop handling
- **Scavenger:** better salvage rate and lower risk in gathering uncertain materials

## 12. Wages and Control

The player controls:

- where workers are assigned
- what wages they receive
- what tools they use
- how labor is distributed across the city

Wages should mainly affect:

- willingness to work
- reliability
- retention

Wages should **not** be the main direct source of output power.
Star level, tools, and fulfilled needs should matter more.

## 13. Needs Failure Escalation

Need failure should escalate gradually.
Do not jump directly to extreme behavior.

Recommended escalation:

1. output drops
2. reliability falls
3. workers reject assignments more often
4. absence / skipping work
5. theft
6. leaving the city
7. unrest
8. riot

For MVP, the first few steps are enough.
Riot can come later after the basic worker loop is stable.

## 14. Mid-Game Needs Expansion

Early game is intentionally simple:

- Food
- Clothing
- Shelter

Mid game can expand into:

- comfort
- household goods
- luxury goods

These should be layered in only after the early city loop is stable.

## 15. Player Development Direction

The player does not need multiple hard classes.
The current direction is closer to intellectual / managerial growth:

- Negotiator
- Strategist
- Investor
- Analyst
- Administrator

These are not separate characters, but growth directions that reinforce the fantasy
of rebuilding the city through smarter leadership.

## 16. Production and Storage Direction

The current technical direction remains:

- jobs consume inputs and generate outputs
- outputs should not automatically become personal player loot
- workshop-oriented storage is preferred for production chains

This supports chain-based gameplay:

- produce
- process
- store
- refine
- use / sell / reinvest

## 17. Current Prototype Foundations

The following foundations already exist in the prototype:

- player inventory with capacity / load logic
- world pickup items using item data
- workshop storage separated from player inventory
- job and process pipeline foundations
- time and weather hooks
- basic NPC dialogue and negotiation groundwork

These are implementation foundations, not final balancing.

## 18. Current Design Priorities

### Priority A. Clarify NPC Identity

- keep unique NPCs focused on story / guidance / support
- keep regular NPCs focused on routine labor and simulation

### Priority B. Build City Resource Loop

- city food stock
- city clothing stock
- city treasury
- housing / shelter fulfillment

### Priority C. Build Worker Core Loop

- assign worker
- fulfill needs
- run jobs
- gain profession XP
- level up by star
- improve output with tools and fulfilled needs

### Priority D. Keep Scope Healthy

Do not overload the system too early with:

- too many needs
- too many hidden modifiers
- too many unique NPC exceptions
- riot-level consequences before the basic city loop is stable

## 19. Open Questions

These are still intentionally open:

- how exactly city stock is distributed to regular NPCs each day
- how shelter quality is represented in early prototype
- what exact formula connects wages to reliability and retention
- how tools are assigned and degraded in the regular worker loop
- which unique NPCs, if any, should keep direct money-based interactions

## 20. Immediate Reference Rules

If future design choices feel messy, return to these rules first:

1. Unique NPCs are not routine workers.
2. Regular NPCs are the core workforce.
3. Early regular worker needs are fixed: Food, Clothing, Shelter.
4. Worker growth comes from profession XP and star progression.
5. Leveling requires needs fulfillment.
6. City management is separate from personal inventory.
7. Long-term strength comes from systems, not from manual labor alone.
