extends Node

## Tests actual city owners with an isolated XDG profile and reconstructed v5 data.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	_check(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").begins_with(data_root.trim_suffix("/") + "/"), "Use a disposable XDG profile.")
	if failures:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	var city: Node2D = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	for i: int in range(3):
		await get_tree().process_frame
	var work: Node = city.get_node("YSortWorld/WorkerRuntime")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var clock_minute: int = work.daily.now()
	var source: Dictionary = store.snapshot.capture(city)
	var codec = VALUES.new()
	var legacy: Dictionary = codec.decode(source.state)
	legacy.worksites.schema_version = 5
	for id: String in ["ClaySiteB", "ReedSiteB", "WoodSiteB", "WoodSiteC"]:
		legacy.worksites.sites.erase(id)
	legacy.worksites.sites.ClaySiteA.stock = 0
	legacy.worksites.sites.WoodSite.stock = 240
	legacy.worksites.sites.StrawSite.stock = 77
	legacy.worksites.pending_output["ClaySiteA"] = 5
	source.state = codec.encode(legacy)
	var before: String = JSON.stringify(source)
	var city_before: int = int(work.city_tools.items.get("clay_lump", 0))
	var added_marker: Node2D = work.get_node("WorksiteMarkers/ClaySiteB")
	var added_origin: Vector2 = added_marker.position
	added_marker.position = work.TEMP_RELOCATION_POINTS[0] # Different live state before loading the old save.
	_check(store.snapshot.prepare(source, city), "A v5 empty deposit and legacy straw save migrates: " + store.snapshot.error)
	if failures:
		get_tree().quit(1)
		return
	var saved: Dictionary = store.snapshot.prepared.worksites
	_check(saved.sites.ClaySiteA.stock == 0 and saved.sites.ClaySiteA.respawn_started_at == clock_minute and saved.sites.ClaySiteA.respawn_due_at == clock_minute + 4320, "Legacy depletion receives a conservative three-day deadline from the checkpoint.")
	_check(saved.sites.WoodSite.stock == 240 and saved.sites.StrawSite.stock == 77, "Legacy stock above the new test capacity and legacy straw remain unchanged.")
	_check(saved.sites.ClaySiteB.stock == 36 and saved.sites.ReedSiteB.stock == 40 and saved.sites.WoodSiteB.stock == 24 and saved.sites.WoodSiteC.stock == 24, "The four added deposits begin with their provisional reserves.")
	_check(int(saved.pending_output.ClaySiteA) == 5 and JSON.stringify(source) == before, "Pending city-owned output and the original document are unchanged.")
	store.snapshot.apply_prepared(city)
	_check(work.sites[&"ClaySiteA"].stock == 0 and work.sites[&"ClaySiteA"].respawn_due_at == clock_minute + 4320 and int(work.daily.pending_output[&"ClaySiteA"].quantity) == 5, "Applying the migration preserves the deadline and pending output.")
	_check(added_marker.position == added_origin, "A new site missing from the old file restores at its authored test origin, independent of the live city.")
	_check(store.snapshot.prepare(source, city), "The same old document can be staged twice.")
	store.snapshot.apply_prepared(city)
	_check(int(work.daily.pending_output[&"ClaySiteA"].quantity) == 5 and int(work.city_tools.items.get("clay_lump", 0)) == city_before, "Repeated migration neither delivers nor duplicates pending output.")
	var current: Dictionary = store.snapshot.capture(city)
	var invalid: Dictionary = codec.decode(current.state)
	invalid.worksites.sites.ClaySiteA.respawn_due_at = clock_minute + 1
	current.state = codec.encode(invalid)
	_check(not store.snapshot.prepare(current, city) and work.sites[&"ClaySiteA"].respawn_due_at == clock_minute + 4320, "A corrupt timer is rejected without changing the live state.")
	var wrong_site: Dictionary = codec.decode(store.snapshot.capture(city).state)
	wrong_site.worksites.sites.ClaySiteA.offset = work.TEMP_RELOCATION_POINTS[0] - Vector2(work._site_origins[&"WoodSiteC"])
	current.state = codec.encode(wrong_site)
	_check(not store.snapshot.prepare(current, city), "A temporary offset belonging to another site cannot move this deposit to an unverified position.")
	# Old outer schemas could allow a lagging ledger; timer validation should
	# use the saved game clock, not misclassify this as a future depletion.
	var lagged: Dictionary = codec.decode(source.state).worksites
	lagged.ledger.last_tick = clock_minute - 1
	var adapter = store.snapshot._sites
	_check(adapter.migrate_legacy(lagged, work, clock_minute) and adapter.validate(lagged, work, WorkerDatabase.workers_by_id, WorkerDatabase.dismissed_workers, clock_minute), "A legacy lagging ledger does not invalidate a timer anchored to the checkpoint clock.")
	print("TimedSiteMigrationTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
