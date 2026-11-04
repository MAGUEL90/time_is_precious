extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Isolated three-process integration fixture. It uses a real New Game/menu,
## paid hires, worksite UI, worker approach, direct city receipt and Continue.
## The ten initial Shekels are an explicit test grant, not a New Game change.
const FLOW_DIR: String = "user://no_stockpile_flow_test"
const FLOW_SAVE: String = FLOW_DIR + "/checkpoint.json"
const FLOW_EVIDENCE: String = FLOW_DIR + "/evidence.json"
const WORKER_ID: String = "initial_workshop_laborer"
const HAULER_ID: String = "initial_worksite_hauler"
const WOOD_SITE: StringName = &"WoodSite"
const WOOD: String = "wood_log"
const MAX_INT_VALUE: int = 9223372036854775807
const CONSTRUCTION = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const LEGACY_PENDING_SAVE: String = FLOW_DIR + "/legacy_pending_v14.json"
const OLD_STOCKPILES: Array[String] = ["ClayStorage", "WoodStorage", "ReedStorage", "StrawStorage", "WaterStorage"]

var store: Node
var city_tools: Node
var continued: bool = false

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--stockpile-phase="):
			phase = argument.trim_prefix("--stockpile-phase=")
	_expect(phase in ["write", "read", "verify"], "Use --stockpile-phase=write, read, or verify.")
	if stopped:
		return
	if phase == "write":
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			_expect(not FileAccess.file_exists(FLOW_SAVE + suffix), "Write requires a fresh isolated checkpoint profile.")
	else:
		_expect(FileAccess.file_exists(FLOW_SAVE) and FileAccess.file_exists(FLOW_EVIDENCE), "This phase needs the preceding isolated checkpoint.")
	if stopped:
		return
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(FLOW_SAVE) if phase != "write" else PackedByteArray()
	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = FLOW_SAVE
	menu.session_started.connect(func(from_save: bool):
		continued = from_save
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	if phase == "write":
		await press(menu.new_game_button)
	else:
		await press(menu.continue_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched and continued == (phase != "write"), "The actual Start Menu opens New Game or Continue.")
	if stopped:
		return
	bind_map()
	store = WorkStateRuntime.get_node("CitySave")
	city_tools = WorkStateRuntime.get_node("CityToolStorage")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	if phase != "write":
		_expect(FileAccess.get_file_as_bytes(FLOW_SAVE) == original_bytes, "Continue does not rewrite the saved checkpoint.")
	_check_scene()
	if stopped:
		return
	match phase:
		"write": await _write_flow()
		"read": await _read_flow(original_bytes)
		"verify": await _verify_flow()
	if stopped:
		return
	print("NoStockpileFlowTest ", phase, ": PASS")
	get_tree().quit(0)

func _check_scene() -> void:
	_expect(content.name == "ContentScene" and runtime != null, "The real city and resource-worksite runtime are loaded.")
	if stopped:
		return
	for name: String in OLD_STOCKPILES:
		_expect(not runtime.has_node(name), "No per-material stockpile remains: " + name)
	for name: String in ["ClaySiteA", "WoodSite", "ReedSite", "StrawSite", "WaterSite"]:
		_expect(runtime.has_node("WorksiteMarkers/" + name), "The resource site remains: " + name)
	_expect(runtime.has_node("CityStorageArea/DeliveryPoint") and runtime.city_tools == city_tools, "City Storage and its real delivery point remain.")
	_expect(not runtime.daily.allow_haulers, "The gameplay resource-site policy disables new Hauler work.")

func _write_flow() -> void:
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "The actual New Game starts without wallet or hires.")
	Inventory.add_item("shekel", 10) # Fixture funds; normal contract prices still apply.
	var laborer: WorkerData = WorkerDatabase.hire_applicant(WORKER_ID, 3)
	var hauler: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 3)
	_expect(laborer != null and hauler != null and not laborer.is_payroll_blocked() and not hauler.is_payroll_blocked(), "Both authored Laborers receive real paid contracts from fixture funds.")
	if stopped:
		return
	# Model an already-hired legacy Hauler without making new Hauler recruitment
	# available to gameplay. Old-save loading is tested separately with v12 data.
	hauler.profession = WorkerData.Profession.HAULER
	CitizenManager.get_citizen(HAULER_ID).profession = WorkerData.Profession.HAULER
	_expect(city_tools.allocate("initial_worksite_cart", HAULER_ID), "The Hauler has the real city Cart before the policy check.")
	var stock_before: int = int(runtime.sites[WOOD_SITE].stock)
	var city_before: int = int(city_tools.items.get(WOOD, 0))
	var wallet_wood_before: int = int(Inventory.items.get(WOOD, 0))
	var marker: Node2D = runtime.get_node("WorksiteMarkers/WoodSite")
	# Open the real worksite panel; its card and Start buttons use normal signals.
	runtime._open_site_panel(marker)
	runtime.inspector.select_mode("Daily")
	var assignment = runtime.inspector.assignment_ui
	assignment._open_worker_selection(0)
	await _frames()
	var hauler_card: Button = assignment.worker_list.get_node_or_null("Participant_" + HAULER_ID)
	var laborer_card: Button = assignment.worker_list.get_node_or_null("Participant_" + WORKER_ID)
	_expect(is_instance_valid(hauler_card) and hauler_card.disabled, "The real worksite UI disables an equipped Hauler.")
	_expect(is_instance_valid(laborer_card) and not laborer_card.disabled, "The real worksite UI offers the paid Laborer.")
	var city_endpoint: Node = runtime.get_node("CityStorageArea/DeliveryPoint")
	var city_path: NodePath = runtime.get_path_to(city_endpoint)
	_expect(not runtime.daily.toggle(WOOD_SITE, HAULER_ID), "Direct toggle rejects a new Hauler.")
	_expect(not runtime.daily.select_hauler(WOOD_SITE, HAULER_ID, city_path, "City Storage", 3), "Direct assignment to City Storage is rejected.")
	_expect(not str(runtime._assign_hauler(HAULER_ID, city_path, 3)).is_empty(), "The UI assignment callback also rejects City Storage.")
	_expect(runtime.daily.selected[WOOD_SITE].is_empty() and runtime.hauling.routes.is_empty(), "Rejected attempts create neither a draft nor a route.")
	if stopped:
		return
	laborer_card.pressed.emit()
	await _frames()
	_expect(runtime.daily.selected[WOOD_SITE] == [WORKER_ID], "The real worker card selects the Laborer.")
	assignment.next_button.pressed.emit()
	await _frames()
	_expect(not runtime.inspector.start_button.disabled, "The real worksite Start button accepts the Laborer-only plan.")
	runtime.inspector.start_button.pressed.emit()
	await _frames()
	_expect(runtime.daily.jobs.has(WOOD_SITE) and runtime.daily.jobs[WOOD_SITE].ids == [WORKER_ID], "The Laborer-only worksite job starts through UI.")
	if stopped:
		return
	var visuals: Node = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	var reentry: Dictionary = {"attempts": 0, "accepted": 0}
	var on_city_changed := func():
		reentry.attempts += 1
		if runtime.daily.withdraw(WOOD_SITE, WORKER_ID):
			reentry.accepted += 1
	city_tools.changed.connect(on_city_changed)
	for _minute: int in range(180):
		if int(city_tools.items.get(WOOD, 0)) - city_before >= 2:
			break
		for _frame: int in range(20):
			visuals._process(0.05)
		_expect(TimeComponentManager.advance_minutes(1), "The real clock advances the paid worksite.")
		if stopped:
			city_tools.changed.disconnect(on_city_changed)
			return
	city_tools.changed.disconnect(on_city_changed)
	_expect(int(reentry.attempts) > 0 and int(reentry.accepted) == 0
		and runtime.daily.jobs.has(WOOD_SITE) and runtime.daily.pending_output.is_empty(),
		"City receipt observers cannot withdraw the job and retain already-credited output.")
	var received: int = int(city_tools.items.get(WOOD, 0)) - city_before
	_expect(laborer.physical_approach.get("arrived", false) and received >= 2, "The paid Laborer arrives and naturally produces at least two logs for the city.")
	_expect(int(runtime.sites[WOOD_SITE].stock) + received == stock_before,
		"Direct City Storage receipt conserves the finite site stock.")
	_expect(int(Inventory.items.get(WOOD, 0)) == wallet_wood_before and runtime._daily_output_count(WOOD_SITE) == 0
		and int(runtime.daily.jobs[WOOD_SITE].units) == 0 and runtime.hauling.routes.is_empty(),
		"Worker output reaches City Storage without player inventory, ground output or Hauler cargo.")
	_test_all_authored_outputs()
	if stopped:
		return
	_expect(store.save_checkpoint(), "Save the naturally produced City Storage stock: " + store.last_error)
	if stopped:
		return
	_write_evidence({"stage": "city", "initial_stock": stock_before, "site_stock": int(runtime.sites[WOOD_SITE].stock),
		"player_wood": wallet_wood_before, "initial_city_wood": city_before, "city_wood": int(city_tools.items.get(WOOD, 0)),
		"worker_xp": laborer.profession_xp, "order": laborer.current_order_id, "clock": now()})

