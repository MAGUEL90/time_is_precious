# Start brief: Clay worksites

## Starting point

- Branch: `feature/process-workshop/clay-worksites`
- Baseline: `0f971ab` (merge of PR #100).
- Scope of this handoff: prepare the branch and instructions only; no gathering implementation yet.
- Existing uncommitted human changes: `docs/CONTENT_LOG.md` and `scenes/content_scene/content_scene.tscn`. Preserve them. Inspect the content-scene diff before proposing integration; do not overwrite or include unrelated changes in commits.
- Read `AGENTS.md` and the complete mandatory sequence in `docs/agent-control/00 - AGENT - READ ME FIRST.md` before implementation.
- Follow current design authority in `docs/game-concept.md`; report conflicts instead of silently modifying protected design documents.

## Objective

Create a small, playable manual clay-gathering loop: visit a worksite, inspect available stock, choose work quantity/duration, preview the cost and result, perform work, and receive clay in personal inventory. Reuse existing item, equipment, time and player-condition systems where suitable.

## Discussion baseline

The following captures the conversation, not permission to invent unspecified mechanics or balancing.

- Multiple physical spots should make location and travel meaningful. Start with two clay spots as the proposed MVP; confirm placement with the Game Director.
- Each spot has its own available stock, capacity for its current cycle, and recovery state.
- The user wants varying replenishment capacity and gradual regeneration. Example only: an exhausted 12-clay spot begins a 9-clay cycle taking 3 game days to fill, equivalent to 3 clay/day. These numbers are illustrative, not final tuning.
- Partially replenished stock may be gathered before full recovery.
- Prefer elapsed game-time calculation from a last-update timestamp, preserving fractional stock and allowing only whole units to be collected. Handle overnight time advancement without a per-spot per-frame loop.
- Proposed anti-reroll rule: keep cycle capacity/rate fixed while refilling; only roll another cycle after the spot has reached full and is subsequently depleted. Confirm this precise rule before implementation, including what happens if the player continually harvests partial stock.
- Equipped tools should affect gathering duration/efficiency. Proposed speed formula: actual duration = base duration / (1 + speed bonus). A +25% speed bonus is not a 25% duration reduction. Tools should not generate extra natural stock merely by speeding up gathering.
- Condition costs must use the existing player clock/needs model without counting elapsed-time drain twice.
- Internal Hunger and Fatigue rise as conditions worsen. HUD shows inverse bars as Satiety and Energy; Focus is direct.
- PR #100 removes hunger as a direct collapse trigger. Low Satiety still accelerates Focus drain; critical Energy or Focus can still cause collapse. Do not restore a direct hunger trigger.
- Keep the HUD free of explanatory notes/popups; reuse the approved compact status presentation.

## Decisions still required

Before implementing the affected gameplay rules, present a small parameter table and obtain explicit agreement for:

1. Capacity ranges, initial stock, recovery durations, and exact cycle reset behavior for each spot.
2. Whether the player selects quantity or duration as the primary input, and how the other is calculated/rounded.
3. The equipped tool resource/slot to use, speed bonus, stacking behavior, and when equipment is sampled.
4. Base work duration and any additional work-specific fatigue cost. Preserve existing hunger/Focus tuning unless explicitly changed.
5. EXP recipient, amount and timing. Suggested MVP: personal EXP for actual manual output; hiring alone gives none. Worker profession EXP and management EXP are separate future concerns, not automatically authorized here. Existing player EXP caps at its current requirement; do not add a leveling system implicitly.
6. Cancellation, inventory-full handling, regeneration during active work, and interrupted work on collapse/scene transition. Avoid duplicating or granting unearned output/EXP.

## Boundaries

- This task reaches protected gameplay balancing/conditions and potentially clock integration. Treat the design decisions as LEVEL 4 and implementation integration as at least LEVEL 2; request explicit approval for remaining mechanics and protected edits.
- Audit existing equipment and gathering before creating managers, autoloads, item types, or global APIs. Adding global dependencies/settings needs separate authorization.
- No new worker delegation implementation, market/trading system, save-system overhaul, workshop-from-empty-plot progression, durability system, or unrelated UI refactor.
- Good Deed and Bad Deed are saved future design reminders, not gathering rewards or implementation scope.
- Do not assign moral scores to gathering/hiring.
- Do not modify agent-control governance files or baseline tags.
- No direct work on main, no automatic merge, and no push without authorization.

## First checkpoint

Perform a read-only audit of existing gathering nodes, inventory capacity APIs, equipment effects, game-time advancement, player conditions/EXP, and the current dirty content-scene placement. Report reusable components, missing pieces, expected files, risk level, and the unresolved decision table. Do not start broad implementation merely because the branch exists.

## Acceptance plan after design approval

- Independent stock at two sites; no negative stock or over-cap regeneration.
- Exact fractional recovery, capped stock, partial gathering, and time/day jumps verified.
- Equipment time bonus matches the agreed formula; inventory capacity limits are honored.
- Actual elapsed work affects conditions once; output/EXP corresponds only to completed work.
- No duplicate payout on repeated clicks, cancellation, reopening, or interruption.
- Sleeping, collapse/Nightmare, player scene changes and busy UI behavior are tested where touched.
- Current Godot 4.5.x project launches; compact UI verified at 1200x675 with the project's 400x225 logical viewport, without changing project settings.
- Existing condition HUD and workshop integration regressions pass.
- Human playtest and review remain the merge gate; record untested cases honestly.
