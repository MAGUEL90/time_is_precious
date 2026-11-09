extends Node

## Disposable, deterministic numerical regression. No authored scene or real save is edited.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const STARTERS = preload("res://scenes/content_scene/startup/initial_worksites.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const IDS: Array[String] = [STARTERS.APPLICANT_ID, STARTERS.HAULER_APPLICANT_ID, STARTERS.CITY_HAULER_APPLICANT_ID]
const SLOT: String = "user://satisfaction_boundary/checkpoint.json"
const BELOW_BITS: String = "ffffffffffffdf3f"
const HALF_BITS: String = "000000000000e03f"
const ABOVE_BITS: String = "010000000000e03f"
var failures: int = 0
var launched: bool = false
var city: Node
var store: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _value(bits: String) -> float:
	return bits.hex_decode().decode_double(0)

func _phase() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--boundary-phase="):
			return argument.trim_prefix("--boundary-phase=")
	return "full"

func _run() -> void:
	_expect(_safe_profile(), "Use separate disposable XDG directories under citysave_suite_qa.")
	if failures > 0:
		_finish()
		return
	var phase: String = _phase()
	var continuing: bool = phase in ["read", "legacy", "legacy_neighbors"]
	_expect(FileAccess.file_exists(SLOT) == continuing, "The checkpoint existence agrees with the isolated test phase.")
	if failures > 0:
		_finish()
		return
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = SLOT
	menu.session_started.connect(func(is_continue: bool): launched = is_continue == continuing)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	for _frame: int in range(5):
		await get_tree().process_frame
	if continuing:
		menu.continue_button.pressed.emit()
	else:
		menu.new_game_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched, "The actual Start Menu launches the requested session.")
	if not launched:
		_finish()
		return
	TimeComponentManager.set_process(false)
	city = get_tree().current_scene
	var player: Player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	store = WorkStateRuntime.get_node("CitySave")
	if phase in ["legacy", "legacy_neighbors"]:
		_test_legacy()
	elif phase == "read":
		var original: Dictionary = _files()
		_expect(TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute == 737,
			"Fresh-process Continue restores the checkpoint at minute 137 after New Game.")
		_check_starters(0.55 - 0.05 * 137.0 / 1440.0, 3, "Fresh-process Continue preserves exact accumulated satisfaction.")
		_expect(TimeComponentManager.advance_minutes(1303), "Continue completes the remaining shortage interval.")
		_check_starters(0.5, 3, "Cross-process Continue reaches the same exact 50% boundary.")
		_expect(_files() == original, "Continue and elapsed simulation do not rewrite checkpoint bytes.")
	elif phase == "write":
		_expect(TimeComponentManager.advance_minutes(137), "Advance an uneven 137-minute interval before saving.")
		_expect(store.save_checkpoint(), "Save the mid-interval exact accumulator: " + store.last_error)
	else:
		_test_thresholds_and_codec()
		_check_starters(0.55, 3, "New Game starts with the actual three 55% applicants.")
		for id: String in IDS:
			var needs: Dictionary = CitizenNeedsManager.get_person_needs_summary(id)
			_expect(not needs.food and not needs.clothing and not needs.shelter, "No service is silently supplied to " + id)
		_expect(store.save_checkpoint(), "Save the genuine New Game state.")
		var start_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SLOT)
		_expect(TimeComponentManager.advance_minutes(1440), "Actual clock advances exactly 1440 shortage minutes.")
		_check_starters(0.5, 3, "Exactly one shortage day reaches 50%, not 140 ULPs below.")
		_expect(store.save_checkpoint(), "Save the exact boundary: " + store.last_error)
		var boundary: Dictionary = _files()
		_expect(TimeComponentManager.advance_minutes(1), "Advance a real minute below the threshold.")
		_check_starters(0.55 - 0.05 * 1441.0 / 1440.0, 0, "A further unmet minute really removes eligibility.")
		for _repeat: int in range(3):
			_expect(store.load_checkpoint(), "Repeated Continue restores the boundary: " + store.last_error)
			_check_starters(0.5, 3, "Repeated Continue preserves exact threshold and identities.")
			_expect(_files() == boundary, "Repeated Continue leaves every checkpoint file byte unchanged.")
		# Same initial state, deliberately irregular split intervals and repeated save/load.
		var start_document: Dictionary = JSON.parse_string(start_bytes.get_string_from_utf8())
		_expect(store.snapshot.prepare(start_document, city), "Stage the saved New Game for subdivision comparison.")
		store.snapshot.apply_prepared(city)
		for minutes: int in [1, 136, 314, 510, 478, 1]:
			_expect(TimeComponentManager.advance_minutes(minutes), "Advance subdivision of %d minutes." % minutes)
			_expect(store.save_checkpoint(), "Persist the numerical accumulator between subdivisions: " + store.last_error)
			var part_files: Dictionary = _files()
			var before: Array = _satisfactions()
			for _repeat: int in range(2):
				_expect(store.load_checkpoint(), "Continue a non-round subdivision: " + store.last_error)
				_expect(_satisfactions() == before and _files() == part_files, "Continue is bit-exact and read-only within an interval.")
		_check_starters(0.5, 3, "Subdivided save/Continue path equals uninterrupted exact 50%.")
		_test_saved_neighbors()
		_test_standalone_dismissal_capture()
		_test_corrupt_records()
		_test_invalid_live_capture()
		_test_integrator_subdivision()
		_test_retry_purity()
	_finish()

