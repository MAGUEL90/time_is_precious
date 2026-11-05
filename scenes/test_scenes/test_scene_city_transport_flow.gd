extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Two fresh processes exercise the real menu, storage UI, paid worker, route,
## checkpoint boundary and reverse/cancel/overflow recovery. The initial stock
## and wallet are explicit isolated test grants, not changes to New Game.
const SAVE_PATH: String = "user://city_transport_flow/checkpoint.json"
var worker_id: String = "initial_workshop_laborer"
var hauler_mode: bool = false
const ITEM_ID: String = "wood_log"
const MAX_COUNT: int = 9223372036854775807
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const LEGACY = preload("res://scenes/test_scenes/legacy_reliability_fixture.gd")
var transport: Node
var central: Node
var annex: Node
var store: Node
var continued: bool = false

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--transport-phase="):
			phase = argument.trim_prefix("--transport-phase=")
		elif argument == "--transport-hauler":
			hauler_mode = true
			worker_id = "initial_city_storage_hauler"
	_expect(phase in ["write", "read"], "Choose --transport-phase=write or read.")
	if stopped:
		return
	_expect(FileAccess.file_exists(SAVE_PATH) == (phase == "read"), "Use an isolated profile in write/read order.")
	var before_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SAVE_PATH) if phase == "read" else PackedByteArray()
	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(func(from_save: bool):
		continued = from_save
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.continue_button if phase == "read" else menu.new_game_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched and continued == (phase == "read"), "The actual Start Menu opens the expected session.")
	if stopped:
		return
	bind_map()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	transport = WorkStateRuntime.get_node("CityStorageTransport")
	central = transport.get_storage("city")
	annex = transport.get_storage("annex")
	store = WorkStateRuntime.get_node("CitySave")
	_expect(central == WorkStateRuntime.get_node("CityToolStorage") and runtime.has_node("CityStorageAnnex"), "The city has two distinct city-owned physical locations.")
	if phase == "write":
		await _write_flow()
	else:
		_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == before_bytes, "Continue leaves the saved bytes untouched.")
		await _read_flow()
	if stopped:
		return
	print("CityStorageTransportFlowTest ", phase, ": PASS")
	get_tree().quit(0)

