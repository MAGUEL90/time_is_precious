extends Node

const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const EXTERNAL_PICKUP_SCENE: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")
const EXTERNAL_WORKSHOP_SCENE: PackedScene = preload("res://scenes/workshop/workshop.tscn")
const SITE_A: StringName = &"ClaySiteA"
const SITE_B: StringName = &"ClaySiteB"
const NARAM_ID: String = "worker_laborer_01"
const BELUM_ID: String = "content_hauler_belum"

var failures: int = 0
var content: Node
var worksite
var player: Player
var inventory_ui: InventoryUI
var inspector: Control
var worker_control: WorkerControlUI
var storage_a: StorageDestination
var storage_b: StorageDestination
var deliveries: Array[int] = []
var saved_clock: Dictionary = {}
var saved_tree_paused: bool = false
var saved_needs_disabled: bool = false
var saved_naram_xp: int = 0
var had_belum: bool = false


func _ready() -> void:
	call_deferred("_run")


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _run() -> void:
	_save_and_freeze_clock()
	content = CONTENT_SCENE.instantiate()
	add_child(content)
	await get_tree().process_frame
	await get_tree().process_frame
	_bind_content_nodes()
	if not is_instance_valid(worksite) or not is_instance_valid(player):
		_expect(false, "Content scene must expose its Player and Worksites nodes.")
		_finish()
		return

	# This opt-out belongs only to this regression scene; the shipped Player stays unchanged.
	saved_needs_disabled = player.debug_disable_player_needs
	player.debug_disable_player_needs = true
	_check_shared_content_nodes()
	_check_world_positions_and_output_offsets()
	_check_interaction_and_modal_guards()
	_check_time_shortcuts()
	_run_daily_delivery()
	await _check_progress_and_go_to()
	_finish()


func _save_and_freeze_clock() -> void:
	had_belum = WorkerDatabase.has_worker_data(BELUM_ID)
	saved_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused
	}
	saved_tree_paused = get_tree().paused
	# Start at a known point so F7 and F can be asserted before the Daily plan.
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 6
	TimeComponentManager.current_minute = 0
	TimeComponentManager.is_paused = true
	get_tree().paused = false


func _bind_content_nodes() -> void:
	worksite = content.get_node_or_null("YSortWorld/Worksites")
	player = content.get_node_or_null("YSortWorld/Player") as Player
	inventory_ui = content.get_node_or_null("InventoryUI") as InventoryUI
	if is_instance_valid(worksite):
		inspector = worksite.get_node_or_null("InspectionUI/ClayWorksiteInspector") as Control
		worker_control = worksite.get_node_or_null("WorkerControlUI") as WorkerControlUI
		storage_a = worksite.get_node_or_null("StorageA") as StorageDestination
		storage_b = worksite.get_node_or_null("StorageB") as StorageDestination


func _check_shared_content_nodes() -> void:
	_expect(content.find_children("Player", "", true, false).size() == 1,
		"The integrated content scene must contain exactly one Player.")
	_expect(content.find_children("InventoryUI", "", true, false).size() == 1,
		"The integrated content scene must use exactly one shared InventoryUI.")
	_expect(content.find_children("TopHUD", "", true, false).size() == 1
		and content.find_children("BottomHUD", "", true, false).size() == 1
		and content.find_children("WorkProgressUI", "", true, false).size() == 1,
		"The integrated content scene must keep one shared HUD/progress stack.")
	_expect(worksite.find_children("ClayWorksiteInspector", "", true, false).size() == 1
		and worksite.find_children("WorkerControlUI", "", true, false).size() == 1,
		"Content worksite must expose one Worksite inspector and one Worker Hub.")
	_expect(storage_a != null and storage_b != null
		and int(storage_a.get_storage().get("capacity")) == 96
		and int(storage_b.get_storage().get("capacity")) == 96,
		"Content Worksites must expose both authored StorageDestination nodes at capacity 96.")
	_expect(worksite.inventory_ui == inventory_ui and worksite.player == player,
		"Content Worksites must bind to the map's shared InventoryUI instance.")


