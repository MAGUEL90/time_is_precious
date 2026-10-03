# Independent plot clearing and construction

2026-09-28, feature/process-workshop/main-map-access. Explicitly requested separation
of the two plots and clearer work-start wording. No commit/merge.

Root cause: every plot resolved MainWorkshopConstruction and used the same worker
order ID. Added stable exported plot_id values main_workshop and workshop_2 to
the authored instances. Each resolves its own retained state and construction
order. Primary identity retains the legacy runtime name; no save files are changed.
Clearing, construction, reservations and deadlines now progress independently.
The existing shared workshop production/storage systems remain outside this fix.

The clearing action now says Start Cleaning. Rendered panel checked: label fits.
Existing layout, worker rules, material costs and durations preserved.

Godot 4.5.1 Compatibility at 1200x675: WorkshopPlotIndependenceTest,
WorkshopClearingTest, WorkshopConstructionUITest and WorkshopConstructionTest PASS.
New coverage: untouched plot remains uncleared; one worker cannot serve both;
staggered clearing and worker release; independent construction completion;
correct state identities after map reload; only completed plot gets BuiltWorkshop.
git diff --check passed. Existing ObjectDB/resource-in-use shutdown diagnostics remain.

New authored plot copies must receive distinct stable plot_id values in Inspector.
Restart the current play session to load the changed scenes/scripts. Runtime state
survives map changes, not restarting the application. Status: PASSED - NEEDS HUMAN REVIEW.
