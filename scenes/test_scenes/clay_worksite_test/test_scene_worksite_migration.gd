extends Node2D

## Focused, isolated disk migration and fractional-gathering regression.
const STORE = preload("res://scenes/test_scenes/clay_worksite_test/worksite_save_store.gd")
const LABORER: String = "delivery_laborer"
var failures: int = 0
var fixture: Node
var registry: Dictionary
var probe: Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.is_paused = true
	var setup = preload("res://scenes/test_scenes/clay_worksite_test/test_scene_hauler_delivery_setup.tscn").instantiate()
	setup.persistence_enabled = false
	add_child(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	fixture = setup.fixture
	registry = {"storage_a": setup.destination_a, "storage_b": setup.destination_b}
	fixture._close_inspector()
	var citizen := CitizenData.new()
	citizen.citizen_id = LABORER
	citizen.display_name = "Arad"
	citizen.profession = WorkerData.Profession.LABORER
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	citizen.satisfaction = 0.2
	CitizenManager.citizens_by_id[LABORER] = citizen
	_expect(fixture.daily.toggle(&"ClaySiteA", LABORER), "Laborer is selected for gathering.")
	if not fixture.daily.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA"))):
		_expect(false, "A gathering assignment starts.")
		_finish()
		return
	TimeComponentManager.advance_minutes(1440 + 7 * 60 + 37 - fixture.daily.now())
	# Daily needs settlement during the time skip can change Satisfaction.
	CitizenManager.citizens_by_id[LABORER].satisfaction = 0.2
	probe = STORE.new()
	probe.path = "user://worksite_migration_test/%d_%d/save.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	probe.fixture = fixture
	probe.destinations = registry
	probe.enabled = true
	var current: Dictionary = probe.codec.capture(fixture, registry)
	_expect(probe.codec.validate(current, fixture, registry), "The current fixture is a valid v2 checkpoint: " + probe.codec.error)
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 1
	legacy.jobs.ClaySiteA.progress[LABORER] = 7
	for group: String in ["workers", "dismissed", "citizens"]:
		for data: Dictionary in legacy[group].values():
			data.reliability = 0.5
	var legacy_bytes: String = JSON.stringify(legacy, "", true, true)
	_write(probe.path, legacy_bytes)
	_expect(probe.load_now() == "loaded", "A v1 checkpoint loads from disk: " + probe.status)
	_expect(FileAccess.get_file_as_string(probe.path) == legacy_bytes, "Loading v1 does not rewrite the original bytes.")
	_expect(fixture.daily.jobs[&"ClaySiteA"].progress[LABORER] == 7 and is_equal_approx(CitizenManager.citizens_by_id[LABORER].satisfaction, 0.2), "Legacy integer progress and Satisfaction survive migration.")
	_expect(probe.save_now(), "An explicit save upgrades the prototype checkpoint.")
	_expect(FileAccess.get_file_as_string(probe.path + ".bak") == legacy_bytes, "The v1 checkpoint remains in the normal backup.")
	var upgraded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(probe.path))
	var omitted: bool = upgraded.schema_version == 2
	for group: String in ["workers", "dismissed", "citizens"]:
		for data: Dictionary in upgraded[group].values():
			omitted = omitted and not data.has("reliability")
	_expect(omitted, "The v2 writer omits retired fields from all worker and citizen records.")
	for kind: String in ["worker_missing", "worker_type", "worker_outside", "citizen_missing", "citizen_type", "citizen_outside"]:
		var invalid: Dictionary = legacy.duplicate(true)
		var record: Dictionary = invalid.workers[LABORER] if kind.begins_with("worker") else invalid.citizens[LABORER]
		if kind.ends_with("missing"):
			record.erase("reliability")
		elif kind.ends_with("type"):
			record.reliability = "0.5"
		else:
			record.reliability = 1.01
		_expect(not probe.codec.validate(invalid, fixture, registry), "Invalid v1 Reliability is rejected: " + kind)
	var unexpected: Dictionary = upgraded.duplicate(true)
	unexpected.workers[LABORER].reliability = 0.5
	_expect(not probe.codec.validate(unexpected, fixture, registry), "A v2 checkpoint rejects the retired field.")
	var invalid_progress: Dictionary = upgraded.duplicate(true)
	for amount: Variant in [-0.1, fixture.sites[&"ClaySiteA"].minutes_per_unit, INF, "7"]:
		invalid_progress.jobs.ClaySiteA.progress[LABORER] = amount
		_expect(not probe.codec.validate(invalid_progress, fixture, registry), "Invalid partial progress is rejected: " + str(amount))
	fixture.daily.jobs[&"ClaySiteA"].progress[LABORER] = 9.35
	_expect(probe.save_now(), "Fractional progress is saved to disk.")
	fixture.daily.jobs[&"ClaySiteA"].progress[LABORER] = 0.0
	_expect(probe.load_now() == "loaded", "The v2 fractional checkpoint loads from disk.")
	var job: Dictionary = fixture.daily.jobs[&"ClaySiteA"]
	_expect(is_equal_approx(float(job.progress[LABORER]), 9.35), "Fractional progress is not truncated on restore.")
	var stock_before: int = fixture.sites[&"ClaySiteA"].stock
	var output_before: int = int(job.stats[LABORER].output)
	TimeComponentManager.advance_minutes(1)
	_expect(fixture.sites[&"ClaySiteA"].stock == stock_before - 1 and int(job.stats[LABORER].output) == output_before + 1 and is_equal_approx(float(job.progress[LABORER]), 0.2), "The next low-Satisfaction minute completes exactly one item and keeps the remainder.")
	probe.free()
	_finish()

func _write(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _finish() -> void:
	print("WorksiteMigrationTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
