extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Real New Game/Continue and Job Board paths in an isolated profile.
## The legacy checkpoints are synthetic v12 files. The legacy-worker case
## clears an unrelated old-map laborer approach in a test-only copy so it can
## exercise retained Hauler behavior on the new map. Unmodified old positions
## are checked separately for safe rejection by the house migration fixture.
const TEST_DIR: String = "user://no_hauler_job_board_test"
const LABORER_ID: String = "initial_workshop_laborer"
const SECOND_ID: String = "initial_city_storage_hauler"
const LEGACY_HAULER_ID: String = "initial_worksite_hauler"
const LEGACY_FIXTURES: String = "res://scenes/test_scenes/fixtures/legacy_stockpile_v12/"
var store: Node
var board: JobBoard
var loaded_from_save: bool = false

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--job-board-case="):
			phase = argument.trim_prefix("--job-board-case=")
	_expect(phase in ["new_write", "new_read", "legacy_applicant", "legacy_worker"], "Choose a supported Job Board test case.")
	if OS.get_name() == "Linux":
		var data_root: String = OS.get_environment("XDG_DATA_HOME")
		var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
		_expect(not data_root.is_empty() and data_root.is_absolute_path() and user_root.begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use an isolated absolute XDG_DATA_HOME.")
	if stopped:
		return
	var is_legacy: bool = phase.begins_with("legacy_")
	var save_path: String = TEST_DIR + ("/new.json" if not is_legacy else "/" + phase + ".json")
	var source_bytes := PackedByteArray()
	if phase != "new_read":
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			_expect(not FileAccess.file_exists(save_path + suffix), "Refusing to overwrite a test checkpoint.")
	if is_legacy and not stopped:
		var source_name: String = "stocked" if phase == "legacy_applicant" else "idle"
		source_bytes = FileAccess.get_file_as_bytes(LEGACY_FIXTURES + source_name + ".json.gz").decompress_dynamic(1000000, FileAccess.COMPRESSION_GZIP)
		_expect(not source_bytes.is_empty(), "The synthetic v12 save is readable.")
		if phase == "legacy_worker" and not stopped:
			var document: Variant = JSON.parse_string(source_bytes.get_string_from_utf8())
			var codec = preload("res://scenes/new_scenes/save_game/city_save_values.gd").new()
			var raw: Variant = codec.decode(document.state) if document is Dictionary else null
			var laborer: WorkerData = raw.workers.workers_by_id.get(LABORER_ID) if raw is Dictionary else null
			_expect(laborer != null and laborer.physical_approach.get("owner") == "WoodSite",
				"The synthetic legacy-worker fixture has the expected unrelated old-map laborer route.")
			if not stopped:
				laborer.physical_approach = {}
				document.state = codec.encode(raw)
				_expect(codec.error.is_empty(), "The isolated legacy-worker test copy encodes.")
				source_bytes = (JSON.stringify(document, "\t", true, true) + "\n").to_utf8_buffer()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		_expect(file != null, "A separate legacy checkpoint copy can be created.")
		if not stopped:
			file.store_buffer(source_bytes)
			file.close()
	if phase == "new_read":
		_expect(FileAccess.file_exists(save_path), "The new-game Continue needs the written checkpoint.")
	if stopped:
		return
	var before: PackedByteArray = FileAccess.get_file_as_bytes(save_path) if phase != "new_write" else PackedByteArray()
	get_tree().current_scene = null
	get_tree().paused = false
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = save_path
	menu.session_started.connect(func(from_save: bool):
		loaded_from_save = from_save
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.new_game_button if phase == "new_write" else menu.continue_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched and loaded_from_save == (phase != "new_write"), "The real Start Menu opens the requested game.")
	if stopped:
		return
	bind_map()
	store = WorkStateRuntime.get_node("CitySave")
	board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	if phase != "new_write":
		_expect(FileAccess.get_file_as_bytes(save_path) == before, "Continue does not rewrite the checkpoint.")
	match phase:
		"new_write": await _new_write()
		"new_read": await _new_read()
		"legacy_applicant": await _legacy_applicant(source_bytes)
		"legacy_worker": await _legacy_worker(source_bytes)
	if stopped:
		return
	print("NoHaulerJobBoardTest ", phase, ": PASS")
	get_tree().quit(0)

func _open_board() -> JobBoardUI:
	board.on_player_interact(player)
	_expect(is_instance_valid(board.job_board_ui) and board.job_board_ui.visible, "The actual Job Board opens during its normal hours.")
	return board.job_board_ui

func _contains(ui: JobBoardUI, id: String) -> bool:
	for citizen: CitizenData in ui.applicants:
		if citizen.citizen_id == id:
			return true
	return false

func _index(ui: JobBoardUI, id: String) -> int:
	for index: int in range(ui.applicants.size()):
		if ui.applicants[index].citizen_id == id:
			return index
	return -1

func _verify_board(ui: JobBoardUI) -> void:
	_expect(ui.cards.size() == ui.applicants.size() and ui.applicant_list.item_count == ui.applicants.size(), "Job Board cards and selection indices agree.")
	for index: int in range(ui.applicants.size()):
		var citizen: CitizenData = ui.applicants[index]
		_expect(ui.cards[index].citizen_id == citizen.citizen_id, "Each card belongs to its selectable citizen.")
		if citizen.profession == WorkerData.Profession.HAULER:
			_expect(ui.cards[index].duty_label.text.contains("between city storages"), "The Hauler card describes storage-to-storage deliveries.")

func _hire_via_board(ui: JobBoardUI, id: String) -> void:
	var index: int = _index(ui, id)
	_expect(index >= 0, "Expected applicant is offered: " + id)
	if stopped:
		return
	var profession: WorkerData.Profession = ui.applicants[index].profession
	var before: int = int(Inventory.items.get("shekel", 0))
	var price: int = WorkerDatabase.get_contract_price(profession, 3)
	ui.applicant_list.select(index)
	ui.hire_button.pressed.emit()
	_expect(ui.confirmation_open and not ui.confirm_hire_button.disabled, "Selection opens a valid confirmation.")
	if stopped:
		return
	ui.confirm_hire_button.pressed.emit()
	_expect(WorkerDatabase.get_worker_data(id) != null and WorkerDatabase.get_worker_data(id).profession == profession
		and int(Inventory.items.get("shekel", 0)) == before - price and not _contains(ui, id), "The real UI hires the selected profession and charges once.")
	ui.confirm_hire_button.pressed.emit()
	_expect(int(Inventory.items.get("shekel", 0)) == before - price, "Repeated confirmation does not charge again.")

func _new_write() -> void:
	var first: CitizenData = CitizenManager.get_citizen(LABORER_ID)
	var second: CitizenData = CitizenManager.get_citizen(SECOND_ID)
	var original_laborer: CitizenData = CitizenManager.get_citizen(LEGACY_HAULER_ID)
	_expect(first != null and original_laborer != null and second != null and first.profession == WorkerData.Profession.LABORER and original_laborer.profession == WorkerData.Profession.LABORER and second.profession == WorkerData.Profession.HAULER, "New Game retains two Laborers and adds one Hauler.")
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "New Game has no added wallet grant or worker.")
	# Recreate a pre-update roster with both existing Laborers and no new ID.
	CitizenManager.citizens_by_id.erase(SECOND_ID)
	_expect(store.save_checkpoint(), "The preceding two-Laborer checkpoint saves.")
	_expect(store.load_checkpoint(), "The preceding two-Laborer checkpoint continues.")
	second = CitizenManager.get_citizen(SECOND_ID)
	original_laborer = CitizenManager.get_citizen(LEGACY_HAULER_ID)
	_expect(second != null and second.profession == WorkerData.Profession.HAULER and original_laborer.profession == WorkerData.Profession.LABORER, "Continue adds a separate Hauler without changing the old Laborer.")
	Inventory.add_item("shekel", 5) # Test-only funds for real prepaid hiring.
	var ui: JobBoardUI = _open_board()
	if stopped:
		return
	_verify_board(ui)
	_expect(second.profession == WorkerData.Profession.HAULER and ui.applicants.size() == 3 and _contains(ui, LABORER_ID) and _contains(ui, LEGACY_HAULER_ID) and _contains(ui, SECOND_ID), "The board offers both preserved Laborers and the separate Hauler.")
	second.satisfaction = 1.0
	ui._poll_applicants()
	var live_index: int = _index(ui, SECOND_ID)
	_expect(ui.cards[live_index].satisfaction_label.text == "100%"
		and ui.cards[live_index].mood_icon.texture == preload("res://assets/ui/ui_icon/satisfaction_happy_small_icon.png"),
		"A real applicant changing to 100% updates the card to the happy icon.")
	second.satisfaction = 0.55
	ui._poll_applicants()
	_expect(ui.cards[live_index].mood_icon.texture == preload("res://assets/ui/ui_icon/satisfaction_normal_small_icon.png"),
		"The same live applicant returns to the neutral icon in the middle band.")
	await _capture_review("job-board-hauler.png")
	var second_index: int = _index(ui, SECOND_ID)
	ui.applicant_list.select(second_index)
	ui.hire_button.pressed.emit()
	_expect(ui.confirmation_open, "The stale-selection check begins from a real confirmation.")
	var funds_before: int = int(Inventory.items.get("shekel", 0))
	second.satisfaction = 0.49
	_expect(not bool(ui._quote_for_ids(PackedStringArray([SECOND_ID]), 3).get("valid", true)), "A newly ineligible applicant invalidates an open quote.")
	ui.confirm_hire_button.pressed.emit()
	_expect(WorkerDatabase.get_worker_data(SECOND_ID) == null and int(Inventory.items.get("shekel", 0)) == funds_before, "Confirming a stale applicant neither hires nor debits.")
	ui._cancel_confirmation(false)
	ui._poll_applicants()
	_expect(not _contains(ui, SECOND_ID), "Polling removes the now-ineligible Hauler without an index mismatch.")
	await _capture_review("job-board-disappeared.png")
	second.satisfaction = 0.55
	ui._poll_applicants()
	_expect(_contains(ui, SECOND_ID), "Polling restores the recovered Hauler.")
	var coin := ui.cards[_index(ui, SECOND_ID)].get_node("Details/ShekelIcon") as TextureRect
	var coin_atlas := coin.texture as AtlasTexture
	_expect(coin_atlas != null and coin_atlas.region == Rect2(4, 4, 8, 8)
		and coin_atlas.atlas == preload("res://assets/ui/ui_icon/currency/small_shekel_8x8.png")
		and coin.size == Vector2(8, 8), "A recreated card shows the complete authored Shekel at native size.")
	second.satisfaction = 1.0
	ui._poll_applicants()
	_expect(ui.cards[_index(ui, SECOND_ID)].mood_icon.texture == preload("res://assets/ui/ui_icon/satisfaction_happy_small_icon.png"),
		"The recreated card still refreshes the actual applicant's mood.")
	await _frames(3)
	await _capture_review("job-board-reappeared.png")
	_verify_board(ui)
	_hire_via_board(ui, LABORER_ID)
	ui.close_button.pressed.emit()
	await _frames()
	if stopped:
		return
	ui = _open_board()
	_expect(ui.applicants.size() == 2 and _contains(ui, SECOND_ID) and _contains(ui, LEGACY_HAULER_ID), "Reopening retains both other applicants without duplicates.")
	ui.close_button.pressed.emit()
	await _frames()
	_expect(store.save_checkpoint(), "The new-game state saves: " + store.last_error)

