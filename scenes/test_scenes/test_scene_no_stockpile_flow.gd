extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Isolated three-process integration fixture. It uses a real New Game/menu,
## paid hires, worksite UI, worker approach, natural output and pickup.
## The ten initial Shekels are an explicit test grant, not a New Game change.
const FLOW_DIR: String = "user://no_stockpile_flow_test"
const FLOW_SAVE: String = FLOW_DIR + "/checkpoint.json"
const FLOW_EVIDENCE: String = FLOW_DIR + "/evidence.json"
const WORKER_ID: String = "initial_workshop_laborer"
const HAULER_ID: String = "initial_worksite_hauler"
const WOOD_SITE: StringName = &"WoodSite"
const WOOD: String = "wood_log"
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
	for _minute: int in range(180):
		if runtime._daily_output_count(WOOD_SITE) >= 2:
			break
		for _frame: int in range(20):
			visuals._process(0.05)
		_expect(TimeComponentManager.advance_minutes(1), "The real clock advances the paid worksite.")
		if stopped:
			return
	var ground: int = runtime._daily_output_count(WOOD_SITE)
	_expect(laborer.physical_approach.get("arrived", false) and ground >= 2, "The paid Laborer physically arrives and naturally gathers at least two logs.")
	_expect(int(runtime.sites[WOOD_SITE].stock) + ground == stock_before, "Gathering conserves the finite site stock as real ground output.")
	_expect(int(Inventory.items.get(WOOD, 0)) == wallet_wood_before and int(city_tools.items.get(WOOD, 0)) == city_before and runtime.hauling.routes.is_empty(), "No gathered wood is automatically transferred to player or city.")
	if stopped:
		return
	_expect(store.save_checkpoint(), "Save the naturally produced ground output: " + store.last_error)
	if stopped:
		return
	_write_evidence({"stage": "ground", "initial_stock": stock_before, "site_stock": int(runtime.sites[WOOD_SITE].stock),
		"ground": ground, "player_wood": wallet_wood_before, "initial_player_wood": wallet_wood_before, "city_wood": city_before,
		"worker_xp": laborer.profession_xp, "order": laborer.current_order_id, "clock": now()})

func _read_flow(original_bytes: PackedByteArray) -> void:
	var evidence: Dictionary = _read_evidence("ground")
	if stopped:
		return
	_expect(now() == int(evidence.clock), "Continue restores the checkpoint without advancing the game clock.")
	_assert_ground_state(evidence)
	_expect(store.load_checkpoint() and FileAccess.get_file_as_bytes(FLOW_SAVE) == original_bytes, "Repeated Load keeps the same checkpoint bytes.")
	_assert_ground_state(evidence)
	if stopped:
		return
	var pile: PickUpItem
	for child: Node in runtime.get_node("GroundOutput").get_children():
		if child is PickUpItem and child.item_id == WOOD and child.get_meta("daily_site", "") == str(WOOD_SITE) and not child.is_collecting:
			pile = child as PickUpItem
			break
	_expect(is_instance_valid(pile) and pile.quantity == int(evidence.ground), "The restored output is a real pickup on the ground.")
	if stopped:
		return
	var amount: int = pile.quantity
	await walk(pile.global_position + Vector2(0, -5))
	await interact(pile)
	_expect(int(Inventory.items.get(WOOD, 0)) == int(evidence.player_wood) + amount, "Player E interaction picks up the produced wood.")
	_expect(runtime._daily_output_count(WOOD_SITE) == 0 and int(city_tools.items.get(WOOD, 0)) == int(evidence.city_wood), "Pickup removes the ground stack without transferring it to City Storage.")
	# The item flies away before the player's pickup animation releases movement.
	# Saving is intentionally blocked until both owners finish their animations.
	for _frame: int in range(240):
		if player.can_move and not is_instance_valid(pile):
			break
		await get_tree().physics_frame
	_expect(player.can_move and not is_instance_valid(pile), "The pickup and its movement lock finish before Save; locks=%s, busy=%s" % [player._movement_locks, store.snapshot.busy_reason(content)])
	if stopped:
		return
	_expect(store.save_checkpoint(), "Save after the real player pickup: " + store.last_error)
	if stopped:
		return
	evidence.stage = "picked"
	evidence.player_wood = int(Inventory.items.get(WOOD, 0))
	evidence.ground = 0
	evidence.clock = now()
	_write_evidence(evidence)

func _verify_flow() -> void:
	var evidence: Dictionary = _read_evidence("picked")
	if stopped:
		return
	_assert_ground_state(evidence)
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
	await leave_home()
	if stopped:
		return
	city_tools = WorkStateRuntime.get_node("CityToolStorage")
	_check_scene()
	_assert_ground_state(evidence)
	_expect(now() == int(evidence.clock), "Home and city handoff does not invent elapsed game time.")

func _assert_ground_state(evidence: Dictionary) -> void:
	var laborer: WorkerData = WorkerDatabase.get_worker_data(WORKER_ID)
	_expect(laborer != null and laborer.current_order_id == str(evidence.order)
		and laborer.profession_xp == int(evidence.worker_xp) and not laborer.is_payroll_blocked(), "The same paid Laborer and assignment survive Continue or scene handoff.")
	_expect(runtime.daily.jobs.has(WOOD_SITE) and runtime.daily.jobs[WOOD_SITE].ids == [WORKER_ID] and runtime.hauling.routes.is_empty(), "Only the Laborer owns the restored job.")
	_expect(int(runtime.sites[WOOD_SITE].stock) == int(evidence.site_stock)
		and runtime._daily_output_count(WOOD_SITE) == int(evidence.ground)
		and int(Inventory.items.get(WOOD, 0)) == int(evidence.player_wood)
		and int(city_tools.items.get(WOOD, 0)) == int(evidence.city_wood), "Site, ground, player and City Storage amounts are preserved exactly.")
	_expect(int(evidence.site_stock) + int(evidence.ground) + int(evidence.player_wood) - int(evidence.initial_player_wood) == int(evidence.initial_stock), "The gathered stock remains conserved after pickup.")

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
