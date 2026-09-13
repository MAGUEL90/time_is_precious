# Common walking speed and distance-based departures

2026-09-10. User-authorized revision of the fixture commute; local edits preserved.

## Early exit audit

The scheduler ends the shift at 15:00, and independently stops gathering on stock depletion. Current default stock is 72, rate is 6 clay/hour/person. Two workers from 07:00 exhaust that default at 13:00; one worker with untouched stock should remain productive until 15:00. The exact reported 14:00 run has not been reproduced from its original state.

Controlled regression demonstrates two workers with 84 stock exhaust it at 14:00 and enter Waiting for resources. With 1000 stock they remain Working at 14:00 and stop exactly at 15:00. No early fixed 14:00 cutoff exists or was introduced; no balance changed.

## Revised commute

- Every worker uses the same exported `worker_walk_pixels_per_game_minute` (default 10).
- Exact departure = 07:00 minus route distance / common speed. Movement uses distance travelled at that speed, rather than slowing every route to fill an hour.
- Visible spawn/travel status uses the departure minute; fractional departure within that minute is retained for movement so all distances arrive at exactly 07:00.
- Added editable NearSpawn/FarSpawn under WorkerDeparture. First appearance uses the assigned slot's marker; already-visible roaming workers depart from their current position.
- Routes update while workers roam before departure, then freeze origin and timing when the departure minute is reached. Next-day assignment policy remains unchanged.
- Commute demo positions its clock two minutes before the computed first departure instead of a hardcoded 05:58.

## Files / validation

Changed daily scheduler, fixture .gd/.tscn, worker visual controller and commute test. Added test_scene_clay_worksite_departure.gd/.tscn and this report.

WorksiteDepartureTest passes different origins/departure times, identical computed speeds and shared arrival, depletion-at-14:00 versus full-shift control. Commute, Daily and Gathering tests pass; existing certificate-store and exit-resource diagnostics remain. Straight-line fixture routing only; no obstacle navigation or save persistence.
