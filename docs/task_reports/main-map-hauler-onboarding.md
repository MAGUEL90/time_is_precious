# Main-map Hauler onboarding

Date: 2026-10-01
Branch: feature/process-workshop/main-map-access
Baseline: 94bf6a9; existing dirty map, art, construction and production work preserved.
Risk: LEVEL 2, bounded onboarding integration approved by the Game Director.
Status: normal hire/equip/haul integration PASSED - NEEDS HUMAN REVIEW.
Follow-up: 2026-10-03, starting Cart requested and supplied.

## Scope and implementation

The Game Director accepted the MVP proposal for one Hauler applicant in the existing
Job Board, with cart access through the existing equipment system. On 2026-10-03 the
Game Director requested a Cart for the Hauler. The initial map now supplies one city-owned
Cart through the existing equipment picker. Crafting and purchase prices remain unspecified.

InitialWorksites registers the existing Workshop Laborer and a Worksite Hauler using
stable citizen IDs. Each applicant is checked independently against existing citizens,
hired workers and dismissed workers. A previous Laborer hire therefore no longer prevents
the new Hauler from registering. Registration does not hire/equip/assign anyone.
The existing fixture opt-out still disables all registration.

After map initialization, InitialWorksites supplies the Cart to the existing CityToolStorage
provider under WorkStateRuntime. A stable unit ID and provider marker prevent additional
grants on repeated map visits, including after removal of that unit. The new Inspector
enable_initial_cart flag can disable this initial supply. The player must choose Equip;
the normal missing-cart guard remains active until then.

No map placement, gameplay managers, wages, role rules, project settings or save files
changed. CityToolStorage, Worker Hub, Daily selection and hauling remain the existing systems.

## Verification

Godot 4.5.1 GL Compatibility, 1200x675 development window, existing logical viewport:

- MainMapHaulerStartTest PASS: actual current ContentScene E at Job Board, both applicants,
  citizen-linked Hauler hire, existing wage, consumed applicants, missing-cart rejection,
  reload without duplicate hires/provider, dismissal retained across reload and fixture opt-out.
  Extended follow-up PASS: exactly one starting Cart; actual Worker Hub -> Tools -> Hauler
  -> Tool -> Cart -> Equip signal path; unique allocation and no Inventory cart; normal
  Laborer/Hauler Wood Daily setup and next-day shift; three received logs, nine produced
  logs conserved across output/storage, and E withdrawal. Reload preserves the equipped
  Cart, firing returns it to city stock, and removing it does not grant another on reload.
- InitialWorkshopStartTest PASS: existing Laborer/hiring/resource/construction route plus
  remaining unhired Hauler retained through reload. Test interaction now targets the authored
  Board collision component rather than the obsolete plot-root location. The first run's
  stale plot-root teleport failed to open the panel; that run is not counted as passing.
- WorkshopHiringRosterAudit PASS: existing workshop roster follows Job Board hire/dismissal.
- WorkerControlTest PASS: existing city equipment, unique cart allocation and worker management.
- PopulationEmploymentIntegrationTest PASS: existing employment lifecycle.
- Editor import/parse exit 0; current map scene loads. Native Job Board screenshot inspected:
  both applicants appear; existing truncated rows remain deferred UI polish.
- Whitespace and task diff reviewed. No commit, push or merge.

Existing ObjectDB shutdown diagnostics / 15 retained resources persist (16 on import).
Import's second editor reports port 9876 occupied. Passing runtime tests have no script errors.
The Cart follow-up tests ran beside the Game Director's active game and reported the
expected runtime bridge port 9877 conflict. Gameplay assertions pass independently of that
bridge. The existing game was kept running; add_tool_unit supplied its requested Cart,
the once-per-runtime marker was set, and read-back confirms exactly one available Cart.

## Files

Modified: startup/initial_worksites.gd, initial_workshop_start_test.gd, ROADMAP.md.
Cart follow-up also extends main_map_hauler_start_test.gd and records the initial supply
in game-concept.md. No layout or map transform changes.
Created: main_map_hauler_start_test.gd/.tscn (generated UID if imported), this report.
Deleted/renamed: none. Map/tiles and authored transforms remain unchanged.

## Remaining gates

Normal hire -> equip -> Daily haul -> stockpile withdrawal is now verified without a
test-owned cart or worker. Starting supply follows the existing city runtime lifetime.
Disk persistence, worksite state across map reload, food/clothing balance and normal Shekel
income remain outside this task.