func _test_thresholds_and_codec() -> void:
	for bits: String in [BELOW_BITS, HALF_BITS, ABOVE_BITS]:
		var person := CitizenData.new()
		person.citizen_id = "numerical_threshold"
		person.population_status = CitizenData.PopulationStatus.RESIDENT
		person.profession = WorkerData.Profession.LABORER
		person.satisfaction = _value(bits)
		person.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
		var expected: bool = bits != BELOW_BITS
		_expect(person.can_apply_for_work() == expected, "Apply uses the unchanged exact comparator for " + bits)
		person.employment_status = CitizenData.EmploymentStatus.APPLICANT
		_expect(person.can_be_hired() == expected, "Hire uses the unchanged exact comparator for " + bits)
		var codec = VALUES.new()
		var encoded: Variant = codec.encode(person)
		var restored: CitizenData = codec.decode(JSON.parse_string(JSON.stringify(encoded, "", true, true)))
		_expect(codec.error.is_empty() and _bits(restored.satisfaction) == bits and restored.can_be_hired() == expected,
			"Citizen satisfaction JSON roundtrip preserves all binary64 bits: " + bits)
		var worker := WorkerData.new()
		worker.worker_id = "numerical_unlinked"
		worker.satisfaction = _value(bits)
		encoded = codec.encode(worker)
		var restored_worker: WorkerData = codec.decode(JSON.parse_string(JSON.stringify(encoded, "", true, true)))
		_expect(codec.error.is_empty() and _bits(restored_worker.satisfaction) == bits, "Unlinked worker satisfaction roundtrip is exact: " + bits)
	for invalid: Variant in ["", "000000000000E03F", "000000000000f07f", "000000000000f87f", "not-a-binary64!!", 0.5]:
		var codec = VALUES.new()
		codec.decode({"$type": "float64", "value": invalid})
		_expect(not codec.error.is_empty(), "Malformed or nonfinite exact float is rejected.")

