# CONTENT LOG - Time is Precious

Last updated: 2026-08-01

## Purpose

This document connects development progress with public-facing content.

Use it to answer four questions:
1. What has already been implemented?
2. What has already been shown publicly?
3. What implemented progress has not been shown yet?
4. What should become the next content piece?

This is not a substitute for `DEVLOG.md` or `ROADMAP.md`.

- `DEVLOG.md` records development progress and current implementation state.
- `ROADMAP.md` records development priorities.
- `CONTENT_LOG.md` records what the audience has seen and what content should come next.

## Content Rules

- Do not claim a planned system is already implemented.
- Do not describe documentation-only work as playable gameplay.
- Prefer one clear gameplay story per post instead of listing unrelated features.
- Group small polish changes when they support the same player flow.
- Keep English copy natural, readable, and lightly humorous.
- Avoid overly technical implementation details unless the post is specifically a technical devlog.
- Use PR numbers as the source of truth for the implementation shown.
- Mark publication details as `Needs confirmation` when the exact date, platform, or link has not been recorded.

## Content Status Labels

- `Published` - confirmed to have been posted publicly.
- `Prepared` - video or copy exists but publication has not been confirmed.
- `Ready to Record` - implemented and has a clear content concept.
- `Backlog` - implemented, but not yet shaped into a final content concept.
- `Blocked` - should not be published as implemented yet.

## Confirmed Published Content

### 1. Village, NPC Interaction, and Dialogue Progress

Status: `Published`

Features shown:
- Village area beginning to feel alive.
- Player exploration.
- NPC interaction.
- Dialogue flow and typing effect.

Relevant implementation:
- Dialogue and NPC interaction work before and through PR #75.

Public copy direction used:
- Small progress update.
- The village is slowly coming to life.
- One percent at a time.

Publication details:
- Platform: Needs confirmation.
- Date: Needs confirmation.
- Link: Needs confirmation.

### 2. Gabbi Introduction / Game Overview

Status: `Published`

Features shown:
- Gabbi introducing `Time is Precious`.
- Short explanation of the management RPG concept.
- Gathering, villagers, daily management, and village growth.
- Prototype target and planned platforms.

Relevant implementation:
- PR #75 - intro dialogue and chatbox presentation.

Important messaging boundary:
- AI NPC behavior is a future direction, not an implemented gameplay claim.
- Safe wording: some characters are planned to respond in more personal and unexpected ways as development continues.

Publication details:
- Platform: Needs confirmation.
- Date: Needs confirmation.
- Link: Needs confirmation.

### 3. Pickup Item Progress

Status: `Published`

Known public post:
- Threads post supplied by the developer as the latest pickup-related content.

Features shown or discussed:
- Player picking up items.
- Item interaction feedback.
- Pickup as the start of the inventory flow.

Relevant implementation:
- PR #78 - pickup and inventory item flow.
- Additional pickup polish later included in PR #83 and PR #84.

Publication details:
- Platform: Threads.
- Link: `https://www.threads.com/@hendrohen/post/DaGK0LbDylc`
- Date: Needs confirmation.

## Prepared Content

### Item System, Inventory, HUD, Conditions, and Drop Flow

Status: `Prepared`

Working asset:
- `content 7.mp4` reviewed outside the repository.

Core content story:

```text
Pick up an item
-> See clearer pickup feedback
-> Open the polished inventory
-> Use an item
-> Check player conditions in the HUD
-> Drag another item out
-> Drop it back into the world
-> Pick it up again
```

Relevant implementation:
- PR #78 - pickup and inventory actions.
- PR #79 - drag-out drop and re-pickup.
- PR #81-#82 - player conditions and consumable consequences.
- PR #83 - pixel resolution, inventory, and HUD polish.
- PR #84 - pickup prompt, animation, and world-layer polish.

Suggested corrected in-video copy:

1. `Hey! It's been a while since my last update.`
2. `Over the past week, I've been polishing the pickup system while continuing work on the core gameplay.`
3. `Pickup interactions now have clearer feedback.`
4. `A cleaner prompt and smoother animations.`
5. `My previous pickup animation.`
6. `The inventory also got a makeover.`
7. `A fixed 5x3 layout, clearer item details, and less UI chaos. Hopefully.`
8. `The important stuff stays hidden until you need it. Just hold Tab.`
9. `Hunger, Fatigue, and Focus now change over time. Hold Tab to check them.`
10. `You can also toggle the HUD for a cleaner screen.`
11. `Picked up the wrong item and changed your mind?`
12. `Drag items out of the inventory to drop them back into the world.`
13. `And yes, you can pick them up again.`
14. `Or not.`
15. `Okay, that's it for now. Thanks for watching - see you!`

Copy corrections still required inside the game footage when visible:
- `Pan Fried Egg` -> `Pan-Fried Egg`
- `Butchers Cut` -> `Butcher's Cut`

Publication details:
- Platform: Not recorded.
- Publication status: Needs confirmation after upload.
- Final post caption: Not recorded.
- Final hashtags: Not recorded.

## Implemented Progress Not Yet Confirmed as Published

### A. Character and Citizen Animation Polish

Status: `Ready to Record`

Relevant PR:
- PR #84.

Content angle:
- The village feels more alive because citizens now have visual variation, idle behavior, wandering, direction changes, and cleaner layering with the world.

Recommended single-content flow:

```text
Show old/static scene briefly
-> Show layered player movement
-> Show several citizen appearances
-> Show citizens wandering independently
-> Show diagonal direction changes
-> Show player/NPC/object Y-sorting
```

Suggested hook:
- `The villagers have discovered free will. Sort of.`

