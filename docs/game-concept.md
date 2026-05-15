# Time is Precious - Game Concept

Source of truth for high-level game design decisions.

- Last updated: 2026-05-15
- Working version: v0.9 draft
- Focus: game idea, player experience, world logic, and long-term design direction.
- Separate note: implementation progress and coding notes should live outside this concept document.

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

The player does not become the strongest laborer.
The player becomes the person who makes time, people, knowledge, and systems work better.

## 2. World Premise

The city used to look rich, but its prosperity was unequal.
While elites enjoyed wealth and influence, lower-class citizens still suffered from debt,
poor living conditions, and lack of access to basic care.

That false prosperity eventually collapsed.

The player is a young person trying to restore the city, not just into a rich city again,
but into a livable and stable city.

This matters because many systems in the game are not only economic.
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

- **Early game:** the player often works manually.
- **Mid game:** the player balances manual work and delegation.
- **Late game:** the player wins through planning, systems, negotiation, forecasting, and city management.

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
- daily need supply
- treasury
- housing capacity
- production flow
- social stability

### P4. Smart Growth Over Raw Labor

The player can do many things manually, but long-term success should come from
good decisions, not repetitive effort.

### P5. Social Consequences Matter

The city is not just an economy machine.
Worker conditions, needs fulfillment, and trust in the city should shape how stable
or unstable the settlement becomes over time.

### P6. Guidance Through Forecast and Memory

The game can eventually guide the player through systems that feel alive:

- an Oracle-like forecast system that reads city conditions
- an advisor character that remembers player behavior and gives context-aware advice

This is a long-term identity direction, not an early MVP requirement.

## 5. Core Gameplay Loop

1. Check city needs, chapter goals, quests, and economic opportunities.
2. Decide what the player does manually and what gets delegated.
3. Assign workers, tools, and resources.
4. Let jobs and processes run over time.
5. Collect, use, sell, or reinvest outputs.
6. Maintain worker conditions and city stability.
7. Read forecasts, warnings, and NPC advice.
8. Unlock new systems, districts, professions, and story progress.

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

### Personality Direction

Gabbi is cheerful, stubbornly hopeful, clever, and sometimes moody.
She has seen poverty closely, so her optimism is not naive.
She wants the city to recover, but she does not fully trust prosperity that is built without care.

### Background Direction

Gabbi comes from a lower-class family shaped by debt, illness, and instability.
Her father may be rough, irresponsible, or trapped in debt.
Her mother died from sickness after the family could not afford proper care.

This background helps explain why Gabbi cares about ordinary citizens and why she can become
a useful early guide for the player.

### Important Rule

Gabbi is **not** a routine worker.
If she helps, it should be through:

- quest support
- event support
- story involvement
- special help tied to specific situations
- guidance for player decision-making

This keeps her role stable and prevents overlap between story presence and routine labor systems.

## 8. City Resource Layer

The city has its own shared resource pool, separate from the player's personal inventory.

### Early City Resources

- `food_supply`
- `clothing_supply`
- `treasury_shekel`
- `shelter_capacity`

### Food Supply

Food is treated as **supply points**, not as a simple count of food items.

This means:

- 1 loaf and 1 egg do not have to be equal.
- each food item can contribute a different amount of food supply.
- the city consumes food supply to fulfill citizens' daily food needs.

Example:

- a small food item may provide 1 food supply
- a more filling meal may provide 2 or more food supply

### Clothing Supply

Clothing is also treated as **supply points**, not as one exact outfit per citizen.

This represents wear, replacement, basic fabric availability, and the general ability of the city
to keep citizens properly clothed.

Higher-quality clothing can later provide:

- more clothing supply
- slower decay
- comfort bonuses
- satisfaction bonuses

### Treasury

City treasury is used for city-level development, wages, repairs, upgrades, and public decisions.

For MVP, the game does not need to track full personal wealth for every regular NPC.
That would make the simulation too heavy too early.

### Shelter Capacity

Shelter is treated as **housing capacity**, not consumable stock.

Shelter capacity means:

- how many citizens can be housed
- whether the city has enough living space
- a foundation for future housing quality

Shelter capacity is not consumed each day.
It is compared against population needs.

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
- satisfaction