func _write_flow() -> void:
	Inventory.add_item("shekel", 10) # Explicit fixture funding for a normal contract.
	Inventory.add_item(ITEM_ID, 4) # A separate player-owned stock sentinel.
	var courier: WorkerData
	if hauler_mode:
		var job_board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
		await walk(job_board.get_node("InteractableComponent").global_position + Vector2(0, 8))
		await interact(job_board)
		_expect(is_instance_valid(job_board.job_board_ui), "Open the real Job Board for the Hauler.")
		if stopped:
			return
		var candidate_index: int = -1
		for index: int in range(job_board.job_board_ui.applicants.size()):
			if job_board.job_board_ui.applicants[index].citizen_id == worker_id:
				candidate_index = index
		_expect(candidate_index >= 0, "The real Job Board offers the authored Hauler.")
		if stopped:
			return
		job_board.job_board_ui.applicant_list.select(candidate_index)
		job_board.job_board_ui.hire_button.pressed.emit()
		job_board.job_board_ui.confirm_hire_button.pressed.emit()
		courier = WorkerDatabase.get_worker_data(worker_id)
		job_board.job_board_ui.close_button.pressed.emit()
		await _frames()
	else:
		courier = WorkerDatabase.hire_applicant(worker_id, 3)
	_expect(courier != null and not courier.is_payroll_blocked() and (not hauler_mode or courier.profession == WorkerData.Profession.HAULER), "Hire the authored worker using a paid contract.")
	_expect(central.allocate("initial_worksite_cart", worker_id), "Equip the existing city Cart.")
	_expect(central.try_add_worksite_output(ITEM_ID, 6), "Seed six city-owned logs through the city receipt API.")
	if stopped:
		return
	var minute_of_day: int = now() % 1440
	if minute_of_day < 7 * 60:
		_expect(TimeComponentManager.advance_minutes(7 * 60 - minute_of_day), "Advance to the work shift.")
	elif minute_of_day >= 15 * 60:
		_expect(TimeComponentManager.advance_minutes(1440 - minute_of_day + 7 * 60), "Advance to the next work shift.")
	var before_start: Dictionary = store.snapshot.capture(content)
	var values = VALUES.new()
	var old_raw: Dictionary = values.decode(before_start.state)
	LEGACY.strip_v16_owners(old_raw)
	var old: Dictionary = before_start.duplicate(true)
	old.schema_version = 15
	old.state = values.encode(old_raw)
	_expect(store.snapshot.prepare(old, content), "A v15 checkpoint stages an empty annex and route: " + store.snapshot.error)
	_expect(store.snapshot.prepared.annex_storage.items.is_empty() and store.snapshot.prepared.transport.route.is_empty(), "Legacy staging invents no goods or cargo.")
	var board: Node2D = runtime.get_node("CityStorageArea/Board")
	var area: Node = runtime.get_node("CityStorageArea")
	await walk(board.global_position + Vector2(0, 13))
	await interact(area)
	if stopped:
		return
	var access: Node = area.menu
	_expect(is_instance_valid(access) and is_instance_valid(access.haul_button) and access.haul_button.text == "Send", "The real city storage board offers Send.")
	if stopped:
		return
	await press(access.haul_button)
	var dialog: Node = access.haul_ui
	_expect(is_instance_valid(dialog), "The hauling assignment panel opens.")
	if stopped:
		return
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	get_viewport().push_input(cancel_event)
	cancel_event.pressed = false
	get_viewport().push_input(cancel_event)
	await _frames()
	_expect(not is_instance_valid(access.haul_ui) and access.visible and get_tree().paused, "Escape returns to storage while preserving its pause.")
	await press(access.haul_button)
	dialog = access.haul_ui
	_expect(is_instance_valid(dialog), "The hauling panel can be reopened.")
	if stopped:
		return
	var panel: Control = dialog.get_node("Center/Panel")
	_expect(get_viewport().get_visible_rect().encloses(panel.get_global_rect()), "The hauling panel fits the logical gameplay viewport.")
	for action: Control in [dialog.start_button, dialog.cancel_button, dialog.source_option, dialog.worker_option, dialog.item_option, dialog.quantity_spin]:
		_expect(panel.get_global_rect().encloses(action.get_global_rect()), "The hauling control stays inside the panel: " + str(action.name))
	var found_worker: bool = _select_metadata(dialog.worker_option, worker_id)
	var found_item: bool = _select_metadata(dialog.item_option, ITEM_ID)
	_expect(found_worker and found_item, "The panel lists the cart-equipped worker and city-owned logs.")
	dialog.quantity_spin.value = 3
	await _capture_haul_ui("ready")
	var probe: Dictionary = {"calls": 0, "conserved": true, "reentered": false}
	var observe_pickup := func():
		probe.calls += 1
		probe.conserved = bool(probe.conserved) and int(central.items.get(ITEM_ID, 0)) + int(annex.items.get(ITEM_ID, 0)) + int(transport.route.get("quantity", 0)) == 6
		probe.reentered = bool(probe.reentered) or transport.cancel() or TimeComponentManager.advance_minutes(1)
	central.changed.connect(observe_pickup)
	await press(dialog.start_button)
	central.changed.disconnect(observe_pickup)
	_expect(int(probe.calls) > 0 and bool(probe.conserved) and not bool(probe.reentered), "Pickup observers see exactly one stock owner and cannot reenter the route or advance time.")
	_expect(not transport.route.is_empty() and transport.route.worker_id == worker_id and int(transport.route.quantity) == 3, "The real Start button creates an outbound three-log cargo.")
	_expect(int(central.items.get(ITEM_ID, 0)) == 3 and int(annex.items.get(ITEM_ID, 0)) == 0 and int(Inventory.items.get(ITEM_ID, 0)) == 4, "Pickup moves city stock to cargo once, without touching player stock.")
	_expect(dialog.start_button.disabled and not dialog.cancel_button.disabled and dialog.route_label.text.contains("x3"), "The active panel shows its cargo and offers cancellation.")
	await _capture_haul_ui("active")
	_expect(not central.release("initial_worksite_cart", worker_id) and central.has_equipped(worker_id, "cart"), "The active courier's cart cannot be removed mid-shipment.")
	dialog.close()
	access.close()
	await _frames()
	_expect(store.save_checkpoint(), "Save while cargo is in transit: " + store.last_error)
	if stopped:
		return
	_assert_invalid_snapshots()

func _select_metadata(option: OptionButton, value: String) -> bool:
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			option.item_selected.emit(index)
			return true
	return false

