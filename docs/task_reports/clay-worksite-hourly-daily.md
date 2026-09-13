# Worksite Hourly / Daily checkpoint

2026-09-08 — PASSED — NEEDS HUMAN REVIEW for the approved flows.
Random-stock balancing remains TBD; the live test range is still 72–72.
Scope: LEVEL 2 limited integration within the existing test fixture and sandbox UI,
authorized by the latest Hourly/Daily specification and request to implement what is settled.
Branch: feature/process-workshop/clay-worksites; baseline 0f971ab. Existing dirty scene,
asset deletion, rename and documentation changes preserved. No production/global source edits.

## Behavior

- Initial panel offers Hourly and Daily, with assignment feedback. Old footer Add Worker
  and estimated output are hidden. Hourly reveals the question and 3/6/9-hour choices.
- Daily opens the existing assignment cards without Player. Next returns to the site panel;
  Start activates a recurring assignment without advancing time or charging a fee.
- Daily workers gather only during 07:00–15:00. Assignment at 14:00 earns only one hour
  that day. Assignment after 15:00 waits for the next shift. Existing minute signals also
  advance Daily jobs while Player skips time through Hourly work or other activities.
- Eight-hour usage is recorded per worker per world day across the fixture's sites.
  Removing/reassigning does not reset the ledger. This does not yet account for minutes
  previously worked in production workshops: a future shared workload integration is needed.
- Assignments persist through shift end, depleted stock and rest until explicitly withdrawn.
  Use Daily, right-click an occupied slot, then Next to return. Withdrawal is immediate,
  settles completed output, and releases that worker. New selections activate on Start.
- Small site capacity is two active places, including an Hourly Player. Two active
  NPC workers block Hourly during the shift. Resting workers leave room for Hourly;
  Hourly that crosses into a full 07:00 shift stops at that boundary. One NPC plus Player
  can use the same site and finite stock simultaneously.
- Existing WorkerData busy/order fields reserve standing assignments across the day and
  night. The worksite panel displays resting separately. Generic worker management may
  still display Working for this reservation; no global status schema was added.
- A Daily shift settles completed output at 15:00 or depletion. Results merge into the
  existing daily clay pile for that site. Pickups in their collection animation are excluded.
  Oversized piles support partial pickup using existing feedback, leaving the remainder.
- Stock replacement occurs once at midnight. It replaces unharvested natural stock only,
  never ground items. Minimum/maximum are exported on the test scene root, both default 72.
  Integer random generation is ready, but no scarcity range was invented from the user's
  illustrative 8–9 example. Tests inject 2–4 solely to verify bounds and no repeated reroll.

## Balance clarification

Actual harvest is capped by both available stock and completed labor. A daily stock below
the team's capacity can reduce output. A stock above capacity does not raise that day's
worker output; it only leaves resources available for other gathering until replacement.
The rate remains 1 clay per 10 minutes per person, not the illustrative 3 clay/day.
Thus one full 8-hour shift can produce 48 clay, two can produce 96, subject to stock.
With the unchanged live stock 72, two workers exhaust it after six hours.

Satisfaction acceptance/refusal, tools, worker levels, transporter delivery, and extra
duration-based resting are not implemented. All Daily output currently goes to ground.
The fixed shift provides the approved rest period. Jobs and ground output remain scene-local;
closing/reloading the fixture resets them and releases worker reservations.

## Verification

- Daily regression passed headlessly and graphically at 1200x675. Screenshots inspected.
- Covered NPC-only cards, row filling, empty selection, Hourly/Daily visibility, capacity,
  14:00 start, exact 15:00 stop, overnight inactivity, next-day recurrence, 480-minute
  ceiling, withdrawal/reassignment, shared Player/NPC time and stock, replacement bounds,
  one roll per day, pile merging, partial pickup, and output arriving during collection.
- Inspection, Hourly gathering/overflow, and full Nightmare escape/timeout regressions passed.
- Workshop UI, condition HUD and population/employment regressions passed.
- Main project smoke launched. Existing certificate-store and shutdown resource warnings
  persist; no new blocking errors. git diff --check passed; untracked edited files read directly.

## Changed files

New: clay_worksite_daily.gd and clay_worksite_daily_pickup.gd under the fixture folder.
Updated: clay_worksite_session.gd, test_scene_clay_worksite.gd, clay_worksite_assignment_ui.gd;
clay_worksite_inspector.gd/.tscn; existing team, inspection, gathering and Nightmare test scripts.
The team regression now tests the replacement Hourly/Daily contract.
Documentation: this report and a supersession note in clay-worksite-team-production.md.
No commit, push, merge, asset changes or project setting changes in this step.

## Human playtest

F6 test_scene_clay_worksite.tscn. E at a site, then Hourly for Player or Daily to assign NPCs.
For removal, reopen Daily and right-click an occupied slot. Observe the active/resting
feedback when returning to the main site panel. Daily outputs appear at the site even if
Player moves away. The existing overflow inventory preset remains enabled.

To test different scarcity ranges later, use Daily Stock Min / Daily Stock Max on the
fixture root. These affect the next midnight replacement; starting stock remains 72.
This is a test control, not approval of a production balance range.