func _new_read() -> void:
	var second: CitizenData = CitizenManager.get_citizen(SECOND_ID)
	_expect(WorkerDatabase.get_worker_data(LABORER_ID) != null and second != null and second.profession == WorkerData.Profession.HAULER, "Continue retains the paid Laborer and Hauler applicant.")
	var ui: JobBoardUI = _open_board()
	if stopped:
		return
	_verify_board(ui)
	_expect(ui.applicants.size() == 2 and _contains(ui, SECOND_ID) and _contains(ui, LEGACY_HAULER_ID), "The saved board retains the remaining Laborer and Hauler.")
	_hire_via_board(ui, SECOND_ID)
	ui.close_button.pressed.emit()
	await _frames()
	_expect(store.save_checkpoint() and store.load_checkpoint(), "The second paid hire saves and reloads.")
	_expect(WorkerDatabase.get_worker_data(SECOND_ID) != null and WorkerDatabase.get_worker_data(SECOND_ID).profession == WorkerData.Profession.HAULER, "Reload retains the paid Hauler.")

func _legacy_applicant(source: PackedByteArray) -> void:
	var legacy: CitizenData = CitizenManager.get_citizen(LEGACY_HAULER_ID)
	_expect(legacy != null and legacy.profession == WorkerData.Profession.HAULER and legacy.employment_status == CitizenData.EmploymentStatus.APPLICANT and is_equal_approx(legacy.satisfaction, 0.5), "The old applicant record and satisfaction survive Continue.")
	var ui: JobBoardUI = _open_board()
	if stopped:
		return
	_verify_board(ui)
	_expect(_contains(ui, LABORER_ID) and _contains(ui, LEGACY_HAULER_ID), "The eligible legacy Hauler is offered alongside the Laborer.")
	ui._poll_applicants()
	ui._refresh_applicants()
	_expect(_contains(ui, LEGACY_HAULER_ID) and CitizenManager.get_citizen(LEGACY_HAULER_ID) == legacy, "Refresh and poll retain the same legacy citizen.")
	var wallet: int = int(Inventory.items.get("shekel", 0))
	Inventory.items["shekel"] = 0 # Fixture-only insufficient funds.
	_expect(WorkerDatabase.hire_applicant(LEGACY_HAULER_ID) == null and WorkerDatabase.hire_applicants(PackedStringArray([LABORER_ID, LEGACY_HAULER_ID])).is_empty(), "Insufficient funds reject single and mixed hires.")
	_expect(int(Inventory.items.get("shekel", 0)) == 0 and WorkerDatabase.get_all_workers().is_empty(), "Rejected hires leave the roster and wallet unchanged.")
	Inventory.items["shekel"] = wallet
	ui.close_button.pressed.emit()
	await _frames()
	_expect(store.save_checkpoint(), "A new explicit save upgrades the legacy applicant checkpoint.")
	_expect(FileAccess.get_file_as_bytes(store.disk.path + ".bak") == source, "The original v12 save is retained as backup.")
	_expect(store.load_checkpoint(), "The upgraded checkpoint loads.")
	legacy = CitizenManager.get_citizen(LEGACY_HAULER_ID)
	_expect(legacy != null and legacy.profession == WorkerData.Profession.HAULER and legacy.employment_status == CitizenData.EmploymentStatus.APPLICANT, "Save/Continue preserves the legacy applicant.")
	legacy.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	legacy.satisfaction = 0.8 # Test-only recovered former Hauler before midnight.
	var day: int = TimeComponentManager.current_day
	var minutes: int = 1440 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute
	_expect(TimeComponentManager.advance_minutes(minutes), "The game clock reaches midnight.")
	_expect(TimeComponentManager.current_day == day + 1 and legacy.satisfaction >= 0.5 and legacy.employment_status == CitizenData.EmploymentStatus.APPLICANT and legacy.profession == WorkerData.Profession.HAULER, "Daily evaluation re-offers the recovered former Hauler.")
	_expect(CitizenManager.evaluate_daily_applications() == 0 and CitizenManager.get_all_applicants().has(legacy), "Repeated evaluation does not duplicate an applicant.")
	_expect(store.save_checkpoint() and store.load_checkpoint(), "The post-midnight legacy state saves and reloads.")
	legacy = CitizenManager.get_citizen(LEGACY_HAULER_ID)
	_expect(legacy != null and legacy.profession == WorkerData.Profession.HAULER and legacy.employment_status == CitizenData.EmploymentStatus.APPLICANT, "Post-midnight Continue retains the applicant and profession.")