### 9.1 Fixed Needs for All Regular NPCs

All regular NPCs share the same core needs in early game:

- Food
- Clothing
- Shelter

There is **no needs sensitivity difference** between regular NPCs in the current direction.
The differentiation should come from profession, level, tools, assignment, and satisfaction,
not from individual needs tuning.

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
- `satisfaction`

Possible later additions:

- `absence_risk`
- `theft_risk`
- `leaving_risk`
- `riot_risk`

## 11. Needs Fulfillment and Satisfaction

Needs fulfillment is checked through the city systems:

- food uses city food supply
- clothing uses city clothing supply
- shelter uses city shelter capacity

Satisfaction is the early emotional / social result of needs fulfillment.

### MVP Rule

- if all basic needs are fulfilled, satisfaction rises slightly
- if any basic need fails, satisfaction falls

Satisfaction should not immediately cause extreme outcomes.
It is a bridge system for future social consequences.

## 12. Needs Failure Escalation

Need failure should escalate gradually.
Do not jump directly to extreme behavior.

Recommended escalation:

1. satisfaction falls
2. output drops
3. reliability falls
4. workers reject assignments more often
5. absence / skipping work
6. theft
7. leaving the city
8. unrest
9. riot

For MVP, satisfaction and light output or reliability impact are enough.
Riot can come later after the basic worker loop is stable.

## 13. Work Output Rules

Work output should be affected by:

- the job being performed
- worker profession
- star level
- tool quality / suitability
- needs fulfillment
- satisfaction
- efficiency

### Output Direction

`final output = base job output x profession bonus x star bonus x tool bonus x needs multiplier x satisfaction multiplier x efficiency`

### Profession Flavor

- **Laborer:** better at general physical work
- **Crafter:** more stable output, potentially better material efficiency
- **Hauler:** better transport speed or carrying throughput
- **Farmer:** better farming speed and crop handling
- **Scavenger:** better salvage rate and lower risk in gathering uncertain materials

### Worker Team / Mastermind Composition

Long-term worker management should not only be about selecting the best single worker.
The stronger fantasy is assigning the right combination of workers to the right site.

A work site may eventually support multiple workers with different professions.
The correct mix can create team efficiency bonuses.

Example directions:

- **Farming site:** Farmer improves crop work, Hauler improves movement, Laborer supports physical tasks.
- **Mining site:** Laborer improves extraction, Hauler improves transport, Crafter helps tool handling.
- **Crafting site:** Crafter improves production, Laborer prepares inputs, Hauler supports supply movement.

This creates a "mastermind" style of play:

> The player wins by composing teams, not just by hiring stronger individuals.

This is not part of the earliest MVP.
The recommended progression is:

1. show worker list
2. show worker detail
3. assign one worker to a job or site
4. assign multiple workers to a site
5. add profession synergy bonuses

## 14. Wages and Control

The player controls:

- where workers are assigned
- what wages they receive
- what tools they use
- how labor is distributed across the city

Wages should mainly affect:

- willingness to work
- reliability
- retention
- satisfaction over time

Wages should **not** be the main direct source of output power.
Star level, tools, and fulfilled needs should matter more.

## 15. Shelter and Population Direction

Shelter is a basic need and a soft population constraint.

The player may eventually build housing on available land.
One house can support multiple citizens depending on its size and quality.

Possible early model:

- simple shelter gives basic capacity
- better housing increases capacity or quality
- housing quality can later affect satisfaction

Incoming groups of people should not be fully automatic.
The player should have a chance to accept or reject incoming groups.

For MVP:

- citizens can exist even if shelter is insufficient
- lack of shelter lowers satisfaction
- no individual rent or personal housing economy is required yet

## 16. Mid-Game Needs Expansion

Early game is intentionally simple:

- Food
- Clothing
- Shelter

Mid game can expand into:

- comfort
- household goods
- luxury goods
- education or knowledge access
- public safety

These should be layered in only after the early city loop is stable.

## 17. Player Development Direction

The player does not need multiple hard classes.
The current direction is closer to intellectual / managerial growth:

- Negotiator
- Strategist
- Investor
- Analyst
- Administrator