func _check_world_positions_and_output_offsets() -> void:
	var site_a: Marker2D = worksite.get_node("WorksiteMarkers/ClaySiteA") as Marker2D
	var site_b: Marker2D = worksite.get_node("WorksiteMarkers/ClaySiteB") as Marker2D
	var ground: Node2D = worksite.get_node("GroundOutput") as Node2D
	var authored_worksite_position: Vector2 = worksite.position
	var authored_ground_position: Vector2 = ground.position
	var original_site_position: Vector2 = site_a.position
	var authored_site_a_global: Vector2 = site_a.global_position
	var authored_site_b_global: Vector2 = site_b.global_position
	var authored_ground_global: Vector2 = ground.global_position
	var worksite_offset := Vector2(37, -19)
	var ground_offset := Vector2(13, -7)
	var site_offset := Vector2(9, 4)
	worksite.position = authored_worksite_position + worksite_offset
	ground.position = authored_ground_position + ground_offset
	site_a.position += site_offset
	_expect(site_a.global_position.is_equal_approx(authored_site_a_global + worksite_offset + site_offset)
		and site_b.global_position.is_equal_approx(authored_site_b_global + worksite_offset),
		"Content site world positions must include authored parent and test translation offsets.")
	_expect(ground.global_position.is_equal_approx(authored_ground_global + worksite_offset + ground_offset),
		"GroundOutput must preserve its world position through Worksites and local translation.")

	_expect(worksite._drop_daily_output(1, site_a), "Site A must accept a daily output drop.")
	var site_a_stack: Node2D = ground.get_child(-1) as Node2D
	_expect(site_a_stack.global_position.is_equal_approx(site_a.global_position + Vector2(0, 24)),
		"Site A output must land at site world position plus its authored offset.")

	_expect(worksite._drop_daily_output(1, site_b), "Site B must accept a daily output drop.")
	var site_b_stack: Node2D = ground.get_child(-1) as Node2D
	_expect(site_b_stack.global_position.is_equal_approx(site_b.global_position + Vector2(0, 24)),
		"Site B output must land at site world position plus its authored offset.")

	player.global_position = site_a.global_position + Vector2(0, 20)
	_expect(worksite._drop_output(1), "Player output drop must be accepted.")
	var player_stack: Node2D = ground.get_child(-1) as Node2D
	_expect(player_stack.global_position.is_equal_approx(player.global_position + Vector2(0, 16)),
		"Player output must convert through GroundOutput to player world position plus offset.")
	# These are coordinate probes only; leave no cargo for the Daily test below.
	site_a_stack.queue_free()
	site_b_stack.queue_free()
	player_stack.queue_free()
	worksite.position = authored_worksite_position
	ground.position = authored_ground_position
	site_a.position = original_site_position
	player.global_position = site_a.global_position + Vector2(0, 20)


func _check_interaction_and_modal_guards() -> void:
	var pickup_fixture: Node = EXTERNAL_PICKUP_SCENE.instantiate()
	player.current_interactable = pickup_fixture
	player.can_interact = true
	worksite._unhandled_input(_action("interact"))
	_expect(not inspector.visible, "Existing map pickups retain priority over Worksite E.")
	player.current_interactable = null
	player.can_interact = false
	pickup_fixture.free()

	var workshop_fixture: Node = EXTERNAL_WORKSHOP_SCENE.instantiate()
	player.current_interactable = workshop_fixture
	worksite._unhandled_input(_action("interact"))
	_expect(not inspector.visible, "Existing workshops retain priority over Worksite E.")
	player.current_interactable = null
	workshop_fixture.free()

	worksite._unhandled_input(_action("interact"))
	_expect(inspector.visible and get_tree().paused and not player.can_move,
		"Opening the Worksite inspector must lock movement and pause the world.")
	var modal_time: int = worksite.daily.now()
	worksite._unhandled_input(_key(KEY_F7))
	worksite._unhandled_input(_key(KEY_F))
	_expect(worksite.daily.now() == modal_time,
		"F and F7 must be ignored while the Worksite inspector owns input.")
	worksite._close_inspector()

	inventory_ui.open_inventory()
	modal_time = worksite.daily.now()
	worksite._unhandled_input(_key(KEY_F7))
	worksite._unhandled_input(_key(KEY_F))
	_expect(worksite.daily.now() == modal_time,
		"F and F7 must be ignored while the shared inventory is open.")
	inventory_ui.close_inventory()

	worker_control.open()
	modal_time = worksite.daily.now()
	worksite._unhandled_input(_key(KEY_F7))
	worksite._unhandled_input(_key(KEY_F))
	_expect(worksite.daily.now() == modal_time,
		"F and F7 must be ignored while the Worker Hub owns input.")
	worker_control.close()
	_expect(not get_tree().paused and player.can_move,
		"Closing modal content UI must restore movement and world pause state.")


