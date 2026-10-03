## Current debug UI status (2026-09-27)

At the user's request, all embedded debug controls and handlers were removed from Workshop Plot, Workshop Menu and Job Board: material supply, Shekel supply, bag capacity and Hauler/cart supply. The standalone debug bag script and obsolete DebugHaulerTest were removed. Earlier debug sections below are historical verification, not current UI capabilities. Future debug controls should live outside gameplay panels. Player-needs protection and time shortcuts remain active by explicit user choice. Existing fixture-owned supplies remain isolated in tests. No commit was made.

# Shared resource worksites and hiring audit

Date: 2026-09-26. Branch: feature/process-workshop/main-map-access. Baseline: 94bf6a9.
Status: PASSED - NEEDS HUMAN REVIEW for the corrected worksite integration.
Scope: approved reuse/generalization of Clay Worksite, replacing the earlier separate Gather component; read-only hiring UI audit. Existing construction, debug-needs and mudbrick work preserved.

## Final implementation

Wood, Reed, Straw and Water markers now live under the existing Content Worksites/WorksiteMarkers node. They use the same inspector, Player Hourly selection (3/6/9 hours), daily workers, two-worker capacity, commute, equipment requirements, ground output/overflow, interruption behavior, XP attribution and hauling as Clay. No new manager or parallel interaction dispatch remains.

Configuration-only resource_site_marker.gd exposes item_id, minutes_per_unit and daily_stock. Provisional rates remain Wood 20 min/unit, Reed 7.5, Straw 10, Water 5. New sites use the existing 72-unit daily stock pattern; these are editable MVP values, not final balancing. Clay's defaults and authored locations remain unchanged.

Sessions and the daily scheduler use the selected resource/rate; fractional progress survives daily ticks. Ground stacks, transport cargo and progress labels retain resource identity. Routes capture their item ID when created, so simultaneous routes do not use one shared mutable cargo item. Existing Storage A/B remain configured for clay; a resource's Hauler needs a matching destination. Their backend now reports this item filter to the destination-choice UI. City Storage still excludes raw resources. Tests use separate matching destinations to verify all four routes; no city-ownership rule was loosened.

Removed the six uncommitted script/scene/UID files under scenes/material_gathering and its Player dispatch after the shared-worksite replacement passed. InitialWorksites now holds only the existing Job Board and one-time applicant bootstrap.

## Job Board audit

Follow-up correction approved by the user: gameplay no longer automatically loads the three legacy worker resources or seeds Belum. Existing resource files and the explicit fixture loader remain available to isolated tests. This removes builders that bypassed hiring from all consumers of the roster, not just the plot UI. The main-map start test no longer clears the worker database or overrides the Hauler flag before testing startup.

Verification: WorkshopHiringRosterAudit passes with the untouched default roster (empty before hire, exactly the hired applicant afterward), preserves the same worker on map reload, and removes dismissed workers from builder options. InitialWorkshopStartTest passes recruitment, worksite collection and construction. ContentWorksitesIntegrationTest and MudbrickProductionChainIntegrationTest pass with explicit legacy fixture setup. Runtime logs also report the MCP bridge cannot bind port 9877 and the existing shutdown resource diagnostics; these do not prevent the gameplay assertions from completing. The interactive WorkState smoke fixture was updated to opt into its legacy worker but was not exercised in this follow-up.

The map instantiates scenes/job_board/job_board.tscn, which opens scenes/ui/job_board_ui/job_board_ui.tscn and calls the existing WorkerDatabase.hire_applicant API. This UI was introduced by efa1fe7. The last script change at 3dcabb6 changes row separators, not a visual overhaul. It is still the basic applicant list/Hire/Close screen.

Production WorkerHubUI handles existing workers and workshop job selection. The larger worker_control screen handles post-hire status, tools, levels, details and dismissal. Neither contains applicant recruitment. A search of reachable local Git history found no newer alternate hiring scene. The recently placed board did not replace or downgrade a newer screen. No Job Board presentation changes were made in this correction.

## Verification

Root reviewed the actual delegated hauling diff and current source/history for the hiring audit. Godot 4.5.1 GL Compatibility runs passed:

