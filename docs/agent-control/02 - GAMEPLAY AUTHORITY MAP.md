# TIME IS PRECIOUS — GAMEPLAY AUTHORITY MAP

Status: ACTIVE

Purpose: prevent implementation agents from accidentally becoming the game designer.

## Protected design domains
Human-controlled domains include:
- Core identity and Time ↔ Shekel trade-offs.
- Manual work versus delegation.
- City/community development and consequences.
- Worker hiring, professions, XP/stars, wages, needs, tools, efficiency and reliability.
- Prices, production costs, conversion ratios, scarcity, rewards and opportunity cost.
- Progression, unlocks, milestones, campaign pacing and win/lose conditions.
- Story, lore, dialogue meaning, character identity, quest outcomes, branching choices, Nightmare World narrative purpose and endings.

## Design source of truth
Primary approved design authority:
`docs/game-concept.md`

Related domain documents may refine presentation or character-specific details, but they must not override the high-level design source without an explicit Game Director decision.

Examples:
- `docs/characters/**` = character-specific canon details.
- `docs/game-concept-resolution.md` = display/presentation direction.
- `ROADMAP.md` = current implementation priority, not design authority.
- `ARCHITECTURE.md` = technical responsibilities, not gameplay authority.

## Agent-safe implementation examples
Given approved behavior, an agent may implement UI layout, display of existing stats, data binding, animation hooks, explanatory tooltips, sorting/filtering that preserves game rules, error/empty states, accessibility/presentation improvements, tests, debug visualization and boilerplate.

## Technical-looking changes that are actually design changes
Do not silently change cooldowns, timers, production speed, item weight/capacity, prices, wages, drop rates, resource requirements, worker efficiency, XP requirements, inventory capacity, quest rewards, spawn frequency, failure penalties, number of days, player-visible information that changes decision quality, or automation that removes a player trade-off.

## Proposal rule
The agent may propose alternatives. Protected design proposals must be clearly labeled and must not be implemented until explicitly approved.

## Canon conflict rule
If code, design docs, prior notes and task instructions disagree:
1. Preserve the working build.
2. Identify the conflict explicitly.
3. Follow the latest explicit Game Director instruction when it clearly resolves the conflict.
4. Otherwise leave the disputed design unchanged.
5. Do not use stale implementation behavior as evidence that design intent changed.

## Progress-vs-design rule
A feature may be implemented in code while `ROADMAP.md` still marks validation or integration as incomplete. That is not automatically a design conflict.

Use:
- `docs/game-concept.md` to answer what the game should do.
- `ROADMAP.md` to answer what is currently complete enough to prioritize or rely on.
- current source code to answer what implementation exists right now.