func _test_saved_neighbors() -> void:
	for index: int in IDS.size():
		CitizenManager.get_citizen(IDS[index]).satisfaction = _value([BELOW_BITS, HALF_BITS, ABOVE_BITS][index])
	var stale: Dictionary = CitizenNeedsManager.satisfaction_accumulators.duplicate(true)
	_expect(store.save_checkpoint(), "External satisfaction updates save without stale-anchor rejection: " + store.last_error)
	_expect(CitizenNeedsManager.satisfaction_accumulators == stale, "Capture never mutates a live accumulator dictionary.")
	var saved: Dictionary = _files()
	for _repeat: int in range(3):
		_expect(store.load_checkpoint(), "Load adjacent saved threshold values: " + store.last_error)
		_expect(_bits(CitizenManager.get_citizen(IDS[0]).satisfaction) == BELOW_BITS
			and _bits(CitizenManager.get_citizen(IDS[1]).satisfaction) == HALF_BITS
			and _bits(CitizenManager.get_citizen(IDS[2]).satisfaction) == ABOVE_BITS,
			"No saved below-threshold neighbor is promoted or rounded by Continue.")
		_expect(CitizenManager.get_all_applicants().size() == 2 and _files() == saved, "Only exact-half and above remain eligible; disk stays unchanged.")

func _test_standalone_dismissal_capture() -> void:
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var worker := WorkerData.new()
	worker.worker_id = "boundary_standalone_worker"
	worker.display_name = "Boundary Standalone"
	worker.profession = WorkerData.Profession.LABORER
	worker.satisfaction = 0.8
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	CitizenNeedsManager._advance_satisfaction_to_minute(now)
	_expect(CitizenNeedsManager.satisfaction_accumulators.has(worker.worker_id), "A standalone worker receives one numerical accumulator.")
	_expect(WorkerDatabase.dismiss_worker(worker.worker_id), "The ordinary idle legacy-worker dismissal succeeds.")
	var live: Dictionary = CitizenNeedsManager.satisfaction_accumulators.duplicate(true)
	_expect(store.save_checkpoint(), "Saving immediately after dismissal cannot fail on inactive numerical history: " + store.last_error)
	_expect(CitizenNeedsManager.satisfaction_accumulators == live, "Dismissal capture only sanitizes a staged copy.")
	_expect(store.load_checkpoint() and not WorkerDatabase.has_worker_data(worker.worker_id)
		and WorkerDatabase.dismissed_workers.has(worker.worker_id)
		and not CitizenNeedsManager.satisfaction_accumulators.has(worker.worker_id),
		"Continue retains dismissal and does not restore inactive numerical history.")

func _test_corrupt_records() -> void:
	_expect(TimeComponentManager.advance_minutes(1), "Establish a fresh record after the saved external updates.")
	_expect(store.save_checkpoint(), "Save consistent records for malformed-record testing.")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SLOT))
	var files: Dictionary = _files()
	var before: Array = _satisfactions()
	var live_before: Dictionary = store.snapshot.capture(city)
	for defect: String in ["unknown", "future", "wrong_cursor", "bad_bits", "bad_minutes", "extra_field", "mismatch", "missing_ledger", "old_header"]:
		var codec = VALUES.new()
		var raw: Dictionary = codec.decode(document.state)
		var ledger: Dictionary = raw.needs.satisfaction_accumulators
		var record: Dictionary = ledger[IDS[0]]
		match defect:
			"unknown": ledger["not_a_person"] = record.duplicate()
			"future": record.cursor += 100000
			"wrong_cursor": record.cursor -= 1
			"bad_bits": record.anchor_bits = "000000000000f87f"
			"bad_minutes": record.minutes = 28801
			"extra_field": record["unexpected"] = true
			"mismatch": record.anchor_bits = HALF_BITS
			"missing_ledger": raw.needs.erase("satisfaction_accumulators")
		var corrupt: Dictionary = document.duplicate(true)
		corrupt.state = codec.encode(raw)
		if defect == "old_header":
			corrupt.schema_version = 17
		_expect(not store.snapshot.prepare(corrupt, city), "Reject malformed accumulator before apply: " + defect)
		_expect(_satisfactions() == before and store.snapshot.capture(city) == live_before and _files() == files,
			"Malformed preparation leaves every persisted live group and original file intact: " + defect)
		var observed: Dictionary = store.disk.read_snapshot(Callable(store, "_validate"))
		_expect(not observed.is_empty() and store.disk.error.is_empty(), "Establish a valid original-slot observation before each write attempt.")
		_expect(not store.disk.write_snapshot(corrupt, Callable(store, "_validate")) and store.disk.error == "validator_rejected",
			"Each malformed replacement reaches validation and is rejected before save commit: " + defect)
		_expect(store.snapshot.capture(city) == live_before and _files() == files, "Rejected save preserves all live groups and file bytes: " + defect)
		var invalid_path: String = "user://satisfaction_boundary/invalid_" + defect + ".json"
		var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
		_expect(invalid_file != null, "Create a disposable malformed-load fixture.")
		if invalid_file != null:
			invalid_file.store_string(JSON.stringify(corrupt, "", true, true))
			invalid_file.close()
		var invalid_files: Dictionary = _files(invalid_path)
		store.disk.path = invalid_path
		_expect(not store.load_checkpoint(), "Actual checkpoint load rejects malformed provenance: " + defect)
		store.disk.path = SLOT
		_expect(store.snapshot.capture(city) == live_before and _files() == files
			and _files(invalid_path) == invalid_files,
			"Failed load leaves live groups, good checkpoint and rejected bytes unchanged: " + defect)

