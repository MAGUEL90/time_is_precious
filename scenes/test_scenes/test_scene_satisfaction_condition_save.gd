extends Node

## Cross-revision checkpoint test. The writer is deliberately compatible with
## baseline 25f587c3e65eb9aab1d295d015703863b9cd16e5 and never calls the new
## summary API. Run that checkout with --satisfaction-save-phase=write, then
## this checkout with phase=read, reusing one isolated XDG_DATA_HOME. The read
## phase reads before midnight and saves after it, post-read Continues that
## midnight checkpoint and saves after an offscreen home day, and home-read
## Continues the final home checkpoint in a fourth process.
## Example: XDG_DATA_HOME=/tmp/satisfaction-condition-save godot --path .
##   res://scenes/test_scenes/test_scene_satisfaction_condition_save.tscn --
##   --satisfaction-save-phase=write
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const SAVE_VALUES: Script = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const RAID_STATE: Script = preload("res://scenes/raid/raid_state.gd")
const RAID_CONFIG: Script = preload("res://scenes/raid/raid_config.gd")
const SAVE_PATH: String = "user://satisfaction_condition_save/checkpoint.json"
const HOME_PATH: String = "res://scenes/player_home_interior/player_home_interior.tscn"
const LINKED_ID: String = "condition_save_linked"
const RESIDENT_ID: String = "condition_save_resident"
const LEGACY_WORKER_ID: String = "condition_save_legacy_worker"
const FOOD_ID: String = "barley_bread"
const CLOTHING_ID: String = "simple_clothes"
const TARGET_PER_NEED: float = 0.33
const DAILY_STEP: float = 0.05

var phase: String = "write"
var failures: int = 0
var launched: bool = false
var loaded_from_checkpoint: bool = false
var city: Node
var player: Player
var store: Node
var initial_bytes: PackedByteArray
var initial_document: Dictionary = {}
var initial_state: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--satisfaction-save-phase="):
			phase = argument.trim_prefix("--satisfaction-save-phase=")
	_expect(phase in ["write", "read", "post-read", "home-read"], "Choose write, read, post-read, or home-read.")
	_check_isolated_xdg()
	if phase == "write":
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			_expect(not FileAccess.file_exists(SAVE_PATH + suffix), "Writer requires an empty isolated checkpoint slot.")
	else:
		_expect(FileAccess.file_exists(SAVE_PATH), "Reader requires the checkpoint from the preceding phase.")
	if failures > 0:
		_finish()
		return

	if phase != "write":
		initial_bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
		initial_document = _parse_document(initial_bytes)
		_expect(not initial_bytes.is_empty() and not initial_document.is_empty(), "The source checkpoint is valid JSON.")
		if initial_document.is_empty():
			_finish()
			return
		var expected_location: String = "home" if phase == "home-read" else "city"
		_expect(initial_document.get("scenario") == "city_mvp"
			and initial_document.get("location") == expected_location,
			"The source checkpoint has the expected city/home location.")
		var codec = SAVE_VALUES.new()
		var decoded: Variant = codec.decode(initial_document.get("state"))
		_expect(codec.error.is_empty() and decoded is Dictionary, "The source value schema decodes exactly.")
		if decoded is Dictionary:
			initial_state = decoded

	await _open_session(phase != "write")
	if not launched:
		_finish()
		return
	if phase == "write":
		await _write_baseline_checkpoint()
	elif phase == "read":
		await _read_before_midnight_and_save_city()
	elif phase == "post-read":
		await _read_after_midnight_and_save_home()
	else:
		_verify_home_checkpoint()
	_finish()


func _check_isolated_xdg() -> void:
	if OS.get_name() != "Linux":
		return
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	_expect(data_root.is_absolute_path() and not data_root.is_empty()
		and user_root.begins_with(data_root.simplify_path().trim_suffix("/") + "/"),
		"Set an isolated absolute XDG_DATA_HOME and reuse it across the baseline writer and both readers.")