func _assert_invalid_snapshots() -> void:
	var document: Dictionary = store.snapshot.capture(content)
	var codec = VALUES.new()
	for invalid_case: String in ["quantity", "source", "worker", "cart", "extra_field", "cursor", "origin", "reservation"]:
		var raw: Dictionary = codec.decode(document.state)
		match invalid_case:
			"quantity": raw.transport.route.quantity = -1
			"source": raw.transport.route.source = "annex"
			"worker": raw.transport.route.worker_id = "missing_worker"
			"cart": raw.city_storage.units.erase("initial_worksite_cart")
			"extra_field": raw.transport.route["forged"] = true
			"cursor": raw.transport.last_tick += 1
			"origin": raw.transport.route.leg_origin = Vector2(9999, 9999)
			"reservation": raw.workers.workers_by_id[worker_id].current_job_id = ""
		var invalid: Dictionary = document.duplicate(true)
		invalid.state = codec.encode(raw)
		_expect(not store.snapshot.prepare(invalid, content), "Reject malformed route checkpoint: " + invalid_case)
		_expect(store.snapshot.capture(content) == document, "Rejected route load does not mutate the live city: " + invalid_case)

func _read_flow() -> void:
	print("Transport flow: restored cargo")
	_expect(int(central.items.get(ITEM_ID, 0)) == 3 and int(annex.items.get(ITEM_ID, 0)) == 0 and int(transport.route.get("quantity", -1)) == 3, "Continue restores source, empty destination and in-flight cargo together.")
	_expect(int(Inventory.items.get(ITEM_ID, 0)) == 4, "Continue preserves the separate player-owned materials.")
	_expect(WorkerDatabase.get_worker_data(worker_id).is_reserved(), "The in-flight worker remains reserved.")
	if stopped:
		return
	await _finish_route()
	print("Transport flow: first delivery completed")
	_expect(int(central.items.get(ITEM_ID, 0)) == 3 and int(annex.items.get(ITEM_ID, 0)) == 3 and int(Inventory.items.get(ITEM_ID, 0)) == 4, "The resumed shipment arrives once and releases the worker.")
	# Reach and use the actual annex board, then start a reverse shipment.
	var area: Node = runtime.get_node("CityStorageAnnex")
	await walk(area.get_node("Board").global_position + Vector2(0, 8))
	await interact(area)
	print("Transport flow: reached annex board")
	if stopped:
		return
	var access: Node = area.menu
	_expect(is_instance_valid(access) and access.storage_id == "annex" and access.deposit_button.disabled, "The reachable annex shows city-owned stock and disallows player deposits.")
	await press(access.haul_button)
	var dialog: Node = access.haul_ui
	_expect(_select_metadata(dialog.worker_option, worker_id) and _select_metadata(dialog.item_option, ITEM_ID), "The annex offers the same worker and delivered city stock.")
	dialog.quantity_spin.value = 2
	await press(dialog.start_button)
	dialog.close()
	access.close()
	await _frames()
	await _finish_route()
	print("Transport flow: reverse delivery completed")
	_expect(int(central.items.get(ITEM_ID, 0)) == 5 and int(annex.items.get(ITEM_ID, 0)) == 1, "A second trip moves two logs back to Central Storage.")
	_expect(transport.start(worker_id, "annex", ITEM_ID, 1), "A third shipment can be scheduled.")
	await interact(area)
	access = area.menu
	_expect(is_instance_valid(access), "The annex board reopens while cargo is in transit.")
	if stopped:
		return
	await press(access.haul_button)
	dialog = access.haul_ui
	_expect(is_instance_valid(dialog) and not dialog.cancel_button.disabled, "The active hauling panel offers cancellation.")
	if stopped:
		return
	await press(dialog.cancel_button)
	_expect(str(transport.route.get("phase", "")) == "returning" and int(transport.route.get("quantity", 0)) == 1,
		"The actual Cancel Route button requests a safe loaded return.")
	await _capture_haul_ui("cancelled")
	dialog.close()
	access.close()
	await _frames()
	await _finish_route()
	print("Transport flow: cancellation completed")
	_expect(int(central.items.get(ITEM_ID, 0)) == 5 and int(annex.items.get(ITEM_ID, 0)) == 1 and int(Inventory.items.get(ITEM_ID, 0)) == 4, "Cancellation returns the cargo to its source without duplication or player debit.")
	# The Laborer variant also models a legacy Hauler for the XP and cargo checks.
	var legacy_hauler: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	legacy_hauler.profession = WorkerData.Profession.HAULER
	CitizenManager.get_citizen(worker_id).profession = WorkerData.Profession.HAULER
	var xp_before: int = legacy_hauler.profession_xp
	# Saturate the destination only after pickup: an arrival can no longer fit.
	_expect(transport.start(worker_id, "city", ITEM_ID, 1), "Begin a city-owned shipment before capacity is exhausted.")
	annex.items[ITEM_ID] = MAX_COUNT # Explicit integer-limit test fixture.
	for _minute: int in range(60):
		if now() >= int(transport.route.get("arrival", MAX_COUNT)):
			break
		_expect(TimeComponentManager.advance_minutes(1), "Advance the loaded cart toward the full annex.")
	_expect(not transport.route.is_empty() and int(transport.route.quantity) == 1 and int(annex.items[ITEM_ID]) == MAX_COUNT and int(central.items.get(ITEM_ID, 0)) == 4 and legacy_hauler.profession_xp == xp_before, "A full destination retains cargo and awards no delivery experience.")
	_expect(store.save_checkpoint(), "Save the refused delivery and cargo together: " + store.last_error)
	var refusal_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SAVE_PATH)
	_expect(store.load_checkpoint() and FileAccess.get_file_as_bytes(SAVE_PATH) == refusal_bytes and int(transport.route.quantity) == 1, "Reload preserves the refused cargo without rewriting the file.")
	print("Transport flow: refused delivery reloaded")
	annex.items[ITEM_ID] = 1 # Simulate the extra capacity becoming available.
	await _finish_route()
	print("Transport flow: refused delivery retried")
	_expect(int(central.items.get(ITEM_ID, 0)) == 4 and int(annex.items.get(ITEM_ID, 0)) == 2 and int(Inventory.items.get(ITEM_ID, 0)) == 4 and WorkerDatabase.get_worker_data(worker_id).profession_xp == xp_before + 1, "A refused delivery retries once and awards one Hauler XP after capacity is freed.")
	# Daily receipts include these resources even though the city does not
	# accept every one as a personal deposit. Exercise actual city-to-city
	# transport rather than assuming the wood route covers the other goods.
	for resource_id: String in ["clay_lump", "reed_bundle", "straw_bundle", "water_jar"]:
		var owned_before: int = int(Inventory.items.get(resource_id, 0))
		_expect(central.try_add_worksite_output(resource_id, 1), "The city receives one fixture worksite output: " + resource_id)
		_expect(transport.available_items("city").has(resource_id) and transport.start(worker_id, "city", resource_id, 1), "The courier picks up the city-owned output: " + resource_id)
		await _finish_route()
		_expect(int(central.items.get(resource_id, 0)) == 0 and int(annex.items.get(resource_id, 0)) == 1 and int(Inventory.items.get(resource_id, 0)) == owned_before,
			"The non-wood shipment arrives exactly once without taking player goods: " + resource_id)
	_expect(transport.start(worker_id, "city", ITEM_ID, 1), "Start a shipment before worker resignation.")
	var citizen: CitizenData = CitizenManager.get_citizen(worker_id)
	_expect(citizen != null, "The courier has its real citizen record.")
	if stopped:
		return
	citizen.satisfaction = 0.0
	WorkerDatabase.resign_idle_workers_at_zero()
	print("Transport flow: resignation requested")
	await _finish_route()
	print("Transport flow: resignation cargo settled")
	await _frames()
	_expect(not WorkerDatabase.has_worker_data(worker_id) and int(central.items.get(ITEM_ID, 0)) + int(annex.items.get(ITEM_ID, 0)) == 6 and int(Inventory.items.get(ITEM_ID, 0)) == 4, "A resigning courier settles city cargo before leaving, without loss or player debit.")

func _capture_haul_ui(label: String) -> void:
	var directory: String = OS.get_environment("TIP_HAUL_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(directory.path_join("haul-" + label + ".png")) == OK,
		"Capture the real hauling panel: " + label)

func _finish_route() -> void:
	for _minute: int in range(600):
		if transport.route.is_empty() or stopped:
			return
		_expect(TimeComponentManager.advance_minutes(1), "Advance one minute of the route.")
		if _minute % 10 == 0:
			await _frames(1)
	_expect(transport.route.is_empty(), "The route finishes within a bounded number of game minutes.")