func _read_flow(original_bytes: PackedByteArray) -> void:
	var evidence: Dictionary = _read_evidence("city")
	if stopped:
		return
	_expect(now() == int(evidence.clock), "Continue restores the checkpoint without advancing the game clock.")
	_assert_city_state(evidence)
	_expect(store.load_checkpoint() and FileAccess.get_file_as_bytes(FLOW_SAVE) == original_bytes, "Repeated Load keeps the same checkpoint bytes.")
	_assert_city_state(evidence)
	if stopped:
		return
	# Force an integer-limit refusal, persist the still-owned output, and then
	# free capacity. This is a test fixture, not an initial capacity or grant.
	var city_before: int = int(city_tools.items.get(WOOD, 0))
	city_tools.items[WOOD] = MAX_INT_VALUE
	for _minute: int in range(60):
		if int(runtime.daily.jobs[WOOD_SITE].units) > 0:
			break
		_expect(TimeComponentManager.advance_minutes(1), "Advance until one receipt is refused at capacity.")
	var pending: int = int(runtime.daily.jobs[WOOD_SITE].units)
	_expect(pending > 0 and int(city_tools.items[WOOD]) == MAX_INT_VALUE
		and runtime._daily_output_count(WOOD_SITE) == 0,
		"A full City Storage leaves earned goods in the worksite job without a duplicate pile.")
	_expect(store.save_checkpoint(), "Save the refused worksite output: " + store.last_error)
	await _test_legacy_pending_migration(pending)
	if stopped:
		return
	_expect(store.load_checkpoint() and int(runtime.daily.jobs[WOOD_SITE].units) == pending
		and int(city_tools.items[WOOD]) == MAX_INT_VALUE,
		"Continue restores the full storage and pending output together.")
	city_tools.items[WOOD] = city_before # Simulate capacity becoming available.
	var stock_before_retry: int = int(runtime.sites[WOOD_SITE].stock)
	_expect(TimeComponentManager.advance_minutes(1), "Retry the retained output after capacity is freed.")
	_expect(int(runtime.daily.jobs[WOOD_SITE].units) == 0
		and int(runtime.sites[WOOD_SITE].stock) == stock_before_retry
		and int(city_tools.items[WOOD]) == city_before + pending
		and int(city_tools.items[WOOD]) - int(evidence.initial_city_wood)
			== int(evidence.initial_stock) - int(runtime.sites[WOOD_SITE].stock),
		"Restored goods retry next minute without another gathered item and conserve stock exactly once.")
	_test_player_construction_materials()
	if stopped:
		return
	_expect(store.save_checkpoint(), "Save after retrying the direct City Storage receipt: " + store.last_error)
	if stopped:
		return
	evidence.stage = "received"
	evidence.site_stock = int(runtime.sites[WOOD_SITE].stock)
	evidence.city_wood = int(city_tools.items.get(WOOD, 0))
	evidence.worker_xp = WorkerDatabase.get_worker_data(WORKER_ID).profession_xp
	evidence.clock = now()
	_write_evidence(evidence)