func _test_invalid_live_capture() -> void:
	var original: Dictionary = CitizenNeedsManager.satisfaction_accumulators.duplicate(true)
	var before: Dictionary = store.snapshot.capture(city)
	var files: Dictionary = _files()
	CitizenNeedsManager.satisfaction_accumulators[IDS[0]].anchor_bits = "000000000000f87f"
	var invalid: Dictionary = CitizenNeedsManager.satisfaction_accumulators.duplicate(true)
	_expect(store.snapshot.capture(city).is_empty(), "Malformed live provenance fails capture instead of being silently reset.")
	_expect(not store.save_checkpoint() and store.last_error == "Invalid satisfaction accumulator entry.",
		"Actual save refuses malformed live provenance before writing.")
	_expect(CitizenNeedsManager.satisfaction_accumulators == invalid and _files() == files,
		"Rejected live-state save neither repairs the invalid record nor modifies checkpoint candidates.")
	CitizenNeedsManager.satisfaction_accumulators = original
	_expect(store.snapshot.capture(city) == before, "Restoring only the injected ledger proves every other persisted live group stayed unchanged.")

func _test_integrator_subdivision() -> void:
	var id: String = "isolated_numerical_plan"
	var person := CitizenData.new()
	person.citizen_id = id
	person.satisfaction = 0.55
	var results: Array[float] = []
	for chunks: Array in [[1440], [137, 1303], [360, 360, 720], [1, 1, 1, 1437]]:
		CitizenNeedsManager.satisfaction_accumulators.erase(id)
		var cursor: int = 100000
		var current: float = person.satisfaction
		for elapsed: int in chunks:
			var plan: Dictionary = CitizenNeedsManager._plan_satisfaction(person, id, current, cursor, cursor + elapsed)
			current = plan.value
			CitizenNeedsManager.satisfaction_accumulators[id] = plan.accumulator
			cursor += elapsed
		results.append(current)
	_expect(results == [0.5, 0.5, 0.5, 0.5], "One bulk integration and uneven partitions produce identical boundary bits.")
	CitizenNeedsManager.satisfaction_accumulators.erase(id)
	# Both directions and immediate input neighbors retain their strict side.
	for initial_bits: String in ["999999999999e13f", "9a9999999999e13f", "9b9999999999e13f", "ccccccccccccdc3f", "cdccccccccccdc3f", "ceccccccccccdc3f"]:
		var initial: float = _value(initial_bits)
		person.shelter_fulfilled = initial < 0.5
		if person.shelter_fulfilled:
			CitizenNeedsManager.food_coverage_until[id] = 200000
		else:
			CitizenNeedsManager.food_coverage_until.erase(id)
		CitizenNeedsManager.satisfaction_accumulators.erase(id)
		var once: float = CitizenNeedsManager._integrate_satisfaction(person, id, initial, 100000, 101440)
		var value: float = initial
		for minute: int in range(1440):
			var plan: Dictionary = CitizenNeedsManager._plan_satisfaction(person, id, value, 100000 + minute, 100001 + minute)
			value = plan.value
			CitizenNeedsManager.satisfaction_accumulators[id] = plan.accumulator
		_expect(_bits(once) == _bits(value), "Minute and day integration match for neighboring input " + initial_bits)
		var side: int = ["999999999999e13f", "ccccccccccccdc3f"].find(initial_bits)
		if side >= 0:
			_expect(value < 0.5, "Immediately lower start remains strictly below the threshold.")
		elif initial_bits in ["9a9999999999e13f", "cdccccccccccdc3f"]:
			_expect(value == 0.5, "The specified starter/recovery boundary reaches exactly half.")
		else:
			_expect(value > 0.5, "Immediately higher start remains strictly above the threshold.")
	# Entitlement expiry reverses direction partway through one requested interval.
	person.shelter_fulfilled = true
	CitizenNeedsManager.food_coverage_until[id] = 100137
	var reversed: Array = []
	for chunks: Array in [[274], [137, 137], [1, 136, 1, 136]]:
		CitizenNeedsManager.satisfaction_accumulators.erase(id)
		var cursor: int = 100000
		var value: float = 0.55
		for elapsed: int in chunks:
			var plan: Dictionary = CitizenNeedsManager._plan_satisfaction(person, id, value, cursor, cursor + elapsed)
			value = plan.value
			CitizenNeedsManager.satisfaction_accumulators[id] = plan.accumulator
			cursor += elapsed
		reversed.append(value)
	_expect(reversed == [0.55, 0.55, 0.55], "Food expiry and direction reversal cancel integer minutes identically across partitions.")
	CitizenNeedsManager.satisfaction_accumulators.erase(id)
	CitizenNeedsManager.food_coverage_until.erase(id)
	var cap: Dictionary = CitizenNeedsManager._plan_satisfaction(person, id, 0.33001, 100000, 100001)
	_expect(cap.value == 0.33 and cap.accumulator.minutes == 0, "Reaching the unchanged target resets the numeric anchor.")
	CitizenNeedsManager.satisfaction_accumulators.erase(id)
	person.shelter_fulfilled = false
	for case: Array in [[0.70, 5760], [0.95, 12960]]:
		var initial: float = case[0]
		var elapsed: int = case[1]
		var actual: float = CitizenNeedsManager._integrate_satisfaction(person, id, initial, 100000, 100000 + elapsed)
		var native_binary: float = initial - 0.05 * float(elapsed) / 1440.0
		_expect(actual == native_binary, "Do not reinterpret arbitrary binary64 inputs as rounded decimal values.")
		print("BINARY64_CHARACTERIZATION initial=", initial, " elapsed=", elapsed, " bits=", _bits(actual), " eligible=", actual >= 0.5)