func _check_time_shortcuts() -> void:
	var before_f7: int = worksite.daily.now()
	worksite._unhandled_input(_key(KEY_F7))
	_expect(worksite.daily.now() == before_f7 + 30,
		"F7 must advance the frozen test clock by exactly 30 minutes.")
	worksite._unhandled_input(_key(KEY_F))
	_expect(TimeComponentManager.current_day == 1
		and TimeComponentManager.current_hour == 6
		and TimeComponentManager.current_minute == 45,
		"F must advance the test clock to the next day at 06:45.")


func _run_daily_delivery() -> void:
	var naram: WorkerData = WorkerDatabase.get_worker_data(NARAM_ID)
	var belum: WorkerData = WorkerDatabase.get_worker_data(BELUM_ID)
	_expect(naram != null and naram.get_resolved_display_name() == "Naram",
		"Content Daily must use the existing worker_laborer_01/Naram worker.")
	_expect(belum != null and belum.get_resolved_display_name() == "Belum",
		"Content Worksites must seed the optional legacy Belum Hauler fixture.")
	if naram == null or belum == null:
		return

	saved_naram_xp = naram.profession_xp
	naram.profession_xp = 0
	_expect(not worksite.daily.toggle(SITE_A, BELUM_ID),
		"A Hauler without a cart must not enter the Daily roster.")
	_expect(worksite.daily.unavailable(BELUM_ID).begins_with("Requires a cart"),
		"The missing cart requirement must be exposed by the Daily roster.")
	_expect(worksite.worker_management.equip(BELUM_ID, "content_cart") == "Tool equipped.",
		"Belum must equip the content cart from City Storage.")
	_expect(worksite.daily.toggle(SITE_A, NARAM_ID),
		"Existing Naram must be selectable as the Daily laborer.")
	_expect(worksite.daily.select_hauler(
		SITE_A, BELUM_ID, worksite.get_path_to(storage_a), storage_a.display_name, 20
	), "Equipped Belum must accept one Storage A destination and target 20.")
	_expect(worksite.daily.selected[SITE_A] == [NARAM_ID, BELUM_ID],
		"Daily setup must contain Naram and Belum in the two available slots.")
	_expect(worksite.daily.start_reason(SITE_A).is_empty(),
		"The configured cart and Storage A must make the Daily plan startable.")
	var start_day: int = TimeComponentManager.current_day
	_expect(worksite.daily.start(SITE_A, worksite._drop_daily_output.bind(
		worksite.get_node("WorksiteMarkers/ClaySiteA")
	)), "Daily start must commit the actual content worksite plan.")
	_expect(worksite.daily.jobs[SITE_A].starts[NARAM_ID] == (start_day + 1) * 1440 + 420,
		"Daily assignment must begin next day at 07:00.")
	_expect(worksite.hauling.routes[BELUM_ID].daily_target == 20,
		"Belum's committed route must retain its target of exactly 20.")

	deliveries.clear()
	storage_a.delivery_received.connect(func(_item_id: String, quantity: int): deliveries.append(quantity))
	TimeComponentManager.advance_minutes((start_day + 1) * 1440 + 420 - worksite.daily.now())
	var guard: int = 0
	while not worksite.hauling.target_reached(BELUM_ID, TimeComponentManager.current_day) and guard < 720:
		TimeComponentManager.advance_minutes(1)
		guard += 1
	_expect(worksite.hauling.target_reached(BELUM_ID, TimeComponentManager.current_day),
		"Repeated manual clock ticks must complete the 20-item daily target.")
	_expect(deliveries == [3, 3, 3, 3, 3, 3, 2],
		"Hauler delivery must accept six full three-item trips and a final two-item trip.")
	var stats: Dictionary = worksite.daily.jobs[SITE_A].stats
	var storage_backend: Node = storage_a.get_storage()
	_expect(int(storage_backend.get("quantity")) == 20,
		"Storage A must contain exactly the accepted target quantity.")
	_expect(stats[NARAM_ID].output > 0 and naram.profession_xp == stats[NARAM_ID].output,
		"Naram's gathered output must award matching profession XP.")
	_expect(stats[BELUM_ID].output == 20 and belum.profession_xp == 20,
		"Belum's accepted deliveries must award exactly 20 profession XP.")
	_expect(worksite.worker_management.productive_days[NARAM_ID].size() == 1
		and worksite.worker_management.productive_days[BELUM_ID].size() == 1,
		"Naram and Belum must each record one productive day.")


