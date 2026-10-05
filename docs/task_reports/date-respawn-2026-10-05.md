# Random date refill — 2026-10-05

Branch: feature/item/food-mvp. Baseline: e083bce. Starting tree clean. Risk LEVEL 2: explicitly authorized tree spawning and session continuity. Status: implementation checks pass; human review and outstanding runtime/platform validation remain.

## Behavior

Each tree starts full (default max_pickups 3). The first successful collection draws a whole-hour wait uniformly from 1 through 18 game hours. Further collections do not reset it. When the timer expires, only missing slots are restored; existing pickups retain identity and position. Full trees have no running refill timer. Quantity stays at the existing one date_cluster per pickup.

DatePalmTree uses date_palm_spawner.gd, instantiating the same pickup_item.tscn used by other items. PickUpItem publishes collected only after inventory accepts its quantity. A state node per stable unique tree_id lives beneath the existing WorkStateRuntime, following the merchant's session-state ownership pattern. The minute_changed elapsed-time signal decrements the timer while views are absent and during time skips. Snapshot time_changed signals cannot accelerate it. No new autoload or disk-save schema.

Inspector: max_pickups configures capacity; pickup_positions must provide at least that many local offsets. Default three offsets preserve the user's placement. Tree identity is now generated from its containing scene and node path; duplicating a node gives it independent stock without entering an ID. Keep node names and paths stable during a running session. Configuration is initialized once per running session. Positions are authored, not randomized; the approved randomness concerns time. Weather does not block refill; no weather policy was approved in this implementation request.

## Verification

Godot 4.6.3 editor import and headless fixtures:
- DateRespawnTest PASS: initial stock, 1–18-hour bounds, no timer reset, no early refill, missing-slot refill, retained pickup identity, full-cap behavior, snapshot immunity, partial stock/timer across map recreation, refill during map absence, independent trees and varied waits across 100 cycles.
- DatePickupTest PASS: player interaction, full inventory, duplicate prevention, consumption, icon override and legacy fallback.
- Startup smoke and diff whitespace checks run before commit.

Both fixtures retain the ObjectDB shutdown warning; the pickup fixture already emitted it at baseline. No script errors reported. Godot 4.5.x, graphical Windows/Android, actual home-door traversal and actual sleep UI were not manually tested; map recreation and elapsed-time advancement were exercised directly. No full QA or disk persistence claim.

Files: pickup_item.gd, ContentScene integration, two tree scripts with UIDs, respawn fixture with UID/scene, task reports. No settings, addon, autoload definition, food balance or terrain changes. No merge performed.

## Requested debug controls

The existing Debug panel (backtick / Debug button, debug builds only) now includes DATE PICKUPS. It shows each registered tree's stock/capacity and remaining hours/minutes. Refill dates (all trees) fills only missing ground pickups and cancels their timers without advancing the clock or granting inventory. The button is disabled when all trees are full or the normal debug supply guard disallows changes. Existing clock-step controls remain available for natural timer testing. Release builds reject the refill method.

The extended DateRespawnTest passes read-only panel viewing, stock label, button availability, real button callback, timer clearing, inventory conservation and repeated-refill cap. Visual layout still needs manual review; the section uses the existing scroll container.

## Final QA follow-up

See `food-mvp-final-qa-2026-10-05.md` for subsequent duplication safety, graphical evidence, corrected test teardown and multi-tree balance comparisons. Earlier validation limitations above describe the initial checkpoint.
