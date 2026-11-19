# City transport and player-funded construction

Status: cloud branch implementation for integration. The branch starts at
`13a6c0725a08c91bfcbc2606646e8ebf0f668968`; it includes the earlier direct-city
worksite commit and this follow-up. No laptop or shared branch was modified.

## Gameplay

- Daily worker production from all five authored resource sites is received by
  Central City Storage, with raw materials accepted through a dedicated city
  receipt. A rejected receipt remains under its existing job or pending-output
  owner and retries without consuming natural stock again. Integer limits are
  checked; no old storage capacity or stock is reduced.
- City-owned counted goods may be sent between Central Storage and a new
  city-owned Annex. Open either storage board and choose **Haul**, a paid idle
  Laborer or legacy Hauler with an allocated city Cart, an item and 1–3 units.
  This is a single trip, with at most one active assignment. A Laborer acts as
  a temporary courier and keeps the Laborer profession. An actual legacy Hauler
  earns its existing per-delivered-item profession XP. New worksite Hauler jobs
  remain disabled. Personal Inventory, city currency, unique equipment and open
  food portions are outside this transport flow. Citizens consume from Central,
  not the Annex. Pickup currently starts at the selected source: the courier
  does not yet walk from their prior idle position to that source.
- The cart owns its cargo until the destination accepts it. If the destination
  is full it retries; Cancel returns a load to its source; a resigning courier
  settles the load before leaving. An unavailable/blocked navigation segment
  pauses the cart at its last clear point. Cargo, worker reservation, both stock
  locations and transport time cursor are saved together. An active cart cannot
  be removed from its courier.
- Workshop and house plot starts, timed wall construction/repair/upgrade,
  Watchtower construction and Drying Yard construction/upgrades debit personal
  Inventory. Payment preflights and publishes as one guarded transaction;
  synchronous observers cannot capture a partial payment or advance time in it.
  Legacy city-funded wall projects retain City Storage as their refund owner.
  A refused Inventory refund remains pending and is persisted until it fits.
- Drying Yard has explicit personal-material contributions and an explicit refund.
  Each confirmed batch transfers atomically; a full Inventory refuses refund
  without losing the saved contribution, and larger refunds can be reclaimed
  over several trips. This supports the unchanged level-three
  cost of 6 Wood Logs, 10 Reed Bundles and 20 Sun-Dried Mudbricks (108 weight)
  over multiple trips with the normal 100-weight bag. Stale confirmation quotes
  are rejected.
- The existing traveling merchant now offers Stone as a provisional acquisition
  path for player-funded defense: 12 Stone at 2 Shekels each per normal visit.
  Other listed prices, construction costs, wages, capacities and schedules are
  unchanged. This is a new temporary balance choice, not a claim that final Stone
  acquisition or pricing has been approved.

Player-only Hourly gathering still goes into personal Inventory, with existing
player-pickable overflow. That preserves the only authored personal Reed source
needed for early construction. Hendro's broad wording that worksite results go
to City Storage could also be read as covering player-only Hourly work; that
interpretation would remove the existing early-game material route. The branch
therefore leaves this distinction explicit for integration review instead of
silently redirecting or granting city property to the player.

## Checkpoint compatibility

City checkpoints use schema v16. Versions 1–15 are decoded and validated into a
staged copy: missing Annex/cargo/contributions begin empty, legacy active defense
payments are attributed to City Storage, and a new merchant Stone offer is staged
with zero stock for an already-running legacy visit. Its next scheduled visit
refills normally. The original file is not changed on load; the normal backup is
kept on the next successful save. Cargo and contribution records are strictly
validated against authored endpoints, worker/cart reservations, known items,
facility levels and requirements before any live owner is changed. Older
worksite piles and in-flight jobs retain the prior branch's conservative migration.

## Validation

Godot 4.5.2 was run headlessly in isolated user-data directories. The editor
import and a bounded normal startup both completed without script errors.

- Fresh-process transport write/Continue covered the real board, outbound and
  reverse delivery, cancellation, full-destination retry, cargo persistence,
  equipment ownership, resignation and a legacy Hauler's experience. A
  separate home/Continue journey covered offscreen delivery and return to city.
- Fresh-process facility contribution/Continue covered the 108-weight kit,
  partial returns over multiple trips, conservation, recontribution and build.
  The player-facing workshop flow passed with the logical viewport forced to
  400×225 for the confirmation text and control-boundary checks. A three-phase
  paid construction, production and Continue journey also passed.
- The direct-output journey passed write, Continue and verification phases,
  including all five Daily resources, full storage/retry and a v14 legacy job.
  `CitySleepSaveTest` passed its real sleep and home/city transitions, v2/v3
  stockpile migration and one-time pickup; `PickupSourcesTest` also passed.
- `StonePurchaseTest` passed through the normal merchant dialogue and Buy UI,
  guarded concurrent-payment checks, wall construction and Continue. The
  prior failing `WarehouseTest`, `CityStorageSupplyFlowTest` and
  `CityStorageHaulingTest` all passed. Nearby city-save, economy, defense,
  raid, wall, workshop, resignation, merchant, deposit, overflow and clock
  transaction suites passed as well.

One separately run `WorkerPayrollFixtureTest` still fails its first hire check.
The identical failure was reproduced in a separate checkout of baseline
`13a6c07`: this fixture expects the retired daily-payroll hiring path and a new
Hauler hire, while the baseline has prepaid contracts and blocks new Hauler
recruitment. The test was not weakened; the current prepaid production and
resignation journeys above passed.

No graphical or Windows playtest or human acceptance was performed in this
cloud environment. The 400×225 check verifies control geometry and text line
visibility headlessly, not visual polish. The Hourly gathering distinction,
single active courier assignment, source-start shortcut and provisional Stone
offer described above remain integration decisions or limitations.
