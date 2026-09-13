# Worker commute and base work animation

2026-09-09. Authorized limited integration in clay test fixture; existing local changes retained.

- Worker Daily keeps its next-day start. At 07:00 on eligible days, a worker leaves WorkerDeparture, travels in a straight line to its site slot, then plays base work animation.
- Added Travelling activity, retaining the standing reservation. Gathering minutes only accumulate after arrival; shift still ends at 15:00, so travel reduces productive time.
- Travel duration is ceil(distance / worker_travel_pixels_per_minute). Fixture default is 8 pixels per game minute. WorkerDeparture and speed are editable test settings, not a production pathfinding or home system.
- Worksite visuals reuse BaseWorkerVisual, linked citizen appearance where available, and base expression. Stock depletion shows idle. Withdrawal removes the visual. Outside the shift visuals are hidden; return-home travel is not implemented.
- Position and arrival derive from game time, so time skips settle arrival and production consistently. Frame interpolation smooths visible travel; scene pause stops it.
- F6 demo: test_scene_clay_worksite_commute.tscn schedules one temporary worker and advances to next-day 06:58. Player needs are disabled in this demo to allow watching the journey. Main fixture presets preserved.

Changed: WorkerData enum/text; clay_worksite_daily.gd; fixture .gd/.tscn; existing team regression (disables commute to retain isolated scheduler coverage). Added clay_worksite_worker_visuals.gd and commute demo/test .gd/.tscn.

Validation: graphical WorksiteCommuteTest PASSED at 1200x675, including invisible before shift, travel animation and movement, no production before arrival, base work animation at destination, post-arrival output, depleted idle and withdrawal cleanup. Arrival screenshot inspected. Existing Daily, Gathering and Inspection regressions exercised separately. Existing certificate store / exit resource warnings remain.

Limitations: no navigation obstacles, actual homes, return journey, XP changes, save persistence or production-world integration. Matching work clothing/hair/accessory assets are still absent and remain hidden during work.

## Worksite visual cycle refinement

After arrival: idle 0.7 seconds, base work in last travel direction for seven frames, base work in the opposite direction for seven frames, idle 0.7 seconds, walk to a nearby point, idle 0.7 seconds, repeat. Local movement cycles through four offsets within the site slot at 10 pixels/second. Body/head frames are synchronized explicitly; shared eight-frame animation resources are unchanged. Work frame timing follows the actor's Anim Speed. Visual pauses and local movement do not alter production or game time. Depletion cancels the cycle to idle; withdrawal and shift end clear cycle state.

Extended graphical WorksiteCommuteTest PASSED: arrival idle, frames 0 through 6, facing reversal, subsequent idle/walk/idle and position change, no output caused by visual progression, and depleted/withdrawal cleanup. Changed only the visual controller, its regression test and this report in this refinement.