func _verify_flow() -> void:
	var evidence: Dictionary = _read_evidence("received")
	if stopped:
		return
	_assert_city_state(evidence)
	if stopped:
		return
	# Exercise the real city/home handoff and back without sleeping or changing time.
	await walk(content.get_node("YSortWorld/HomeDoor").global_position, true)
	while SceneTransition.is_transitioning and not stopped:
		await get_tree().process_frame
	bind_map()
	_expect(content.name == "PlayerHomeInterior", "The real Home Door opens the home scene.")
	if stopped:
		return
	var legacy_bytes: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY_PENDING_SAVE + ".bak")
	var legacy_document: Dictionary = JSON.parse_string(legacy_bytes.get_string_from_utf8())
	var home_before: Dictionary = store.snapshot.capture(content)
	var home_migration_ok: bool = store.snapshot.prepare(legacy_document, content)
	_expect(home_migration_ok and store.snapshot.capture(content) == home_before
		and FileAccess.get_file_as_bytes(LEGACY_PENDING_SAVE + ".bak") == legacy_bytes,
		"The old pending-output snapshot validates from a parked city without mutating home or its backup: " + store.snapshot.error)
	await leave_home()
	if stopped:
		return
	city_tools = WorkStateRuntime.get_node("CityToolStorage")
	_check_scene()
	_assert_city_state(evidence)
	_expect(now() == int(evidence.clock), "Home and city handoff does not invent elapsed game time.")

