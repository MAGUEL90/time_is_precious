extends SceneTree

const HISTORY = preload("res://scenes/new_scenes/save_game/city_worksite_history.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func _run() -> void:
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/")
	var qa_root: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/").trim_suffix("/")
	if not _check(not qa_root.is_empty() and qa_root.is_absolute_path() and user_path.begins_with(qa_root + "/"), "Refusing non-QA user directory"):
		quit(1)
		return
	print("QA_USER_DIR=", user_path)
	var city = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	var clock = root.get_node("TimeComponentManager")
	clock.set_process(false)
	for frame in range(30):
		await physics_frame
	var works = city.get_node("YSortWorld/WorkerRuntime")
	var visuals = works.get_node("WorkerVisuals")
	visuals.set_process(false)
	var store = root.get_node("WorkStateRuntime/CitySave")
	var snapshot = store.snapshot
	var codec = load("res://scenes/new_scenes/save_game/city_save_values.gd").new()
	var adapter = load("res://scenes/new_scenes/save_game/city_save_worksites.gd").new()
	var db = root.get_node("WorkerDatabase")
	var citizen = root.get_node("CitizenManager").get_citizen("initial_workshop_laborer")
	citizen.satisfaction = 0.99
	citizen.employment_status = citizen.EmploymentStatus.APPLICANT
	root.get_node("Inventory").add_item("shekel", 9)
	var worker = db.hire_applicant("initial_workshop_laborer", 1, 9)
	if not _check(worker != null, "Paid worker fixture"):
		quit(1)
		return
	works.daily.tool_requirement = Callable() # Fixture only; production rules unchanged.
	var marker = works.get_node("WorksiteMarkers/WoodSite")
	if not _check(works.daily.toggle(&"WoodSite", worker.worker_id) and works.daily.start(&"WoodSite", works._drop_daily_output.bind(marker)), "Active Wood assignment fixture"):
		quit(1)
		return
	visuals._process(0.05)
	_check(not worker.physical_approach.is_empty() and not worker.physical_approach.arrived, "Worker is travelling")
	var document: Dictionary = snapshot.capture(city)
	if not _check(not document.is_empty() and snapshot.prepare(document, city), "Valid active control: " + snapshot.error):
		quit(1)
		return
	var raw: Dictionary = codec.decode(document.state)
	var now: int = int(raw.worksites.ledger.last_tick)
	# Synthetic owned state exercises conservation without advancing production.
	raw.worksites.sites.WoodSite.stock = 7
	raw.worksites.sites.WoodSiteB = {"stock": 0, "respawn_started_at": now, "respawn_due_at": now + 4320}
	raw.worksites.sites.WoodSiteC["offset"] = Vector2(48, 0)
	raw.workers.workers_by_id[worker.worker_id].profession_xp = 10
	var day: int = int(raw.worksites.ledger.stock_day)
	raw.worksites.jobs.WoodSite.stats[worker.worker_id] = {"days": [day], "output": 3}
	raw.worksites.contributions[worker.worker_id] = 3
	raw.worksites.productive_days[worker.worker_id] = [day]
	raw.worksites.journey_cache_day = day
	raw.worksites.worker_journeys["WoodSite:%s:%d" % [worker.worker_id, day]] = {"origin": worker.physical_approach.position, "target": worker.physical_approach.target, "start": float(now), "arrival": now + 60}
	raw.worksites.jobs.WoodSite.units = 2
	raw.worksites.jobs.WoodSite.progress[worker.worker_id] = 0.5
	raw.worksites.pending_output = {"WoodSiteB": 3}
	raw.worksites.pending_progress = {"WoodSiteB": [0.25]}
	raw.worksites.ground = [{"item_id": "wood_log", "quantity": 4, "position": Vector2(5, 5), "site_id": "WoodSiteB"}]
	var history: Array[Dictionary] = HISTORY.revisions()
	_check(history[0].size() == 10 and history[1].size() == 44 and history[2].size() == 50, "Published membership counts")
	for revision: int in range(history.size()):
		var source: Dictionary = raw.duplicate(true)
		for id: String in source.worksites.sites.keys():
			if not history[revision].has(id):
				source.worksites.sites.erase(id)
		var candidate: Dictionary = document.duplicate(true)
		candidate.state = codec.encode(source)
		var input_bytes: PackedByteArray = var_to_bytes(candidate)
		var live_before: Dictionary = snapshot.capture(city)
		if not _check(snapshot.prepare(candidate, city), "Historical active fixture %d: %s" % [revision, snapshot.error]):
			continue
		_check(var_to_bytes(candidate) == input_bytes and snapshot.capture(city) == live_before, "Prepare leaves source and live owners untouched")
		var expected: Dictionary = snapshot.prepared.worksites.duplicate(true)
		var expected_workers: Variant = codec.encode(snapshot.prepared.workers)
		var conserved: Dictionary = expected.duplicate(true)
		for id: String in expected.sites:
			if not source.worksites.sites.has(id):
				_check(expected.sites[id] == {"stock": works.sites[StringName(id)].deposit_capacity}, "Only approved initial stock: " + id)
				conserved.sites.erase(id)
		_check(conserved == source.worksites, "Every pre-existing worksite field conserved")
		_check(codec.encode(snapshot.prepared.workers) == codec.encode(source.workers), "Worker journey and paid contract conserved")
		snapshot.apply_prepared(city, false)
		_check(adapter.capture(works) == expected, "Apply restores all worksite ledgers and output")
		store.disk.path = "user://worksite_history/revision_%d.json" % revision
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://worksite_history"))
		for repeat: int in range(2):
			if not _check(store.save_checkpoint(), "QA disk save: " + store.last_error):
				break
			var file_before: String = FileAccess.get_file_as_string(store.disk.path)
			if not _check(store.load_checkpoint(), "QA disk load: " + store.last_error):
				break
			_check(FileAccess.get_file_as_string(store.disk.path) == file_before, "Load never rewrites source file")
			_check(adapter.capture(works) == expected, "Repeated roundtrip conserves stock/timers/jobs/output/RNG")
			var roundtrip: Dictionary = codec.decode(snapshot.capture(city).state)
			_check(codec.encode(roundtrip.workers) == expected_workers, "Repeated roundtrip conserves worker and contract")
		# Malformed membership and dangling references must fail before additions.
		var broken: Dictionary = source.duplicate(true)
		broken.worksites.sites.erase("WoodSite")
		_reject(snapshot, codec, document, broken, city, "Partial registry")
		broken = source.duplicate(true)
		broken.worksites.sites["UnknownWood"] = {"stock": 24}
		_reject(snapshot, codec, document, broken, city, "Foreign ID")
		broken = source.duplicate(true)
		broken.worksites.sites.WoodSite.stock = -1
		_reject(snapshot, codec, document, broken, city, "Invalid stock")
		broken = source.duplicate(true)
		broken.worksites.sites.WoodSiteB.erase("respawn_due_at")
		_reject(snapshot, codec, document, broken, city, "Incomplete respawn timer")
		if revision < 2:
			for field: String in ["pending_output", "pending_progress", "jobs", "ground", "worker_journeys"]:
				broken = source.duplicate(true)
				var missing: String = "WoodSitePoplar38"
				match field:
					"pending_output": broken.worksites.pending_output[missing] = 1
					"pending_progress": broken.worksites.pending_progress[missing] = [0.5]
					"jobs": broken.worksites.jobs[missing] = broken.worksites.jobs.WoodSite.duplicate(true)
					"ground": broken.worksites.ground[0].site_id = missing
					"worker_journeys":
						broken.worksites.journey_cache_day = int(broken.worksites.ledger.stock_day)
						broken.worksites.worker_journeys["%s:%s:%d" % [missing, worker.worker_id, broken.worksites.journey_cache_day]] = {"origin": Vector2.ZERO, "target": Vector2.ZERO, "start": 0.0, "arrival": now + 1440}
				_reject(snapshot, codec, document, broken, city, "Reference to absent source site: " + field)
		print("REVISION_CONSERVATION_PASS=", revision)
	# Earlier schema migration still composes with the explicit content history.
	var legacy: Dictionary = codec.decode(document.state)
	legacy.worksites.schema_version = 5
	for id: String in legacy.worksites.sites.keys():
		if id not in ["ClaySiteA", "WoodSite", "ReedSite", "StrawSite", "WaterSite"]:
			legacy.worksites.sites.erase(id)
	var legacy_document: Dictionary = document.duplicate(true)
	legacy_document.state = codec.encode(legacy)
	_check(snapshot.prepare(legacy_document, city), "Schema 5 registry still migrates: " + snapshot.error)
	_check(snapshot.prepared.worksites.sites.size() == 50 and snapshot.prepared.worksites.schema_version == 6, "Legacy schema uses existing v6 output")
	# A failed addition plan must not partially add/refill any site.
	var atomic: Dictionary = raw.worksites.duplicate(true)
	for id: String in atomic.sites.keys():
		if not history[0].has(id):
			atomic.sites.erase(id)
	var atomic_before: Dictionary = atomic.duplicate(true)
	var session = works.sites[&"WoodSitePoplar38"]
	var capacity: int = session.deposit_capacity
	session.deposit_capacity = 0
	_check(not adapter.migrate_legacy(atomic, works, now) and atomic == atomic_before, "Invalid late addition is atomic")
	session.deposit_capacity = capacity
	_check(adapter.migrate_legacy(atomic, works, now), "Valid addition plan applies")
	atomic.sites.WoodSitePoplar38.stock = 1
	atomic_before = atomic.duplicate(true)
	_check(adapter.migrate_legacy(atomic, works, now) and atomic == atomic_before, "Repeated migration cannot refill a spent new deposit")
	# Real arrival survives a checkpoint, not just the in-transit fixture.
	worker = db.get_worker_data("initial_workshop_laborer")
	for frame: int in range(700):
		await process_frame
		visuals._process(0.05)
		if worker.physical_approach.get("arrived", false):
			break
	_check(worker.physical_approach.get("arrived", false), "Restored Wood worker can arrive")
	var arrived: Dictionary = worker.physical_approach.duplicate(true)
	_check(store.save_checkpoint() and store.load_checkpoint(), "Arrived worker disk roundtrip: " + store.last_error)
	_check(db.get_worker_data(worker.worker_id).physical_approach == arrived, "Arrived approach conserved")
	# Simulate an old assigned job at a retained inactive marker. This does not
	# claim support for a moved/removed physical target or assign via gameplay UI.
	var retired: Dictionary = codec.decode(snapshot.capture(city).state)
	retired.worksites.jobs["WoodSiteB"] = retired.worksites.jobs.WoodSite
	retired.worksites.jobs.erase("WoodSite")
	retired.worksites.worker_journeys.clear()
	var retired_worker = retired.workers.workers_by_id[worker.worker_id]
	retired_worker.physical_approach.owner = "WoodSiteB"
	retired_worker.physical_approach.target = works.site_slot_destination_at_offset(&"WoodSiteB", 0, Vector2.ZERO)
	retired_worker.physical_approach.position = retired_worker.physical_approach.target
	var retired_document: Dictionary = document.duplicate(true)
	retired_document.state = codec.encode(retired)
	if _check(snapshot.prepare(retired_document, city), "Retained inactive assignment: " + snapshot.error):
		var retired_expected: Dictionary = snapshot.prepared.worksites.duplicate(true)
		# Existing daily activity resolution returns RESTING at inactive sites during
		# the restore refresh. Only that derived activity may normalize.
		var normalized_workers: Dictionary = codec.decode(codec.encode(snapshot.prepared.workers))
		normalized_workers.workers_by_id[worker.worker_id].current_work_status = worker.WorkStatus.RESTING
		var retired_workers: Variant = codec.encode(normalized_workers)
		snapshot.apply_prepared(city, false)
		_check(not works.is_world_site_available(&"WoodSiteB") and works.daily.jobs.has(&"WoodSiteB"), "Inactive site stays inactive and assigned")
		_check(adapter.capture(works) == retired_expected, "Inactive stock, output and assignment conserved")
		var actual_workers: Variant = codec.encode(codec.decode(snapshot.capture(city).state).workers)
		_check(actual_workers == retired_workers, "Inactive worker conserved except existing RESTING refresh")
		_check(store.save_checkpoint() and store.load_checkpoint(), "Inactive assignment disk roundtrip: " + store.last_error)
		_check(adapter.capture(works) == retired_expected, "Inactive roundtrip conserved")
		_check(codec.encode(codec.decode(snapshot.capture(city).state).workers) == retired_workers, "Inactive contract and journey survive disk roundtrip")
	# Moving a physical target remains unsupported and rejected without damage.
	var moved: Dictionary = codec.decode(snapshot.capture(city).state)
	moved.workers.workers_by_id[worker.worker_id].physical_approach.target += Vector2(100, 0)
	_reject(snapshot, codec, document, moved, city, "Changed physical target remains unsupported")
	# A future map edit cannot implicitly redefine any historical source set.
	var future: Dictionary = history[2].duplicate()
	future["FutureSite"] = true
	_check(not HISTORY.plan(history[0], future).ok, "Unregistered target expansion rejected")
	future = history[2].duplicate()
	future.erase("WoodSiteB")
	_check(not HISTORY.plan(history[0], future).ok, "Unregistered target removal rejected")
	print("WorksiteHistoryConservation: checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _reject(snapshot, codec, document: Dictionary, raw: Dictionary, city: Node, label: String) -> void:
	var candidate: Dictionary = document.duplicate(true)
	candidate.state = codec.encode(raw)
	var before: PackedByteArray = var_to_bytes(candidate)
	var live: Dictionary = snapshot.capture(city)
	_check(not snapshot.prepare(candidate, city), label + " rejected")
	_check(var_to_bytes(candidate) == before and snapshot.capture(city) == live, label + " rejection is non-mutating")