func _open_session(continued: bool) -> void:
	get_tree().current_scene = null
	get_tree().paused = false
	TimeComponentManager.is_paused = false
	# Freeze the newly opened city as soon as the scene-change signal fires,
	# before Continue can validate or hand off a saved home location.
	get_tree().scene_changed.connect(_freeze_clock_after_scene, CONNECT_ONE_SHOT)
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	if continued:
		menu.continue_button.pressed.emit()
	else:
		menu.new_game_button.pressed.emit()
	var deadline: int = Time.get_ticks_msec() + 20000
	while not launched and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(launched and loaded_from_checkpoint == continued,
		"Start Menu opens New Game or Continues the checkpoint before timeout.")
	if not launched:
		return
	city = get_tree().current_scene
	store = WorkStateRuntime.get_node("CitySave")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	if phase == "home-read":
		_expect(city.scene_file_path == HOME_PATH and store.map == city,
			"Continue restores the saved home as the active location.")
	else:
		_expect(city.scene_file_path == "res://scenes/content_scene/content_scene.tscn",
			"The checkpoint opens in the authored city scene.")
	player = city.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true


func _freeze_clock_after_scene() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false


func _on_session_started(continued: bool) -> void:
	loaded_from_checkpoint = continued
	launched = true


func _write_baseline_checkpoint() -> void:
	_expect(TimeComponentManager.current_hour >= 8 and TimeComponentManager.current_hour < 17,
		"The baseline New Game starts while the Job Board is open.")
	if failures > 0:
		return
	var starter_ids: Array[String] = ["initial_workshop_laborer", "initial_worksite_hauler", "initial_city_storage_hauler"]
	var has_all_starters: bool = true
	for starter_id: String in starter_ids:
		has_all_starters = has_all_starters and CitizenManager.get_citizen(starter_id) != null
	_expect(CitizenManager.citizens_by_id.size() == starter_ids.size() and has_all_starters
		and WorkerDatabase.workers_by_id.is_empty(),
		"The fresh city has its three authored starter residents and no hired workers before the isolated fixture replaces them.")
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	var linked: CitizenData = _new_resident(LINKED_ID, 0.94)
	var resident: CitizenData = _new_resident(RESIDENT_ID, 0.71)
	# The existing legacy migration seeds a starter Hauler only when no
	# resident Hauler exists. Keep this fixture semantically complete so an
	# unrelated migration does not add a fourth consumer on Continue.
	resident.profession = WorkerData.Profession.HAULER
	CitizenManager.add_citizen(linked)
	CitizenManager.add_citizen(resident)
	_expect(CitizenManager.register_applicant(LINKED_ID, WorkerData.Profession.LABORER),
		"The linked resident registers through the real applicant lifecycle.")
	Inventory.add_item("shekel", 100)
	var linked_worker: WorkerData = WorkerDatabase.hire_applicant(LINKED_ID, 1, 3)
	_expect(linked_worker != null and linked_worker.has_linked_citizen()
		and linked_worker.payroll_contract_days == 3 and linked_worker.payroll_paid_until_day >= TimeComponentManager.current_day,
		"The linked worker has a real paid contract before the checkpoint.")
	if linked_worker == null:
		return
	var legacy_worker: WorkerData = WorkerData.new()
	legacy_worker.worker_id = LEGACY_WORKER_ID
	legacy_worker.display_name = "Unlinked legacy worker"
	legacy_worker.profession = WorkerData.Profession.LABORER
	legacy_worker.satisfaction = 0.38
	WorkerDatabase.workers_by_id[LEGACY_WORKER_ID] = legacy_worker
	CityStockManager.shelter_capacity = 1
	var city_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	city_storage.items.clear()
	city_storage.food_portions.clear()
	Inventory.add_item(FOOD_ID, 2)
	Inventory.add_item(CLOTHING_ID, 1)
	var selected_items: Dictionary = {}
	selected_items[FOOD_ID] = 2
	selected_items[CLOTHING_ID] = 1
	var deposited: Dictionary = city_storage.deposit_items_from_inventory(selected_items)
	_expect(bool(deposited.get("ok", false)), "The fixture supplies enter real City Storage through the inventory transfer.")
	# These baseline fields are all present at 25f587c. Keep the fixture's current
	# day unprocessed so the next midnight is the only daily settlement.
	CitizenNeedsManager.last_processed_day = TimeComponentManager.current_day
	CitizenNeedsManager.last_food_processed_day = TimeComponentManager.current_day
	CitizenNeedsManager.last_clothing_processed_day = TimeComponentManager.current_day
	CitizenNeedsManager.last_food_fulfilled_count = 0
	CitizenNeedsManager.last_food_unfulfilled_count = 0
	CitizenNeedsManager.last_clothing_fulfilled_count = 0
	CitizenNeedsManager.last_clothing_unfulfilled_count = 0
	CitizenNeedsManager.last_shelter_capacity_fulfilled_count = 0
	CitizenNeedsManager.last_shelter_capacity_unfulfilled_count = 0
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()
	_expect(CitizenNeedsManager.get_food_consumer_count() == 3
		and city_storage.get_food_supply_points() == 2
		and city_storage.get_clothing_item_count() == 1,
		"Two residents, one linked worker and one unlinked worker form three unique consumers with known stock.")
	if failures > 0:
		return
	var day_before: int = TimeComponentManager.current_day
	var minute_of_day: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var until_midnight: int = 1440 - minute_of_day
	_expect(TimeComponentManager.advance_minutes(until_midnight), "The real city clock advances to midnight.")
	_expect(TimeComponentManager.current_day == day_before + 1
		and CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day,
		"Midnight runs exactly one actual daily-needs settlement.")
	_expect(CitizenNeedsManager.last_needs_results.size() == 3
		and CitizenNeedsManager.last_food_fulfilled_count == 2
		and CitizenNeedsManager.last_food_unfulfilled_count == 1
		and CitizenNeedsManager.last_clothing_fulfilled_count == 1
		and CitizenNeedsManager.last_clothing_unfulfilled_count == 2
		and CitizenNeedsManager.last_shelter_capacity_fulfilled_count == 1
		and CitizenNeedsManager.last_shelter_capacity_unfulfilled_count == 1,
		"The day's ledger records three unique people and the exact physical supply limits.")
	_expect(city_storage.get_food_supply_points() == 0 and city_storage.get_clothing_item_count() == 0,
		"The real settlement consumes exactly two food points and one garment.")
	_expect(WorkerDatabase.get_worker_data(LINKED_ID) == linked_worker
		and linked_worker.get_linked_citizen() == CitizenManager.get_citizen(LINKED_ID)
		and WorkerDatabase.get_worker_data(LEGACY_WORKER_ID).get_linked_citizen() == null,
		"The saved worker set contains a linked contract and a separate unlinked legacy record.")
	if failures > 0:
		return
	if not await _advance_bounded(1439, 120000):
		return
	_expect(TimeComponentManager.current_hour == 23 and TimeComponentManager.current_minute == 59
		and CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day,
		"The baseline checkpoint is captured at 23:59 after that day's real ledger is complete.")
	if failures > 0:
		return
	_expect(store.save_checkpoint(), "Baseline-compatible writer saves the real settlement: " + store.last_error)
	_expect(FileAccess.file_exists(SAVE_PATH), "The baseline checkpoint file exists after Save.")
	if FileAccess.file_exists(SAVE_PATH):
		var written: Dictionary = _parse_document(FileAccess.get_file_as_bytes(SAVE_PATH))
		_expect(written.get("schema_version") == store.snapshot.VERSION
			and written.get("location") == "city", "The baseline writer records the unchanged current schema and city location.")