func _capture_review(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_REVIEW_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(directory.path_join(filename)) == OK, "The requested UI evidence is captured.")

func _legacy_worker(source: PackedByteArray) -> void:
	var legacy: WorkerData = WorkerDatabase.get_worker_data(LEGACY_HAULER_ID)
	_expect(legacy != null and legacy.profession == WorkerData.Profession.HAULER, "An already-hired Hauler is restored from the synthetic v12 worker copy.")
	if stopped:
		return
	var previous_end: int = legacy.payroll_paid_until_day
	var previous_xp: int = legacy.profession_xp
	var previous_status: int = CitizenManager.get_citizen(LEGACY_HAULER_ID).employment_status
	_expect(store.save_checkpoint() and FileAccess.get_file_as_bytes(store.disk.path + ".bak") == source and store.load_checkpoint(), "The synthetic worker copy upgrades while preserving its exact input as backup.")
	legacy = WorkerDatabase.get_worker_data(LEGACY_HAULER_ID)
	_expect(legacy != null and legacy.profession == WorkerData.Profession.HAULER and legacy.payroll_paid_until_day == previous_end and legacy.profession_xp == previous_xp and CitizenManager.get_citizen(LEGACY_HAULER_ID).employment_status == previous_status, "Save/Continue retains the existing Hauler, XP and paid contract.")
	Inventory.add_item("shekel", 3) # Test-only funds for an existing worker renewal.
	var before: int = int(Inventory.items.get("shekel", 0))
	var price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.HAULER, 3)
	_expect(WorkerDatabase.renew_contract(LEGACY_HAULER_ID, 3) and legacy.payroll_paid_until_day == previous_end + 3 and int(Inventory.items.get("shekel", 0)) == before - price, "A retained legacy Hauler can still renew its existing contract.")
	_expect(store.save_checkpoint() and store.load_checkpoint(), "The renewed legacy contract saves and reloads.")
	legacy = WorkerDatabase.get_worker_data(LEGACY_HAULER_ID)
	_expect(legacy != null and legacy.profession == WorkerData.Profession.HAULER and legacy.payroll_paid_until_day == previous_end + 3 and legacy.profession_xp == previous_xp, "Continue preserves the renewed worker without converting its profession.")