Do not overload this post with:
- Home transitions.
- Sleep.
- Nightmare gameplay.
- Workshop UI.

### B. Player Home and Daily Scene Loop

Status: `Ready to Record`

Relevant PR:
- PR #85.

Content angle:
- The player finally has a home and can move naturally between home and city without losing current conditions.

Recommended content flow:

```text
Start inside the home
-> Walk to the door
-> Exit into the city
-> Show time and conditions remain active
-> Re-enter the home
-> Show correct interior spawn
```

Suggested hook:
- `The player finally has somewhere to live.`

Important boundary:
- State persistence is runtime-only.
- Do not call this a complete save system.

### C. Sleep and Player Condition Loop

Status: `Ready to Record`

Relevant PRs:
- PR #81.
- PR #82.
- PR #85 for home integration.

Content angle:
- Time management now affects the player's body and daily choices.

Recommended content flow:

```text
Show Hunger, Fatigue, and Focus changing
-> Return home
-> Interact with the sleep spot
-> Advance seven hours
-> Show recovery and changed conditions
-> Show that sleep is limited to once per day
```

Suggested hook:
- `Sleep is free. Recovering properly is not.`

### D. Collapse and Nightmare Consequence Loop

Status: `Ready to Record`

Relevant PR:
- PR #82.

Content angle:
- Ignoring player needs has a real gameplay consequence.

Recommended content flow:

```text
Conditions approach critical levels
-> Collapse triggers
-> Transition into the Nightmare World
-> Show limited vision and timer/exit path
-> Show result screen
-> Return with normal-world penalties
```

Suggested hook:
- `Ignore your needs long enough, and the game sends you somewhere worse.`

Content note:
- This is a larger reveal and should come after the audience has seen the condition and sleep systems.

### E. Workshop and Mudbrick Production Loop

Status: `Backlog`

Relevant PRs:
- PR #68.
- PR #73.
- PR #76.

Current implemented content:
- Deposit and withdraw materials.
- Select quantities.
- Assign workers.
- Check profession and material requirements.
- Start mudbrick work.
- Advance time.
- Produce claimable `wet_mudbrick`.
- Apply worker needs, satisfaction, reliability, and service fee rules.

Recommended content structure:

Content 1 - `Preparing the Workshop`

```text
Open workshop
-> Deposit clay, straw, and water
-> Assign a matching worker
-> Show missing-requirement feedback when setup is wrong
```

Content 2 - `Making the First Mudbricks`

```text
Start the job
-> Advance time
-> Show job completion
-> Claim wet mudbrick output
```

Important boundary:
- The player-facing drying path to `sun_dried_mudbrick` is not complete enough for a final full-chain claim.

### F. Immigration and Growing Population

Status: `Backlog`

Relevant PR:
- PR #66.

Content angle:
- Growing the city creates both opportunity and responsibility.

Recommended content flow:

```text
Immigration request appears
-> Review new arrivals
-> Accept or reject the batch
-> Accepted citizens appear in the city
-> Population and city needs update
```

Suggested hook:
- `More citizens. More workers. More mouths to feed. Great.`

## Blocked or Future-Only Content

### AI NPC Quest Integration

Status: `Blocked`

Relevant PR:
- PR #74.

Current state:
- Architecture and responsibility boundaries are documented.
- Playable AI NPC quest integration is not implemented.

Allowed public direction:
- Discuss it as a future plan or design goal.

Not allowed as a current-progress claim:
- `AI NPCs are now active.`
- `NPCs remember every conversation.`
- `Dynamic AI quests are implemented.`

### Complete Save System

Status: `Blocked`

Current state:
- Player state can persist across current runtime scene transitions.
- Disk save/load is not complete.

### Complete Mudbrick Production Chain

Status: `Blocked`

Current state:
- Wet mudbrick production exists.
- The final player-facing claim, drying, and visible progression path is still incomplete.

### Public Demo Release

Status: `Blocked`

Current state:
- Distribution strategy is documented.
- The prototype still needs a stable complete loop, onboarding, testing, and a clear endpoint.

## Recommended Publishing Order

The sequence below continues naturally from the confirmed pickup post:

1. Item system, inventory, HUD, conditions, and drop flow.
2. Character and citizen animation polish.
3. Player home and city transition loop.
4. Sleep and player condition loop.
5. Collapse and Nightmare reveal.
6. Workshop preparation and worker assignment.
7. Mudbrick job and claimable output.
8. Immigration and population growth.

Why this order works:
- It starts from the item interaction the audience already saw.
- It gradually expands from one item to the player, then the home, then the city.
- It introduces player conditions before revealing Collapse and Nightmare consequences.
- It saves the broader management systems for after the audience understands the daily-life loop.

## Next Content Decision

Current next post:
- `Item system, inventory, HUD, conditions, and drop flow.`

Current stage:
- Video prepared and English reviewed.

Before publication:
- Apply the English corrections listed above.
- Confirm visible item names are corrected.
- Record the final post caption and hashtag set in this document.
- After publication, move this entry into `Confirmed Published Content` and add the date, platform, and link.

## Update Workflow

Whenever a PR is merged:
1. Add the new implementation to `DEVLOG.md`.
2. Check whether it is visually understandable in a short video.
3. Add it to `Implemented Progress Not Yet Confirmed as Published`.
4. Group it with related work when that creates a stronger player-facing story.

Whenever content is published:
1. Move or copy the entry into `Confirmed Published Content`.
2. Record the platform, date, and link.
3. Record which PRs were covered.
4. Remove those features from the unpublished backlog unless a clearly different angle remains.
5. Set the next content based on the closest unfinished player journey.
