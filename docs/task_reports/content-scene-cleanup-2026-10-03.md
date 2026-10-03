# ContentScene cleanup — 2026-10-03

The Game Director requested two workshop plots and the Job Board remain, with
the worksite/storage map objects and the "Bekas Workshop" world title removed.

ContentScene now instances workshop_worker_runtime.tscn instead of the populated
main_map_worksites.tscn. The runtime reuses existing worker management, city tool
provider and worker presentation with empty site and destination collections.
It introduces no replacement gathering or economy rules. Original worksite and
stockpile scenes remain available for later map authoring. Internal workshop
production storage is unchanged.

Ground tiles and the two plot/Job Board positions are preserved. The subsequently
saved player spawn at (-258, -392) is included in the content checkpoint.

Verified after cleanup in native Godot 4.5.1:

- WorkshopPlotAccessTest: PASS, including no active resource sites or destinations
  and no uncleared-plot debug title.
- WorkshopConstructionUITest: PASS.
- WorkshopWorkerPresenceTest: PASS, including worker entry, activity and completion
  presentation.

The existing ObjectDB and 15-resources-in-use exit diagnostics remain. Earlier
BranchAcceptanceFlowTest, MainMapHaulerStartTest and NormalStartProductionAudit
results in the other reports refer to the populated map. Those fixtures still
expect YSortWorld/Worksites and need a dedicated populated-map fixture before
reuse; they are not claimed as passing on this cleaned map. Resource collection
and hauling are intentionally absent from the current map. Debug supplies remain
available for workshop testing.
