extends Node

## An older checkpoint already employed Lugal as a Laborer. Migration must add
## the requested Hauler without converting him or changing the source file.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const STARTERS = preload("res://scenes/content_scene/startup/initial_worksites.gd")
const SAVE_FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var root_path: String = OS.get_environment("XDG_DATA_HOME")
	_check(root_path.is_absolute_path() and ProjectSettings.globalize_path("user://").begins_with(root_path.trim_suffix("/") + "/"), "Use a disposable XDG_DATA_HOME.")
	if failures:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	var city: Node2D = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	for _frame: int in range(3):
		await get_tree().process_frame
	Inventory.add_item("shekel", 6) # Test-only funding for two normal contracts.
	var old_worker: WorkerData = WorkerDatabase.hire_applicant(STARTERS.HAULER_APPLICANT_ID)
	_check(old_worker != null and old_worker.profession == WorkerData.Profession.LABORER, "The existing Lugal is hired as a Laborer.")
	if old_worker == null:
		get_tree().quit(1)
		return
	old_worker.profession_xp = 17
	var old_until: int = old_worker.payroll_paid_until_day
	var old_wallet: int = int(Inventory.items.get("shekel", 0))
	# Fixture-only reconstruction of the previous version, before Belum existed.
	CitizenManager.citizens_by_id.erase(STARTERS.CITY_HAULER_APPLICANT_ID)
	# Keep the synthetic roster and all per-person ledgers consistent.
	CitizenNeedsManager.food_coverage_until.erase(STARTERS.CITY_HAULER_APPLICANT_ID)
	CitizenNeedsManager.satisfaction_last_minute.erase(STARTERS.CITY_HAULER_APPLICANT_ID)
	CitizenNeedsManager.satisfaction_accumulators.erase(STARTERS.CITY_HAULER_APPLICANT_ID)
	var store: Node = WorkStateRuntime.get_node("CitySave")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://hauler_migration"))
	store.disk.path = "user://hauler_migration/checkpoint.json"
	var saved: bool = store.save_checkpoint()
	_check(saved, "The prior hired-Laborer state saves: " + store.last_error)
	if not saved:
		get_tree().quit(1)
		return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(store.disk.path)
	# An otherwise valid old document can be just below the existing 8 MiB
	# limit. Adding Belum must not make that checkpoint unloadable.
	var almost_full: Dictionary = store.snapshot.capture(city)
	var codec := CitySaveValues.new()
	var raw: Dictionary = codec.decode(almost_full.state)
	# Roster migration is independent of Worksite schema history. Keep this
	# fixture on the complete current registry instead of deleting arbitrary IDs.
	var old_person: CitizenData = raw.citizens.citizens_by_id[STARTERS.HAULER_APPLICANT_ID]
	old_person.display_name = ""
	almost_full.state = codec.encode(raw)
	var base_size: int = JSON.stringify(almost_full, "\t", true, true).to_utf8_buffer().size()
	old_person.display_name = "x".repeat(SAVE_FILE.MAX_FILE_BYTES - base_size - 64)
	almost_full.state = codec.encode(raw)
	var full_size: int = JSON.stringify(almost_full, "\t", true, true).to_utf8_buffer().size()
	_check(codec.error.is_empty() and full_size <= SAVE_FILE.MAX_FILE_BYTES and full_size > SAVE_FILE.MAX_FILE_BYTES - 100, "The old document is valid and almost at the file-size limit.")
	var near_limit_prepared: bool = store.snapshot.prepare(almost_full, city)
	_check(near_limit_prepared, "A near-limit old checkpoint can still be prepared: " + store.snapshot.error)
	if near_limit_prepared:
		# Compact JSON can fit the added fields even when indented JSON cannot.
		# If the applicant still cannot fit, migration must remain valid without it.
		var prepared_raw: Dictionary = store.snapshot.prepared
		var added_applicant: CitizenData = prepared_raw.citizens.citizens_by_id.get(STARTERS.CITY_HAULER_APPLICANT_ID)
		_check(added_applicant == null or added_applicant.profession == WorkerData.Profession.HAULER, "Any migrated applicant keeps the intended Hauler identity.")
		var migrated: Dictionary = almost_full.duplicate(true)
		migrated.state = codec.encode(prepared_raw)
		var compact_disk = SAVE_FILE.new()
		compact_disk.path = "user://hauler_migration/near_limit.json"
		compact_disk.read_snapshot(func(_document: Dictionary) -> bool: return true)
		_check(compact_disk.write_snapshot(migrated, func(document: Dictionary) -> bool: return store.snapshot.prepare(document, city)), "The migrated near-limit checkpoint can be safely written: " + compact_disk.error)
	_check(FileAccess.get_file_as_bytes(store.disk.path) == original, "Near-limit validation does not rewrite the existing save.")
	old_worker.profession_xp = 99
	_check(store.load_checkpoint() and FileAccess.get_file_as_bytes(store.disk.path) == original, "Continue preserves the original checkpoint bytes.")
	old_worker = WorkerDatabase.get_worker_data(STARTERS.HAULER_APPLICANT_ID)
	var hauler: CitizenData = CitizenManager.get_citizen(STARTERS.CITY_HAULER_APPLICANT_ID)
	_check(old_worker != null and old_worker.profession == WorkerData.Profession.LABORER and old_worker.profession_xp == 17 and old_worker.payroll_paid_until_day == old_until, "Existing Laborer identity, XP and paid contract survive.")
	_check(hauler != null and hauler.profession == WorkerData.Profession.HAULER and CitizenManager.get_all_applicants().has(hauler), "The old roster receives a distinct Hauler applicant.")
	_check(int(Inventory.items.get("shekel", 0)) == old_wallet, "Migration itself makes no wallet debit or grant.")
	var board: JobBoard = city.get_node("YSortWorld/InitialWorksites/JobBoard")
	_check(not board.world_access_enabled, "The initial scene keeps its legacy board disabled.")
	var hired: WorkerData = WorkerDatabase.hire_applicant(STARTERS.CITY_HAULER_APPLICANT_ID)
	_check(hired != null and hired.profession == WorkerData.Profession.HAULER, "The migrated applicant can take a normal paid Hauler contract.")
	if hired == null:
		get_tree().quit(1)
		return
	_check(store.save_checkpoint() and store.load_checkpoint() and store.load_checkpoint(), "The two roles survive repeated save and Continue: " + store.last_error)
	_check(WorkerDatabase.get_worker_data(STARTERS.HAULER_APPLICANT_ID).profession == WorkerData.Profession.LABORER
		and WorkerDatabase.get_worker_data(STARTERS.CITY_HAULER_APPLICANT_ID).profession == WorkerData.Profession.HAULER
		and CitizenManager.get_all_residents().size() == 3, "Repeated Continue preserves both workers and never duplicates the added resident.")
	print("HaulerSaveMigrationTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
