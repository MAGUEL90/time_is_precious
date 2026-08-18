# ROADMAP - Time is Precious

Last updated: 2026-08-17

## Purpose of This Document

`ROADMAP.md` is the **single source of truth for current development position, priority, and next work**.

If you or Codex need to answer **"Where are we now, and what should we work on next?"**, start here.

Other documents have different jobs:

- `docs/game-concept.md` = design source of truth: what the game should become.
- `ROADMAP.md` = progress source of truth: where development is now and what comes next.
- `DEVLOG.md` = merged implementation history and playable snapshots.
- `ARCHITECTURE.md` = technical responsibilities and system boundaries.
- `docs/root-branch-map.md` = technical domain / Git branch map, not a progress tracker.
- `DEMO_DISTRIBUTION.md` = demo rollout strategy after the prototype is ready.

Do not use an old PR list, branch list, or technical root map as the main indicator of current progress.

## Development Principle

Build a small playable prototype first.

Do not expand into large systems before the core loop is stable, readable, repeatable, and testable without developer help.

Long-term progression should also avoid becoming fully deterministic. Controlled variation can be introduced after the basic loop is stable.

# Current Position

The project is currently in **Technical Prototype -> Playable Loop Integration**.

The main objective is to connect the systems that already exist into one complete daily gameplay loop rather than adding unrelated major systems.

```text
TIME IS PRECIOUS
|
|-- 0. GAME VISION / DESIGN
|   `-- Game Concept                                  [ACTIVE DESIGN / STABLE FOUNDATION]
|
|-- 1. PLAYABLE PROTOTYPE                            [CURRENT PHASE]
|   |
|   |-- A. Daily Player Loop
|   |   |-- Player home starting scene               [DONE]
|   |   |-- Home <-> city transition                 [DONE]
|   |   |-- World time continuity                    [DONE]
|   |   |-- Hunger / Fatigue / Focus                 [MVP DONE]
|   |   |-- Sleep                                    [MVP DONE]
|   |   |-- Collapse / Nightmare                     [MVP DONE]
|   |   `-- Full-loop balance and validation         [IN PROGRESS]
|   |
|   |-- B. Core Production Loop                      [MAIN BLOCKER]
|   |   |-- Inventory / item handling                [DONE]
|   |   |-- Workshop deposit / withdraw              [DONE]
|   |   |-- Worker assignment                        [DONE - PROTOTYPE]
|   |   |-- Start mudbrick job                       [DONE]
|   |   |-- Produce wet_mudbrick                     [DONE]
|   |   |-- Player-facing claim / continue flow      [PENDING]
|   |   |-- Dry wet_mudbrick                         [PENDING]
|   |   |-- Produce sun_dried_mudbrick               [PENDING]
|   |   `-- Use final output for progression         [PENDING]
|   |
|   |-- C. Population / Worker Layer
|   |   |-- Citizen generation                       [DONE - PROTOTYPE]
|   |   |-- Immigration accept / reject              [DONE - PROTOTYPE]
|   |   |-- Visible city citizens                    [DONE - PROTOTYPE]
|   |   |-- Worker assignment                        [DONE - PROTOTYPE]
|   |   |-- City daily needs loop                    [PARTIAL / PENDING BALANCE]
|   |   `-- Citizen -> applicant -> hired worker     [PENDING]
|   |
|   |-- D. Player-Facing Clarity
|   |   |-- Inventory UI                             [DONE - PROTOTYPE]
|   |   |-- Gameplay HUD                             [DONE - PROTOTYPE]
|   |   |-- Workshop UI                              [DONE - PROTOTYPE]
|   |   |-- Failure / missing-resource feedback      [IN PROGRESS]
|   |   `-- Production state clarity                 [IN PROGRESS]
|   |
|   `-- E. Persistence
|       |-- Runtime state across scene changes       [DONE]
|       `-- Real save / load to disk                 [PENDING]
|
|-- 2. INTERNAL PLAYTEST                             [NOT READY YET]
|   |-- Complete daily loop without manual setup
|   |-- Repeatable production loop
|   |-- Condition / Sleep / Focus tuning
|   `-- Internal playtest checklist
|
|-- 3. VERTICAL SLICE                                [LATER]
|   |-- Consistent presentation
|   |-- Representative gameplay loop
|   `-- Stable test build
|
`-- 4. DEMO DISTRIBUTION                             [LATER]
    |-- One Percent Studio website                   [PRIMARY HUB]
    |-- itch.io                                      [SECONDARY TEST CHANNEL]
    |-- Steam Playtest / Steam Demo                  [LATER]
    `-- Optional mirrors / discovery channels        [LATER]