func _read_before_midnight_and_save_city() -> void:
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes,
		"Start Menu Continue leaves the baseline checkpoint bytes unchanged.")
	_expect(TimeComponentManager.current_hour == 23 and TimeComponentManager.current_minute == 59,
		"The baseline checkpoint Continues before midnight.")
	_assert_full_snapshot_unchanged("first Continue")
	_assert_saved_roster_and_summaries("first Continue")
	var city_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var stock_before: Dictionary = city_storage.items.duplicate(true)
	var portions_before: Dictionary = city_storage.food_portions.duplicate(true)
	var satisfaction_before: Dictionary = _all_satisfactions()
	var ledger_before: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	_expect(store.load_checkpoint(), "A repeated load accepts the unchanged original checkpoint: " + store.last_error)
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes
		and city_storage.items == stock_before and city_storage.food_portions == portions_before
		and _all_satisfactions() == satisfaction_before
		and CitizenNeedsManager.last_needs_results == ledger_before,
		"Repeated Load neither rewrites the file nor consumes the saved supplies or repeats Satisfaction.")
	_assert_full_snapshot_unchanged("repeated Load")
	_assert_saved_roster_and_summaries("repeated Load")
	if failures > 0:
		return
	var day_before: int = TimeComponentManager.current_day
	var satisfaction_before_midnight: Dictionary = _all_satisfactions()
	_expect(TimeComponentManager.advance_minutes(1), "The real city clock crosses 23:59 to midnight exactly once.")
	_expect(TimeComponentManager.current_day == day_before + 1
		and CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day,
		"Crossing midnight runs exactly one new daily settlement.")
	_assert_daily_step_and_no_overshoot(satisfaction_before_midnight)
	_assert_saved_roster_and_summaries("first post-midnight settlement", false)
	var stock_after_midnight: Dictionary = city_storage.items.duplicate(true)
	var ledger_after_midnight: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	var satisfaction_after_midnight: Dictionary = _all_satisfactions()
	CitizenNeedsManager.process_daily_needs()
	_expect(city_storage.items == stock_after_midnight
		and CitizenNeedsManager.last_needs_results == ledger_after_midnight
		and _all_satisfactions() == satisfaction_after_midnight,
		"A duplicate same-day settlement after midnight consumes nothing and changes no Satisfaction.")
	_expect(store.save_checkpoint(), "The post-midnight city checkpoint saves: " + store.last_error)
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH + ".bak") == initial_bytes,
		"The post-midnight save retains the exact baseline 23:59 bytes in its backup.")
	var city_document: Dictionary = _parse_document(FileAccess.get_file_as_bytes(SAVE_PATH))
	_expect(city_document.get("location") == "city"
		and city_document.get("schema_version") == initial_document.get("schema_version"),
		"The post-midnight checkpoint keeps the same schema and city location.")