- InitialWorkshopStartTest: real Job Board hire; all four resources via the shared E/Hourly inspector; cancellation; double-start guard; correct elapsed time, output and overflow; resources collected through worksite UI then used to build; hired worker released; reload without duplicate applicant. Rendered Wood Site confirmation inspected.
- ResourceWorksitesTest: four concurrent Laborer/Hauler teams using the existing scheduler; fractional Reed rate; correct cargo/resource identities; matched destination receipt; per-site ground+delivered conservation; City Storage rejects raw resources.
- ClayWorksiteGatheringTest, ClayWorksiteDailyTest, ContentWorksitesIntegrationTest, and the main-map two-cycle MudbrickPlayerFlowTest.
- WorksiteSaveTest write and read in separate processes with isolated APPDATA under the session visualization directory. Existing Clay save format and invalid-file protections pass; this does not add persistence for other resources.

The first ResourceWorksitesTest run passed the CityStorageArea node instead of its DeliveryPoint to a typed helper. That fixture call was corrected and the complete rerun passed. The implementation subagent additionally reported ClayWorksiteHaulerTest passing after a failed native headless run; root acceptance relies on the GL integration/regression results above. Existing ObjectDB shutdown resource diagnostics persist. Diff whitespace checks passed.

## Remaining limits

UI polish, resource artwork/final placement, generic disk persistence, full daily-loop balance and normal gameplay income remain pending. Four matching authored storage destinations now exist (see follow-up below). Existing main-map worksite lifetime behavior is unchanged: stockpiles are scene-local and are not retained through map reloads. No commit, push or merge performed.

## Resource storage access follow-up (2026-09-27)

Wood, Reed, Straw and Water now each have a matching 96-unit stockpile in Content Worksites, reusing the existing delivery endpoint and stockpile capacity. Existing Clay storage also gains E withdrawal. E transfers only what fits in personal inventory; remaining stock stays in storage. Feedback reports the amount taken, an empty stockpile, or a full bag. Player access checks live range, overlap, movement and modal/transition state. The existing workshop deposit API accepts the collected materials.

ResourceWorksitesTest now uses the actual authored destinations instead of creating test destinations. It passes four simultaneous resource deliveries, correct cargo identity, full-bag rejection, partial E withdrawal, repeated empty withdrawal, conservation and exact workshop deposit. The first E test exposed the carrier-only collision mask; stockpile access now also detects the Player layer, and the complete rerun passed. ContentWorksitesIntegrationTest and InitialWorkshopStartTest pass. Render inspection prompted compact two-line labels to avoid overlaps. Existing shutdown diagnostics persist.

The Hauler teams and carts in ResourceWorksitesTest are fixture-owned. The user subsequently approved debug access for playtesting: Job Board now offers a debug-build-only "Debug: Hauler + cart" button while CityToolStorage exists. Clicking registers one Debug Hauler applicant and supplies one Debug Cart to shared City Storage. Hiring and equipping still use the existing APIs/UI. Stable IDs and a runtime grant marker prevent repeated grants, including after map reload; dismissed workers are not silently rehired. Normal opening supplies nothing.

DebugHaulerTest verifies repeat clicks, ordinary hiring, cart allocation, actual Wood Site delivery to its authored storage, and no duplication after map reload. The first test incorrectly expected an empty success string from equip(); its assertion now checks the actual allocated worker ID.

## Debug Shekel follow-up

The user also approved a session-only debug bag capacity of 1,000. A shared debug-only button is available in both the plot construction/progress panel and the built workshop menu. Activation preserves contents and never lowers capacity; normal startup remains 100. Restarting the game clears the override. Item weights and normal balance are unchanged. WorkshopConstructionUITest verifies default capacity, activation, repeated clicks, preserved contents, capacity for 36 water jars, and retention through workshop completion. Both rendered panels were inspected; MudbrickPlayerFlowTest also passed again at normal capacity.

At the player's request, the built workshop menu now includes a debug-build-only button to top up personal inventory to 100 Shekel. It checks bag capacity, preserves other items and higher balances, and can replenish spent currency without stacking repeated grants. No shortcut or normal income rule was added. MudbrickPlayerFlowTest passed full-bag rejection, retry, repeat, partial replenishment, higher-balance preservation and two production/payment cycles. The rendered menu was inspected; the button fits within the viewport. Existing shutdown resource diagnostics persist.