func _assert_city_state(evidence: Dictionary) -> void:
	var laborer: WorkerData = WorkerDatabase.get_worker_data(WORKER_ID)
	_expect(laborer != null and laborer.current_order_id == str(evidence.order)
		and laborer.profession_xp == int(evidence.worker_xp) and not laborer.is_payroll_blocked(), "The same paid Laborer and assignment survive Continue or scene handoff.")
	_expect(runtime.daily.jobs.has(WOOD_SITE) and runtime.daily.jobs[WOOD_SITE].ids == [WORKER_ID] and runtime.hauling.routes.is_empty(), "Only the Laborer owns the restored job.")
	_expect(int(runtime.sites[WOOD_SITE].stock) == int(evidence.site_stock)
		and runtime._daily_output_count(WOOD_SITE) == 0 and int(runtime.daily.jobs[WOOD_SITE].units) == 0
		and int(Inventory.items.get(WOOD, 0)) == int(evidence.player_wood)
		and int(city_tools.items.get(WOOD, 0)) == int(evidence.city_wood), "Site, ground, player and City Storage amounts are preserved exactly.")
	_expect(int(evidence.site_stock) + int(evidence.city_wood) - int(evidence.initial_city_wood)
		== int(evidence.initial_stock), "The gathered stock remains conserved in City Storage.")

func _test_all_authored_outputs() -> void:
	var before: Dictionary = city_tools.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var site_items: Dictionary = {
		"ClaySiteA": "clay_lump", "WoodSite": "wood_log", "ReedSite": "reed_bundle",
		"StrawSite": "straw_bundle", "WaterSite": "water_jar"
	}
	for site_id: String in site_items:
		var item_id: String = site_items[site_id]
		var marker: Marker2D = runtime.get_node("WorksiteMarkers/" + site_id)
		var quantity_before: int = int(city_tools.items.get(item_id, 0))
		_expect(runtime._deliver_daily_output(2, marker)
			and int(city_tools.items.get(item_id, 0)) == quantity_before + 2
			and runtime._daily_output_count(StringName(site_id)) == 0,
			"The authored worksite delivers its exact resource to the city: " + site_id)
	_expect(Inventory.items == inventory_before, "Worksite receipts never modify the player's construction materials.")
	city_tools.items = before # Remove only this explicit five-resource test grant.