func _read_after_midnight_and_save_home() -> void:
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes,
		"Start Menu Continue leaves the post-midnight checkpoint bytes unchanged.")
	_expect(TimeComponentManager.current_hour == 0 and TimeComponentManager.current_minute == 0,
		"The second reader Continues after midnight.")
	_assert_full_snapshot_unchanged("post-midnight Continue")
	_assert_saved_roster_and_summaries("post-midnight Continue")
	var city_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var stock_before: Dictionary = city_storage.items.duplicate(true)
	var portions_before: Dictionary = city_storage.food_portions.duplicate(true)
	var satisfaction_before: Dictionary = _all_satisfactions()
	var ledger_before: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	_expect(store.load_checkpoint(), "A repeated post-midnight Load succeeds: " + store.last_error)
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes
		and city_storage.items == stock_before and city_storage.food_portions == portions_before
		and _all_satisfactions() == satisfaction_before
		and CitizenNeedsManager.last_needs_results == ledger_before,
		"Reloading after midnight does not consume needs or apply the same-day satisfaction step again.")
	_assert_full_snapshot_unchanged("repeated post-midnight Load")
	_assert_saved_roster_and_summaries("repeated post-midnight Load")
	if failures > 0:
		return
	_test_raid_changes_live_satisfaction_only()
	if failures > 0:
		return
	var satisfaction_at_day_start: Dictionary = _all_satisfactions()
	var day_before: int = TimeComponentManager.current_day
	var home_door: Node = city.get_node("YSortWorld/HomeDoor")
	home_door._on_body_entered(player)
	if not await _wait_for_scene(HOME_PATH):
		return
	city = get_tree().current_scene
	player = city.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_expect(store.map == city and store.snapshot.is_home(city), "The active home scene owns the same city checkpoint store.")
	# Wait for the real transition to release its movement/save lock; jumping
	# simulated minutes must not bypass the game's interaction guard.
	var transition_deadline: int = Time.get_ticks_msec() + 15000
	while not store.snapshot.busy_reason(city).is_empty() and Time.get_ticks_msec() < transition_deadline:
		await get_tree().process_frame
	_expect(store.snapshot.busy_reason(city).is_empty(), "The home transition finishes and naturally releases the save guard.")
	if failures > 0:
		return
	if not await _advance_bounded(1440, 120000):
		return
	_expect(TimeComponentManager.current_day == day_before + 1
		and CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day,
		"One offscreen home day triggers exactly one midnight needs settlement.")
	_assert_daily_step_and_no_overshoot(satisfaction_at_day_start)
	_assert_saved_roster_and_summaries("offscreen day settlement", false)
	var stock_after_day: Dictionary = city_storage.items.duplicate(true)
	var ledger_after_day: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	var satisfactions_after_day: Dictionary = _all_satisfactions()
	CitizenNeedsManager.process_daily_needs()
	_expect(city_storage.items == stock_after_day
		and CitizenNeedsManager.last_needs_results == ledger_after_day
		and _all_satisfactions() == satisfactions_after_day,
		"A second same-day daily-needs call while home is idle is idempotent.")
	_expect(store.save_checkpoint(), "The offscreen home settlement saves through the same checkpoint path: " + store.last_error)
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH + ".bak") == initial_bytes,
		"Saving the home checkpoint keeps the exact post-midnight city source bytes in the backup.")
	var home_document: Dictionary = _parse_document(FileAccess.get_file_as_bytes(SAVE_PATH))
	_expect(home_document.get("schema_version") == initial_document.get("schema_version")
		and home_document.get("location") == "home", "The new checkpoint stores home location without changing schema version.")