func _test_retry_purity() -> void:
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var citizen: CitizenData = CitizenManager.get_citizen(IDS[0])
	citizen.satisfaction = 0.4 + 0.05 / 2880.0
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	var worker := WorkerData.new()
	worker.worker_id = citizen.citizen_id
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	var fresh := CitizenData.new()
	fresh.citizen_id = "boundary_missing_cursor"
	fresh.population_status = CitizenData.PopulationStatus.RESIDENT
	fresh.satisfaction = 0.55
	CitizenManager.citizens_by_id[fresh.citizen_id] = fresh
	var cursors: Dictionary = CitizenNeedsManager.satisfaction_last_minute.duplicate(true)
	var accumulators: Dictionary = CitizenNeedsManager.satisfaction_accumulators.duplicate(true)
	var value: float = citizen.satisfaction
	WorkerDatabase._payroll_settling = true
	_expect(not CitizenNeedsManager._advance_satisfaction_to_minute(now + 1), "A crossing plan is withheld when work flush is busy.")
	_expect(citizen.satisfaction == value and CitizenNeedsManager.satisfaction_last_minute == cursors
		and CitizenNeedsManager.satisfaction_accumulators == accumulators,
		"Failed flush commits neither values, numeric anchors nor even new-person cursors.")
	WorkerDatabase._payroll_settling = false
	CitizenNeedsManager._satisfaction_retry_pending = false
	_expect(CitizenNeedsManager._advance_satisfaction_to_minute(now + 1), "Retry commits the single pending interval.")
	_expect(citizen.satisfaction < 0.4 and int(CitizenNeedsManager.satisfaction_last_minute[fresh.citizen_id]) == now + 1,
		"Retry crosses the unchanged worker band once and initializes the newcomer only at commit.")
	var once: Dictionary = CitizenNeedsManager.satisfaction_accumulators.duplicate(true)
	_expect(not CitizenNeedsManager._advance_satisfaction_to_minute(now + 1)
		and CitizenNeedsManager.satisfaction_accumulators == once, "Replaying the settled minute does not accumulate twice.")