func _check_progress_and_go_to() -> void:
	var site_a: Marker2D = worksite.get_node("WorksiteMarkers/ClaySiteA") as Marker2D
	worksite._open_site_panel(site_a)
	await get_tree().process_frame
	_expect(inspector.progress_button.visible,
		"Active Daily work must expose Worker Progress in the Worksite inspector.")
	inspector.progress_button.pressed.emit()
	await get_tree().process_frame
	_expect(inspector.progress_panel.visible and inspector.progress_list.get_child_count() == 2,
		"Worker Progress must show both the laborer and Hauler rows.")
	var progress_text: String = ""
	for row: Node in inspector.progress_list.get_children():
		progress_text += row.get_child(0).text
	_expect(progress_text.contains("Storage A") and progress_text.contains("20 / 20"),
		"Worker Progress must show the Hauler destination and accepted target.")
	var progress_close: BaseButton = inspector.progress_panel.get_node(
		"Margin/ProgressContent/Header/CloseButton"
	) as BaseButton
	progress_close.pressed.emit()
	await get_tree().process_frame
	_expect(not inspector.visible and not get_tree().paused and player.can_move,
		"Closing Worker Progress must restore the map interaction state.")

	var player_before: Vector2 = player.global_position
	var camera_before: Vector2 = player.get_node("Camera2D").offset
	worker_control.open()
	worker_control._show_manage(NARAM_ID)
	_expect(not worker_control.manage_goto_button.disabled,
		"The active Laborer must enable Worker Hub Go To after the Hauler target is complete.")
	worker_control.manage_goto_button.pressed.emit()
	await get_tree().process_frame
	_expect(not worker_control.visible and inspector.visible,
		"Worker Hub Go To must open the assigned Worksite inspector.")
	_expect(worksite._selected_site.name == SITE_A and not player.can_move,
		"Worker Hub Go To must select the assigned site and keep movement locked.")
	_expect(player.global_position == player_before
		and player.get_node("Camera2D").offset == camera_before,
		"Worker Hub Go To must leave both Player and camera positions unchanged.")
	worksite._close_inspector()


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event

func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _finish() -> void:
	print("ContentWorksitesIntegrationTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)


func _exit_tree() -> void:
	if is_instance_valid(player):
		player.debug_disable_player_needs = saved_needs_disabled
	if is_instance_valid(worksite) and worksite.daily != null:
		worksite.daily.cleanup()
	if not had_belum:
		WorkerDatabase.workers_by_id.erase(BELUM_ID)
	if saved_clock.has("day"):
		TimeComponentManager.current_day = int(saved_clock.day)
		TimeComponentManager.current_hour = int(saved_clock.hour)
		TimeComponentManager.current_minute = int(saved_clock.minute)
		TimeComponentManager.current_weather = str(saved_clock.weather)
		TimeComponentManager.is_paused = bool(saved_clock.paused)
		get_tree().paused = saved_tree_paused
	var naram: WorkerData = WorkerDatabase.get_worker_data(NARAM_ID)
	if naram != null:
		naram.profession_xp = saved_naram_xp