func _verify_home_checkpoint() -> void:
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes,
		"Start Menu Continue leaves the saved home checkpoint bytes unchanged.")
	_assert_full_snapshot_unchanged("home Continue")
	_assert_saved_roster_and_summaries("home Continue")
	var city_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var stock_before: Dictionary = city_storage.items.duplicate(true)
	var satisfaction_before: Dictionary = _all_satisfactions()
	var ledger_before: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	CitizenNeedsManager.process_daily_needs()
	_expect(city_storage.items == stock_before
		and _all_satisfactions() == satisfaction_before
		and CitizenNeedsManager.last_needs_results == ledger_before
		and FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes,
		"Loading the home checkpoint on its already-settled day neither consumes needs again nor rewrites bytes.")
	_assert_full_snapshot_unchanged("same-day home replay")


func _test_raid_changes_live_satisfaction_only() -> void:
	var before_ledger: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	var before_summaries: Dictionary = {}
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		before_summaries[id] = _person_summary(id)
	var config: Resource = RAID_CONFIG.new()
	config.set("wall_max_hp", 1)
	config.set("wall_defend", 0)
	config.set("instant_build_enabled", true)
	config.set("satisfaction_penalty", 0.05)
	config.set("max_fleeing_residents", 0)
	var raid: Node = RAID_STATE.new()
	raid.set("config", config)
	add_child(raid)
	var built: bool = bool(raid.call("build_wall"))
	var started: bool = bool(raid.call("start_debug_raid", true))
	raid.set_process(false)
	raid.call("advance_attack", 5.0)
	var report: Dictionary = raid.call("get_last_report")
	raid.free()
	_expect(built and started and report.get("outcome") == "breached"
		and report.get("citizens_fled", []).is_empty(),
		"A deterministic breached raid applies its satisfaction penalty without removing residents.")
	_expect(CitizenNeedsManager.last_needs_results == before_ledger,
		"The raid does not rewrite today's saved physical-needs ledger.")
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		var before: Dictionary = before_summaries[id]
		var after: Dictionary = _person_summary(id)
		_expect(is_equal_approx(float(after.condition_target), float(before.condition_target))
			and is_equal_approx(float(after.food), float(before.food))
			and is_equal_approx(float(after.clothing), float(before.clothing))
			and is_equal_approx(float(after.shelter), float(before.shelter)),
			"Raid changes live Satisfaction but retains actual needs and derived target for " + id + ".")
		if id != LEGACY_WORKER_ID:
			_expect(not is_equal_approx(float(after.satisfaction), float(before.satisfaction)),
				"The raid refreshes live resident Satisfaction for " + id + ".")
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes,
		"The raid probe does not write or migrate the source checkpoint.")