These are not separate characters, but growth directions that reinforce the fantasy
of rebuilding the city through smarter leadership.

## 18. Oracle Forecast and Advisor NPC

This is a long-term core feature direction.
It should not be built large during early MVP.

### 18.1 Oracle Forecast System

The Oracle Forecast System reads city data and predicts future risks or opportunities.

Example forecast topics:

- food shortage risk
- clothing shortage risk
- shelter shortage risk
- treasury pressure
- worker dissatisfaction trend
- demand for certain materials
- risk of failed contracts or delayed production

The Oracle understands the city as a system.
It sees numbers, trends, shortages, and time pressure.

### 18.2 Advisor NPC With Memory

The Advisor NPC reads the player's behavior and remembers important choices.

Example memory topics:

- the player ignored food shortages several times
- the player overbuilt housing before stabilizing food
- the player accepted too many citizens too quickly
- the player paid workers poorly
- the player repeatedly solved problems manually instead of delegating

The Advisor understands the player as a person.
It sees habits, repeated mistakes, and decision style.

### 18.3 Combined Identity

The strongest direction is the combination:

> Oracle sees city data.
> Advisor remembers player behavior.

Example:

> "Last time you focused too much on housing, food supply collapsed within two days.
> The Oracle now predicts another food shortage.
> My advice: pause mudbrick production and move two workers to food."

This can become one of the unique identities of **Time is Precious**:
a management RPG where the city remembers, warns, and responds intelligently.

### 18.4 MVP Boundary

Do not build the full system early.

First small version:

- Oracle reads 3 main resources: food, clothing, shelter
- Advisor remembers 3 to 5 important player events
- advice is simple, readable, and grounded in current city problems

## 19. Production and Storage Direction

The current design direction remains:

- jobs consume inputs and generate outputs
- outputs should not automatically become personal player loot
- workshop-oriented storage is preferred for production chains
- city supply is separate from player inventory

This supports chain-based gameplay:

- produce
- process
- store
- refine
- use / sell / reinvest

## 20. Current Design Priorities

### Priority A. Clarify NPC Identity

- keep unique NPCs focused on story / guidance / support
- keep regular NPCs focused on routine labor and simulation

### Priority B. Build City Resource Loop

- food supply
- clothing supply
- city treasury
- housing / shelter fulfillment

### Priority C. Build Worker Core Loop

- assign worker
- fulfill needs
- adjust satisfaction
- run jobs
- gain profession XP
- level up by star
- improve output with tools and fulfilled needs

### Priority D. Keep Scope Healthy

Do not overload the system too early with:

- too many needs
- too many hidden modifiers
- too many unique NPC exceptions
- full AI advice before city systems are readable
- riot-level consequences before the basic city loop is stable

## 21. Open Questions

These are still intentionally open:

- how exactly food supply values should be balanced per item
- how clothing quality and durability should affect clothing supply
- how shelter quality is represented in early prototype
- what exact formula connects wages to reliability and retention
- how tools are assigned and degraded in the regular worker loop
- which unique NPCs should become advisors, merchants, or quest anchors
- whether the Oracle is mystical, analytical, mechanical, or a blend of all three

## 22. Legacy and Multiple Ending Direction

**Time is Precious** should not have only one simple win condition.

The player can become wealthy, but the meaning of victory depends on how the city was rebuilt.
The central question is not only:

> Did the player become rich?

The stronger question is:

> What kind of city did the player create with the time, money, people, and systems available?

This direction prevents the game from feeling like a fixed economic checklist.
The player should be able to shape the city's future through repeated decisions, not through a single hard class selection.

### 22.1 Ending Evaluation Values

Endings should be determined by several long-term values:

- personal / city wealth
- city stability
- citizen satisfaction
- worker condition
- trust
- corruption / greed pressure
- delegation maturity
- time efficiency
- reliance on manual labor versus systems

The game can still have a clear main objective: rebuild the city and manage wealth wisely.
However, the result should reflect the player's method, not only the final amount of money.

### 22.2 Possible Ending Directions

#### Golden Steward Ending

The player achieves strong wealth, high city stability, high citizen satisfaction, and a mature delegation system.
The city becomes prosperous without repeating the old pattern of greed and neglect.