func _test_legacy() -> void:
	var original: Dictionary = _files()
	var saved: Array = _satisfactions()
	_expect(CitizenNeedsManager.satisfaction_accumulators.is_empty(), "Legacy checkpoints get no invented numerical history.")
	var expected_applicants: int = 2 if _phase() == "legacy_neighbors" else 0
	_expect(CitizenManager.get_all_applicants().size() == expected_applicants, "Legacy eligibility is preserved without retroactively promoting below-threshold values.")
	if _phase() == "legacy_neighbors":
		_expect(saved == [BELOW_BITS, HALF_BITS, ABOVE_BITS], "Legacy neighboring binary64 values retain their exact threshold side.")
	for _repeat: int in range(3):
		_expect(store.load_checkpoint(), "Legacy checkpoints repeatedly migrate in memory: " + store.last_error)
		_expect(_satisfactions() == saved and _files() == original, "Legacy Continue preserves parsed float values and original files.")
	_expect(store.save_checkpoint(), "A separate explicit save writes version18: " + store.last_error)
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SLOT))
	_expect(current.schema_version == 18 and FileAccess.get_file_as_bytes(SLOT + ".bak") == original[""], "Upgrade keeps the exact old source as backup.")
	_expect(store.load_checkpoint() and _satisfactions() == saved, "The explicit upgraded save preserves all original satisfaction values.")

func _satisfactions() -> Array:
	var result: Array = []
	for id: String in IDS:
		result.append(_bits(CitizenManager.get_citizen(id).satisfaction))
	return result

func _check_starters(expected: float, eligible: int, label: String) -> void:
	for id: String in IDS:
		var person: CitizenData = CitizenManager.get_citizen(id)
		_expect(person != null and person.satisfaction == expected and person.employment_status == CitizenData.EmploymentStatus.APPLICANT
			and not WorkerDatabase.has_worker_data(id), label + " [" + id + "]")
	_expect(CitizenManager.get_all_residents().size() == 3 and CitizenManager.get_all_applicants().size() == eligible, label + " [roster]")

func _files(path: String = SLOT) -> Dictionary:
	var files: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		files[suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	return files

func _safe_profile() -> bool:
	var qa_root: String = ProjectSettings.globalize_path("res://../citysave_suite_qa").simplify_path()
	var homes: Array[String] = []
	for variable: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var home: String = OS.get_environment(variable).simplify_path()
		if home.is_empty() or not home.is_absolute_path() or not DirAccess.dir_exists_absolute(home) or not home.begins_with(qa_root + "/") or homes.has(home):
			return false
		homes.append(home)
	return ProjectSettings.globalize_path("user://").simplify_path().begins_with(homes[0] + "/")

func _finish() -> void:
	print("SatisfactionBoundaryTest: ", "PASS" if failures == 0 else "FAIL", " phase=", _phase(), " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
