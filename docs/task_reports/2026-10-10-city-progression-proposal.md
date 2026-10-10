# City progression MVP — approved playtest design

Branch: feature/time-world/city-progression
Baseline: 3c00ff0, validated raid cycle. User authorized implementation after reviewing the numbers (2026-10-10). See the implementation report for verification.

## User-approved intent

City progress reaches 100% to allow a level increase. A ruined/unbuilt wall reduces progress. Later city development increases raider numbers and variety. Keep this feature separate from raid MVP. City Hub is the entry point.

## Approved playtest values

Start level 1 with 0/100 progress.
At a daily settlement with residents, award 5 points each for daily food fulfillment, full clothing coverage, and average resident satisfaction >=70%.
Subtract 5 points per day while wall HP is zero (unbuilt or breached). A new breach subtracts another 10 points once. Clamp progress to 0–100.
At 100, expose a Level Up button; increment level and reset progress to 0. No level loss. No new building unlocks or costs in this pass.
Level 1 maps to Early raiders, 2 to Developing, 3+ to Advanced. A departed party retains its existing composition/strength/arrival.

Food should mean that day's actual needs were fulfilled, not leftover stock after consumption; implementation must avoid penalizing a city that stocked exactly enough. Daily scoring uses completed settlement results for residents; new applicants join the next daily cohort.

## Reviewed integration points

- CitizenNeedsManager already emits needs_changed after daily settlement and exposes last_processed_day, fulfillment counts and last_needs_results. Use completed daily results with a last-awarded-day guard; deposits and UI opens must never award points.
- Existing WorkStateRuntime can host one runtime progression ledger, following the raid ledger lifetime. No new autoload or project settings needed. This is session state, not a claim of disk save support.
- RaidState.set_city_threat_stage already accepts Early/Developing/Advanced and preserves the departed party. Call on actual level changes; keep Debug controls explicitly temporary.
- Detect one transition into a breached wall per raid; do not deduct again on repeated changed signals, rebuilding, or map re-entry. A wall starting ruined receives only the daily missing-wall penalty.
- City Hub should expose compact level/progress/Level Up presentation and a short daily breakdown. Supply remains an observer of the same needs data.

## Acceptance checks after approval

1. Zero residents cannot farm positive points; daily scoring uses settled residents, including linked employed residents.
2. Daily settlement counts once, including sleep/time advancement and scene reload; plain needs refresh/deposit does not count.
3. Missing-wall and breach deductions clamp at zero and cannot repeat per event.
4. At 100, one Level Up click advances exactly once, resets progress, and updates future raid stage only.
5. Existing travel, inspection, stock, satisfaction, construction and recovery checks still pass.
6. City Hub layout remains within 400x225 logical viewport with font sizes 6/12 and existing pixel assets.

Implementation authorized by the user: “oke anda bisa lanjutkan progres city”, following review of these proposed values.