func _assert_saved_roster_and_summaries(label: String, compare_source_checkpoint: bool = true) -> void:
	var source_citizens: Dictionary = initial_state.get("citizens", {}).get("citizens_by_id", {})
	var source_workers: Dictionary = initial_state.get("workers", {}).get("workers_by_id", {})
	var source_needs: Dictionary = initial_state.get("needs", {})
	var expected_results: Dictionary = {}
	if compare_source_checkpoint:
		expected_results = source_needs.get("last_needs_results", {})
	else:
		expected_results = CitizenNeedsManager.last_needs_results
	_expect(CitizenManager.get_citizen(LINKED_ID) != null
		and CitizenManager.get_citizen(RESIDENT_ID) != null
		and WorkerDatabase.get_worker_data(LINKED_ID) != null
		and WorkerDatabase.get_worker_data(LEGACY_WORKER_ID) != null,
		label + ": all citizen and worker IDs survive Continue.")
	if (not source_citizens.has(LINKED_ID) or not source_citizens.has(RESIDENT_ID)
		or not source_workers.has(LINKED_ID) or not source_workers.has(LEGACY_WORKER_ID)):
		_expect(false, label + ": source contains both residents, linked contract, and legacy worker.")
		return
	var live_linked: WorkerData = WorkerDatabase.get_worker_data(LINKED_ID)
	var live_legacy: WorkerData = WorkerDatabase.get_worker_data(LEGACY_WORKER_ID)
	var contract_state_valid: bool = live_linked.get_linked_citizen() == CitizenManager.get_citizen(LINKED_ID) \
		and live_legacy.get_linked_citizen() == null
	if compare_source_checkpoint:
		var source_linked: WorkerData = source_workers[LINKED_ID]
		var source_legacy: WorkerData = source_workers[LEGACY_WORKER_ID]
		contract_state_valid = contract_state_valid and source_linked.payroll_contract_days == 3 \
			and live_linked.payroll_contract_days == source_linked.payroll_contract_days \
			and live_linked.payroll_paid_until_day == source_linked.payroll_paid_until_day \
			and source_legacy.payroll_contract_days == live_legacy.payroll_contract_days
	_expect(contract_state_valid,
		label + ": the linked worker's paid contract and the unlinked legacy contract state are preserved.")
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	if compare_source_checkpoint:
		var source_storage: Dictionary = initial_state.get("city_storage", {})
		_expect(storage.items == source_storage.get("items", {})
			and storage.food_portions == source_storage.get("food_portions", {})
			and CitizenNeedsManager.last_needs_results == expected_results
			and CitizenNeedsManager.last_processed_day == int(source_needs.get("last_processed_day", -1)),
			label + ": city stock, daily ledger, and processed-day latch survive exactly.")
	else:
		_expect(storage.get_food_supply_points() == 0 and storage.get_clothing_item_count() == 0
			and CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day
			and expected_results.size() == 3,
			label + ": the new day's ledger reflects the exhausted food and clothing supplies.")
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		var result: Variant = expected_results.get(id)
		var summary: Dictionary = _person_summary(id)
		if not result is Dictionary:
			_expect(false, label + ": source ledger contains actual needs for " + id + ".")
			continue
		var expected_target: float = _condition_target(bool(result.food), bool(result.clothing), bool(result.shelter))
		var live_person: Variant = CitizenManager.get_citizen(id)
		if live_person == null:
			live_person = WorkerDatabase.get_worker_data(id)
		_expect(bool(summary.get("evaluated", false))
			and int(summary.get("day", -1)) == TimeComponentManager.current_day
			and bool(summary.get("food", false)) == bool(result.food)
			and bool(summary.get("clothing", false)) == bool(result.clothing)
			and bool(summary.get("shelter", false)) == bool(result.shelter)
			and is_equal_approx(float(summary.get("condition_target", -1.0)), expected_target)
			and is_equal_approx(float(summary.get("satisfaction", -1.0)), float(live_person.satisfaction)),
			label + ": live Satisfaction and target derived from today's actual ledger are correct for " + id + ".")