```

## You Are Here

The project is **not blocked by lack of systems**.

The current blocker is that the existing systems are not yet connected into one complete, repeatable player-facing loop.

The most important incomplete chain is:

```text
Clay / straw / water
-> Player Inventory
-> WorkshopStorage
-> Assign Worker
-> Start Mudbrick Job
-> wet_mudbrick
-> CLAIM / CONTINUE PROCESS          <- CURRENT WORK AREA
-> Drying
-> sun_dried_mudbrick
-> Visible / usable progression
```

Until this chain is complete, avoid starting another large production chain or major management feature.

# Immediate Priority Stack

Work from top to bottom. Do not skip downward unless a blocker requires it.

## Priority 1 - Finish Mudbrick Output Chain

- [ ] Make `wet_mudbrick` claim / continue-process flow fully player-facing.
- [ ] Make drying process readable and usable without manual debugging.
- [ ] Produce final `sun_dried_mudbrick` through the normal player flow.
- [ ] Confirm final output can be seen, stored, and used for visible progression.

**Exit condition:** the mudbrick loop can be completed repeatedly from inputs to final output without developer intervention.

## Priority 2 - Validate the Complete Daily Loop

Validate this as one continuous play session:

```text
Wake at home
-> Enter city
-> Gather / manage resources
-> Assign work
-> Run production
-> Manage Hunger / Fatigue / Focus
-> Advance time
-> Return home
-> Sleep
-> Continue into next day
```

- [ ] Confirm no manual setup is required between steps.
- [ ] Confirm scene transitions preserve intended runtime state.
- [ ] Confirm Sleep and Collapse rules do not break the day loop.
- [ ] Confirm worker / workshop state remains understandable throughout the day.

**Exit condition:** one full in-game day feels like a coherent game loop rather than a collection of test systems.

## Priority 3 - Clarity and Failure Feedback

- [ ] Missing materials are explained clearly.
- [ ] Full inventory is explained clearly.
- [ ] Full workshop storage is explained clearly.
- [ ] Active / finished jobs are visually understandable.
- [ ] Player knows what to do after `wet_mudbrick` is produced.

**Exit condition:** a tester can understand what failed and what to do next without reading debug output.

## Priority 4 - Condition and Sleep Tuning

The systems already exist at MVP level. This is a tuning task, not a reason to rebuild them from scratch.

Tune:

- Hunger drain.
- Fatigue growth.
- Focus behavior and costs.
- Sleep duration and recovery.
- Once-per-day Sleep rule.
- Collapse / Nightmare consequence severity.

**Exit condition:** working too long has a meaningful cost, Sleep is valuable but not exploitable, and condition management supports the time-economy theme.

## Priority 5 - Save / Load Persistence

Only after the runtime daily loop is stable:

- [ ] Player conditions.
- [ ] Sleep usage / day state.
- [ ] Inventory.
- [ ] Citizens / workers.
- [ ] Workshop / production state as required.
- [ ] Progression values.

**Exit condition:** the playable prototype can be safely stopped and resumed.

## Priority 6 - Internal Playtest

- [ ] Create a short internal playtest checklist.
- [ ] Test the daily loop from a clean start.
- [ ] Record blockers, confusion, exploits, and balance problems.
- [ ] Fix loop-breaking problems before adding scope.

# Phase Status

## Phase 0 - Foundation Review

**Status: Mostly complete for the current prototype.**

Core foundations already exist or are partially implemented:

- ItemDatabase.
- Inventory and weight handling.
- WorkshopStorage.
- WorkManager.
- ProcessManager.
- Player interaction.
- World time.
- Citizen / immigration prototype.
- Player condition systems.
- Home / city scene flow.

Do not reopen this phase broadly unless a concrete blocker appears.

## Phase 0.5 - Playable Loop Stabilization

**Status: ACTIVE - THIS IS THE CURRENT DEVELOPMENT PHASE.**

Goal:

Connect existing systems into a readable, repeatable player-facing loop.

Main remaining blocker:

`wet_mudbrick -> claim / continue -> drying -> sun_dried_mudbrick -> progression`

## Phase 1 - Core Loop Prototype

**Status: In progress.**

Success criteria:

- Player can acquire resources.
- Player can store / move resources.
- Player can assign work.
- Work consumes correct inputs.
- Work generates output.
- Output can continue into the next production step.
- Final output creates visible progression.
- The loop is repeatable.

Phase 1 is not complete until the final output has an actual gameplay purpose.

## Phase 2 - Population and Worker Separation

**Status: Prototype partially implemented; not the main blocker.**

Design rule remains:

```text
Migrant
-> accepted resident / citizen
-> eligible applicant
-> hired worker
-> assigned / working
```

Population status and employment status must stay separate.

Current prototype supports citizen generation, immigration decisions, visible citizens, and worker-related systems. Daily city needs, persistence, and the complete citizen-to-worker flow still need further work.

Do not let Phase 2 expansion delay completion of the production / daily loop.

## Phase 2.5 - Controlled Variation Layer

**Status: Backlog.**

Long-term variation may include:

- migrant arrival variation
- applicant quality variation
- resident traits
- opportunity timing
- small production / needs-pressure variation

Randomness must remain readable and influenced by player decisions.

## Phase 3 - Prototype Asset Pass

**Status: Ongoing support work, not the main blocker.**

Use enough consistent art to make the prototype readable. Do not wait for final assets before validating gameplay.

## Phase 4 - Basic UI Pass

**Status: Partially implemented.**

Inventory, HUD, dialogue, and workshop interfaces exist at prototype level. Continue UI work when it directly improves the current playable loop.

## Phase 5 - Save / Load

**Status: Queued after loop stabilization.**

Real persistence should begin after the runtime daily loop is stable enough that the saved state model is unlikely to change every session.

## Phase 6 - Internal Playtest

**Status: Not ready.**

Entry gate:

- complete mudbrick chain
- coherent daily loop
- readable failure feedback
- basic condition tuning
- no developer-only setup required

## Phase 7 - Vertical Slice

**Status: Later.**

A vertical slice should represent the intended quality and identity of the game, not merely prove that systems technically run.

## Phase 8 - Demo Distribution

**Status: Later; planning exists, execution waits for readiness.**

Primary demo hub:

- **One Percent Studio website**

Secondary channels:

- itch.io for early public or limited-access testing
- Steam Playtest after a representative vertical slice exists
- Steam Demo when store-facing quality is appropriate
- Game Jolt as an optional community mirror
- CrazyGames as a later browser discovery channel

See `DEMO_DISTRIBUTION.md` for channel roles and rollout details.

# Scope Guard - Do Not Prioritize Yet

Delay these unless they are necessary to unblock the current loop:

- another large production chain
- large NPC behavior expansion
- complex economy balancing
- full Advisor NPC / AI system
- large quest system
- large city simulation
- advanced combat
- large asset library
- advanced VFX / SFX
- marketing trailer
- uncontrolled public demo distribution

# Design Risk - Too Predictable

The game should eventually support controlled variation so players do not discover one permanently solved route.

However, **do not solve this risk by adding complexity before the core loop works**.

Preferred order:

```text
Stable deterministic prototype
-> readable complete loop
-> internal playtest
-> controlled variation
-> balancing
```

# Codex Working Rule

Before starting implementation, Codex should read this section and identify the highest unfinished priority that the requested task belongs to.

When a meaningful feature is merged:

1. Update `DEVLOG.md` with what actually changed.
2. Update `ROADMAP.md` only if current status, priority, or a phase gate changed.
3. Update `ARCHITECTURE.md` only when technical responsibility or system boundaries changed.
4. Update `docs/game-concept.md` only when the intended game design changed.
5. Update `docs/root-branch-map.md` only when technical root/domain structure changed.

Do not copy PR history into this roadmap. PR and milestone history belongs in `DEVLOG.md`.

Do not use `docs/root-branch-map.md` as evidence that a feature is active, complete, or prioritized.

**Current Codex priority:** finish and validate the playable daily / mudbrick loop before expanding into new major systems.
