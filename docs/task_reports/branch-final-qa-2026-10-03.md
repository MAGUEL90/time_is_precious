# Branch QA — 2026-10-03

Branch: `feature/process-workshop/main-map-access`.
Scope: validate the current dirty working tree after human acceptance of the pixel-preserving completion animation. No gameplay changes or commit in this QA pass.

## Verdict

**Later map revision:** ContentScene was subsequently simplified at the Game
Director's request. See `content-scene-cleanup-2026-10-03.md` for current scope
and the historical hauling-test limitations. Before committing, a fresh native
DebugProductionFlowTest run on the simplified map passed two production/drying
cycles, payments, upgrades, withdrawal and the Shekel HUD checks. The same
ObjectDB/resource shutdown diagnostics remain.

The debug-assisted workshop MVP loop passes. This is not an unconditional all-clear for normal progression or Hauler presentation. Normal startup still cannot pay production output fees without Shekel; Hauler cart/clothing presentation still has the limitations below.

## Fresh verification

Native Godot 4.5.1, GL Compatibility, requested window 1200x675. Each test ran in its own process, sequentially, returned exit 0, and printed its success marker. These automated fixtures drive existing UI handlers/input and runtime APIs, teleport to interaction points, and advance game time; they do not validate manual navigation around obstacles.

| Test | Result and coverage |
| --- | --- |
| BranchAcceptanceFlowTest | PASS: real Job Board hires, city Cart equipment and Wood hauling, release from Daily work, cleaning, building, debug controls, storage, two shape/dry production cycles, fees, yard upgrades and withdrawal. 40 dry bricks produced: 10 used for upgrade, 1 withdrawn, 29 free in storage. 14 Shekel paid, leaving 86 from debug 100. |
| MainMapHaulerStartTest | PASS: normal applicant registration, hiring, K equipment flow, one physical Cart, hauling target, output conservation, withdrawal, map reload, firing/tool return, no duplicate grants. |
| WorkshopAssignmentDiscardTest | PASSED: X, Back, Escape, Stay and Discard; drafts released to other workshops/worksites; active orders preserved while unused draft workers are released. |
| WorkshopConstructionUITest | PASS: existing construction UI regression. |
| WorkshopWorkerPresenceTest | PASS: entry/hide/reappearance, eight builders, plot independence, arrival-gated recurring dust, pause/toggle, production/reload, cleaning/building progress, exact settled-bar pixel match and opacity-only fade at three samples. |
| WorkshopClearingTest | PASS: worker or player, exactly 180 minutes, no materials, invalid/double assignment rejection, interrupted player work, Board interaction, UI and reload. |
| NormalStartProductionAudit | PASS for expected blocker: actual worksites supply construction and production materials; 17 wet bricks produced in this run; output remains held with zero Shekel and payment shows insufficient currency. This is not end-to-end normal progression success. |
| WorkerCartAnimationTest | PASSED: existing cart pose/layer/frame/mirroring contract. This does not assert that an equipped cart stays visible during ordinary roaming. |

Inspected fresh rendered images: `TEMP/tip-worker-cart-animation.png` and `TEMP/tip-workshop-assignment-discard.png`. Reviewed worker assignment, production ownership, plot presentation and worker-presence source/diffs. `git diff --check` passed. Existing unrelated local work was preserved.

## Remaining limitations

- **Normal economy:** the tested ordinary start has no Shekel available for output fees. The full successful loop uses the authorized debug top-up. No new income rule or free output was introduced.
- **Hauler presentation:** `clay_worksite_worker_visuals.gd` selects cart poses during hauling; ordinary commute/roaming selects walk/idle, which hides the cart sprite. Equipment ownership remains intact. `base_worker_visual.gd` intentionally hides clothes/hair/accessories for cart poses because matching overlay art is absent. The earlier visual concern is therefore not fully resolved, even though delivery and equipment tests pass.
- **Diagnostics:** all eight processes emitted the existing ObjectDB leak warning and 15-resources-in-use shutdown error. No script errors, failed assertions or bridge-port conflict occurred in these final eight runs. Shutdown cleanup is not certified clean.
- Physical obstacle navigation, long-duration soak testing and disk save/load were not validated. Map reload tests cover runtime persistence only.

Recommendation: separate acceptance of the tested debug-assisted MVP from follow-up decisions on Hauler visual continuity and ordinary Shekel progression. No commit, push or merge performed.