This is the ideal ending.
The player proves that wealth, care, and systems can grow together.

#### Rich but Rotten Ending

The player becomes very wealthy and the city treasury may look strong, but worker conditions, trust, and satisfaction are poor.
The city becomes productive, but cold and exploitative.

This ending reflects the old city's mistake.
The player wins economically, but fails morally and socially.

#### Modest but Stable Ending

The player does not maximize wealth, but the city survives with good stability, fulfilled basic needs, and decent trust.
This is not the richest outcome, but it is still a respectable recovery.

The city may not become golden, but ordinary people can live with dignity.

#### Merchant King Ending

The player focuses heavily on trade, contracts, market timing, treasury growth, and economic expansion.
The city becomes a commercial power.

This ending is not automatically bad.
Its tone depends on whether the player also maintains worker conditions and social stability.

#### People's Leader Ending

The player prioritizes citizen needs, wages, trust, housing, food, clothing, and social care.
Wealth may be moderate, but loyalty and public trust are high.

This ending should feel emotionally warm and human-centered.
The player becomes remembered as someone who rebuilt the city for its people.

#### Collapse Ending

The player repeatedly fails to maintain food, clothing, shelter, wages, or stability.
Satisfaction falls, reliability drops, workers leave, theft rises, unrest grows, and the city eventually collapses.

This ending should feel earned through ignored warnings, not sudden punishment.
The city should collapse gradually because the player failed to respond to visible signals.

#### Burnout Ending

The player works hard manually but fails to build strong delegation, production systems, or city-level planning.
The city may survive for a while, but it cannot scale.

This ending reinforces the title's meaning.
The player used effort, but failed to use time wisely.

### 22.3 Soft Player Identity Routes

The game should avoid forcing the player into hard classes at the beginning.
Instead, the player's identity can emerge from repeated decisions.

Possible soft routes:

- frequent negotiation and deal-making pushes the player toward a **Negotiator** identity
- frequent investment and treasury growth pushes the player toward an **Investor** identity
- frequent forecast reading and data-led planning pushes the player toward an **Analyst** identity
- frequent team composition and worker assignment pushes the player toward a **Strategist** identity
- frequent city infrastructure and system building pushes the player toward an **Administrator** identity
- frequent manual work without delegation can create a **Laborer-style fallback** identity

These routes do not need to lock the player out of other systems.
They are behavioral labels, advisor memory hooks, and ending influences.

### 22.4 Advisor and Oracle Support for Endings

The Oracle and Advisor systems can support multi-ending direction by warning the player about long-term patterns.

Example advisor reactions:

> "You keep solving every shortage with your own hands. That works today, but the city still has no system."

> "Your treasury is rising, but satisfaction is falling. That is how the old city looked before it collapsed."

> "Workers are loyal because you kept food, clothing, and shelter stable. You may not be the richest leader, but people trust you."

The Advisor should not only explain numbers.
The Advisor should help the player understand what kind of leader they are becoming.

### 22.5 Design Rule

Multiple endings should not feel random.
They should be the natural result of visible player behavior over time.

A good ending system for **Time is Precious** should answer three questions:

1. Did the player build wealth?
2. Did the player build a stable city?
3. Did the player use time, people, and power wisely?

## 23. Immediate Reference Rules

If future design choices feel messy, return to these rules first:

1. Unique NPCs are not routine workers.
2. Regular NPCs are the core workforce.
3. Early regular worker needs are fixed: Food, Clothing, Shelter.
4. Food and clothing use supply points, not raw item counts.
5. Shelter uses capacity, not consumable stock.
6. Worker satisfaction changes after needs are processed.
7. Worker growth comes from profession XP and star progression.
8. Leveling requires needs fulfillment.
9. City management is separate from personal inventory.
10. Long-term strength comes from systems, not from manual labor alone.
11. Oracle and Advisor systems are long-term identity features, not early MVP requirements.
12. Worker team composition is a long-term site-management feature, not an early Worker Tab requirement.
13. The game should support multiple ending directions based on how the city is rebuilt, not only on final wealth.
14. The player's identity should emerge from repeated behavior, not from a hard class selection at the start.