func _assert_daily_step_and_no_overshoot(before_by_id: Dictionary) -> void:
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		var summary: Dictionary = _person_summary(id)
		var target: float = float(summary.get("condition_target", -1.0))
		var before: float = float(before_by_id.get(id, -1.0))
		var after: float = float(summary.get("satisfaction", -1.0))
		var expected: float = move_toward(before, target, DAILY_STEP)
		var step: float = absf(after - before)
		var no_overshoot: bool = (before <= target and after <= target + 0.000001) \
			or (before >= target and after >= target - 0.000001)
		_expect(before >= 0.0 and target >= 0.0 and is_equal_approx(after, expected)
			and step <= DAILY_STEP + 0.000001 and no_overshoot,
			"The offscreen settlement moves " + id + " at most 0.05 toward today's actual condition without overshoot.")


func _new_resident(id: String, satisfaction: float) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = id
	citizen.satisfaction = satisfaction
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	var profile: VisualProfile = VisualProfile.new()
	profile.hair_style = "brown_male_02"
	profile.skin_tone = "tan"
	profile.accessory = "default"
	citizen.visual_profile = profile
	return citizen


func _person_summary(id: String) -> Dictionary:
	# Dynamic call keeps the baseline writer loadable; only read phases invoke it.
	var value: Variant = CitizenNeedsManager.call("get_person_needs_summary", id)
	return value if value is Dictionary else {}


func _condition_target(food: bool, clothing: bool, shelter: bool) -> float:
	var fulfilled: int = int(food) + int(clothing) + int(shelter)
	return float(fulfilled) * TARGET_PER_NEED


func _all_satisfactions() -> Dictionary:
	var result: Dictionary = {}
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		var summary: Dictionary = _person_summary(id)
		result[id] = float(summary.get("satisfaction", -1.0))
	return result


func _assert_full_snapshot_unchanged(label: String) -> void:
	var live_document: Dictionary = store.snapshot.capture(store.map)
	_expect(not live_document.is_empty()
		and live_document.get("schema_version") == initial_document.get("schema_version")
		and live_document.get("location") == initial_document.get("location")
		and live_document.get("state") == initial_document.get("state"),
		label + ": every serialized owner, ID, contract, stock, RNG and needs field matches the source snapshot exactly.")
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes,
		label + ": the checkpoint's bytes are unchanged.")
	var progression: Node = WorkStateRuntime.get_node("CityProgression")
	var progress_before: int = progression.progress
	var day_before: int = progression.last_awarded_day
	var daily_before: Dictionary = progression.last_daily.duplicate(true)
	CitizenNeedsManager.needs_changed.emit()
	_expect(progression.progress == progress_before and progression.last_awarded_day == day_before
		and progression.last_daily == daily_before,
		label + ": a same-day needs refresh cannot award city progress again after Continue.")


func _parse_document(bytes: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _wait_for_scene(path: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != path:
		if Time.get_ticks_msec() >= deadline:
			_expect(false, "The expected scene transition completes before timeout: " + path)
			return false
		await get_tree().process_frame
	return true


func _advance_bounded(total_minutes: int, timeout_ms: int) -> bool:
	var remaining: int = total_minutes
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while remaining > 0:
		if Time.get_ticks_msec() >= deadline:
			_expect(false, "Offscreen clock advancement completes before timeout.")
			return false
		var chunk: int = mini(60, remaining)
		if not TimeComponentManager.advance_minutes(chunk):
			_expect(false, "The offscreen city clock accepts each bounded minute chunk.")
			return false
		remaining -= chunk
		await get_tree().process_frame
	return true


func _finish() -> void:
	print("SatisfactionConditionSaveTest ", phase, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