func _test_legacy_pending_migration(pending: int) -> void:
	var document: Dictionary = store.snapshot.capture(content)
	var codec = VALUES.new()
	var raw: Dictionary = codec.decode(document.state)
	# Synthetic v14: a job-owned wood unit and departed workers' clay and Reed
	# were awaiting their old ground drop when the checkpoint was written.
	raw.worksites.schema_version = 3
	raw.worksites.sites.ClaySiteA.stock -= 2
	raw.worksites.sites.ReedSite.stock -= 3
	raw.worksites.pending_output["ClaySiteA"] = 2
	raw.worksites.pending_output["ReedSite"] = 3
	preload("res://scenes/test_scenes/legacy_reliability_fixture.gd").strip_v16_owners(raw)
	document.schema_version = 14
	document.state = codec.encode(raw)
	_expect(codec.error.is_empty() and not FileAccess.file_exists(LEGACY_PENDING_SAVE),
		"Create a fresh synthetic v14 pending-output checkpoint.")
	var prepared: bool = store.snapshot.prepare(document, content)
	_expect(prepared, "Synthetic v14 checkpoint validates and migrates: " + store.snapshot.error)
	if stopped:
		return
	var file := FileAccess.open(LEGACY_PENDING_SAVE, FileAccess.WRITE)
	_expect(file != null, "The isolated v14 checkpoint can be written.")
	if stopped:
		return
	file.store_string(JSON.stringify(document, "\t", true, true) + "\n")
	file.close()
	var old_bytes: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY_PENDING_SAVE)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	store.disk.path = LEGACY_PENDING_SAVE
	_expect(store.load_checkpoint(), "Continue the old pending-output checkpoint: " + store.last_error)
	if stopped:
		return
	var migrated: Dictionary = {WOOD: 0, "clay_lump": 0, "reed_bundle": 0}
	var reed_pile: PickUpItem
	for pile: Node in runtime.get_node("GroundOutput").get_children():
		if bool(pile.get_meta("legacy_stockpile", false)) and migrated.has(pile.item_id):
			migrated[pile.item_id] += int(pile.quantity)
			if pile.item_id == "reed_bundle":
				reed_pile = pile as PickUpItem
	_expect(migrated == {WOOD: pending, "clay_lump": 2, "reed_bundle": 3}
		and int(runtime.daily.jobs[WOOD_SITE].units) == 0 and runtime.daily.pending_output.is_empty()
		and int(city_tools.items[WOOD]) == MAX_INT_VALUE and Inventory.items == inventory_before,
		"Old unsettled goods remain player-pickable on the ground, not converted into city stock.")
	_expect(FileAccess.get_file_as_bytes(LEGACY_PENDING_SAVE) == old_bytes,
		"Continue does not rewrite the original v14 checkpoint.")
	_expect(store.load_checkpoint(), "Repeat Continue on the same original v14 checkpoint.")
	var repeated: Dictionary = {WOOD: 0, "clay_lump": 0, "reed_bundle": 0}
	reed_pile = null
	for pile: Node in runtime.get_node("GroundOutput").get_children():
		if bool(pile.get_meta("legacy_stockpile", false)) and repeated.has(pile.item_id):
			repeated[pile.item_id] += int(pile.quantity)
			if pile.item_id == "reed_bundle":
				reed_pile = pile as PickUpItem
	_expect(repeated == migrated and int(city_tools.items[WOOD]) == MAX_INT_VALUE
		and FileAccess.get_file_as_bytes(LEGACY_PENDING_SAVE) == old_bytes,
		"Repeated Continue does not duplicate migrated piles or rewrite the old checkpoint.")
	if stopped:
		return
	# Reed previously needed a navigable drop position; exercise actual walking
	# and E pickup rather than merely checking that a node was created.
	for offset: Vector2 in [Vector2(0, -5), Vector2(-4, -5), Vector2(4, -5), Vector2(0, 0), Vector2(-5, 0), Vector2(5, 0), Vector2(0, 3)]:
		var candidate: Vector2 = reed_pile.global_position + offset
		if player.test_move(Transform2D(0.0, candidate), Vector2(0.01, 0)):
			continue
		await walk(candidate)
		if stopped or player.current_interactable == reed_pile:
			break
	_expect(is_instance_valid(reed_pile) and player.current_interactable == reed_pile,
		"The migrated Reed pile is reachable and focusable by the player.")
	if stopped:
		return
	await interact(reed_pile)
	_expect(int(Inventory.items.get("reed_bundle", 0)) == int(inventory_before.get("reed_bundle", 0)) + 3,
		"E collects the old Reed output once into the player's inventory.")
	for _frame: int in range(240):
		if player.can_move and not is_instance_valid(reed_pile):
			break
		await get_tree().physics_frame
	_expect(player.can_move and not is_instance_valid(reed_pile), "Legacy pickup finishes before Save.")
	_expect(store.save_checkpoint() and FileAccess.get_file_as_bytes(LEGACY_PENDING_SAVE + ".bak") == old_bytes,
		"The next explicit save retains the exact old checkpoint as its backup.")
	store.disk.path = FLOW_SAVE
	_expect(store.load_checkpoint(), "Restore the current-schema retry fixture after the migration check.")

func _test_player_construction_materials() -> void:
	var state = CONSTRUCTION.new()
	state.order_id = state.CITIZEN_HOUSE_ORDER_ID
	state.phase = "empty" # Isolated post-clearing construction fixture.
	add_child(state)
	var city_before: Dictionary = city_tools.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var capacity_before: float = Inventory.max_load
	Inventory.max_load = 1000.0
	var requirements: Dictionary = state.get_requirements()
	for item_id: String in requirements:
		_expect(city_tools.try_add_worksite_output(item_id, int(requirements[item_id])), "Seed city-owned " + item_id + " for the ownership check.")
	var city_seeded: Dictionary = city_tools.items.duplicate(true)
	_expect(not bool(state.start_build([] as Array[String], true).success)
		and Inventory.items == inventory_before and city_tools.items == city_seeded,
		"City-owned materials alone cannot start player construction.")
	for item_id: String in requirements:
		Inventory.add_item(item_id, int(requirements[item_id]))
	_expect(bool(state.start_build([] as Array[String], true).success)
		and Inventory.items == inventory_before and city_tools.items == city_seeded,
		"Construction consumes exactly the player's materials and leaves the city's stocks untouched.")
	state.interrupt_player_work()
	state.free()
	city_tools.items = city_before
	Inventory.max_load = capacity_before

func _write_evidence(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FLOW_DIR))
	var file := FileAccess.open(FLOW_EVIDENCE, FileAccess.WRITE)
	_expect(file != null, "The isolated evidence file opens.")
	if file != null:
		file.store_string(JSON.stringify(data, "\t", true, true))
		file.close()

func _read_evidence(stage: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FLOW_EVIDENCE))
	_expect(data is Dictionary and data.get("stage") == stage, "The preceding isolated phase produced the expected evidence.")
	return data if data is Dictionary and data.get("stage") == stage else {}
