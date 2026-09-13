# Hauler cycle — isolated worksite integration

Date: 2026-09-11
Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Risk: limited integration inside existing worksite fixtures plus reusable storage destination; no production autoload, resource schema, project setting, balance-rate or asset changes.
Starting tree: dirty. Existing human scene edits, asset changes and prior work preserved.

## Implemented

- Daily Haulers do not gather. Existing non-Hauler gathering rates are unchanged.
- Every completed Daily clay is now made available immediately in the site's merged ground pile. Player pickup and Hauler pickup use that same pile; collecting/deleting piles cannot be taken again.
- A cart carries three items (not slots). Hauler waits for three items, except final partial output may be loaded after natural stock is depleted.
- Routes use the existing common walking speed and game-minute clock. Hauler walks to the configured destination, unloads, returns and repeats during 07:00–15:00. Initial assignment still starts next day.
- No new trip starts at or after 15:00. Trips already underway finish. Daily reservation continues tomorrow.
- Full/unavailable storage prevents loading. If a destination stops accepting after departure, cargo returns to the original site's pile. The destination must accept a whole load; no partial unloading is added.
- Remove is immediate while idle; a Hauler in transit is marked Finishing, retains its reservation/cart while finishing the trip, then releases. The confirmation explains this behavior.
- Progress labels distinguish gathered Output from Hauler Delivered quantities/delivery days.

## Reusable destination

Instance `scenes/storage_destination/storage_destination.tscn` at any location. Configure its `storage_path`, RectangleShape2D unloading bounds and ArrivalPoint. Bind a storage implementing `has_capacity_for(item_id, quantity)` and atomic `try_add_item(item_id, quantity)`. Storage still owns capacity/item validation.

Fixture `storage_destinations` maps each site name to a destination NodePath. Multiple sites can use different destinations or share the same destination. Preflight does not reserve storage capacity: unloading rechecks capacity, so simultaneous deliveries remain safe.

Physics carriers can use `try_deliver`; clock-driven carriers use authoritative world positions through `try_deliver_at_position`, which checks transformed unloading bounds without relying on stale physics overlap caches after time skips.

## Cart boundary

`test_hauler_carts` provides fixture-only cart availability, default zero. Each standing Hauler reserves one cart; in-transit removal keeps that cart reserved until the trip finishes. The dedicated demo supplies one cart. A player-owned cart item, equipment UI, cart sprite/animation, durability and a general equipment system are NOT implemented. These are test allocations, not claims that inventory supplies the cart already.

## Playtest

Open `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_hauler.tscn` and press F6. This creates one Test Laborer, one Test Hauler, a cart and a destination with fixture storage (96 items). Starts 15 minutes before the first scheduled workday. F7 advances 30 minutes while menus are closed. Watch the clay count above the carrier and storage counter.

At the current rate, Laborer makes six clay/hour; first full load becomes available after 30 productive minutes. Delivery takes additional distance/speed time. Approach Clay Site A and open Worker Progress to test Remove.

Automatic mode: `TIP_TEST_HAULER=1`. The graphical run captures `%TEMP%/tip-hauler-cycle.png`.

## Validation

- ClayWorksiteHaulerTest: PASSED headless and graphical 1200x675; repeated trips, 3-item load, free-cart guard, conservation, rejected delivery return, loaded removal, final partial load, post-shift completion and standing reservation.
- StorageDestinationTest: PASSED including independent transformed destination/backends, capacity and duplicate protection.
- ClayWorksiteDailyTest, WorksiteCommuteTest, ClayWorksiteGatheringTest: PASSED.
- Main project launch: exit 0. Targeted files reviewed; git diff --check passed.
- Screenshot reviewed; storage counter, both sites, worker and cargo are visible.
- Existing root certificate-store and ObjectDB/15-resource exit diagnostics remain; no new blocking errors observed.

## Scope and ownership

Modified: Daily scheduler, worksite fixture, worker visuals, inspector, StorageDestination and destination test. Added: hauling module, fixture storage backend, Hauler demo/test scene and script, this report.

Astra root: integration design, scheduler/piles/destination/UI/test fixture, all executed tests, regression checks and final review. Delegated Luna XHigh: bounded transport module; no separate subagent-authored tests. No gameplay authority delegated.

The loop remains scene-local: no persistence, world pathfinding/obstacle handling or shipping warehouse/home/workshop integration is claimed. Leaving the fixture clears its state as before. No commit, push or merge performed.
