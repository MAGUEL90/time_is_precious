# TIME IS PRECIOUS — GAMEPLAY AUTHORITY MAP

Status: TEMPLATE — NOT ACTIVE

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

Approved specifications must come from the designated design source of truth.
Design source path/link: `TBD`

## Agent-safe implementation examples
Given approved behavior, an agent may implement UI layout, display of existing stats, data binding, animation hooks, explanatory tooltips, sorting/filtering that preserves game rules, error/empty states, accessibility/presentation improvements, tests, debug visualization and boilerplate.

## Technical-looking changes that are actually design changes
Do not silently change cooldowns, timers, production speed, item weight/capacity, prices, wages, drop rates, resource requirements, worker efficiency, XP requirements, inventory capacity, quest rewards, spawn frequency, failure penalties, number of days, player-visible information that changes decision quality, or automation that removes a player trade-off.

## Proposal rule
The agent may propose alternatives. Protected design proposals must be clearly labeled and must not be implemented until explicitly approved.

## Canon conflict rule
If code, design docs, prior notes and task instructions disagree: preserve the working build, identify the conflict, follow a clear latest explicit human instruction when it resolves the issue, otherwise leave the disputed design unchanged.
