class_name Player extends CharacterBody2D

const NIGHTMARE_ENTRY_MESSAGE: String = \
"You have neglected the pillars of life. Now, face the consequences."

enum ConditionSeverity {
	NORMAL,
	WARNING,
	CRITICAL
}

signal condition_changed
signal experience_changed
signal collapse_started
signal collapse_completed(duration_minutes: int)
signal sleep_completed(duration_minutes: int, recovery_quality: float)

@export var speed: float = 50.0
@export var debug_disable_player_needs: bool = false
@export var fatigue: float = 0.5 # << Hanya Tester
@export var min_fatigue: float = 0.0
@export var max_fatigue: float = 1.0
@export var hunger: float = 0.0
@export var hunger_increase_per_min: float = 0.001
@export var min_hunger: float = 0.0
@export var max_hunger: float = 1.0
@export var fatigue_increase_per_min: float = 0.0005
@export var focus_loss_per_min: float = 0.00025
@export var focus_loss_from_fatigue_per_min: float = 0.0005
@export var focus_loss_from_hunger_per_min: float = 0.00035
@export var sleep_duration_minutes: int = 420
@export_range(0.0, 1.0, 0.01) var sleep_fatigue_recovery: float = 0.65
@export_range(0.0, 1.0, 0.01) var sleep_focus_recovery: float = 0.75
@export_range(0.0, 1.0, 0.01) var focus: float = 1.0
@export_range(0, 10000, 1) var current_experience: int = 0
@export_range(1, 10000, 1) var experience_required: int = 100

@export_group("Condition Thresholds")

@export_range(0.0, 1.0, 0.01) var fatigue_warning_threshold: float = 0.75
@export_range(0.0, 1.0, 0.01) var fatigue_critical_threshold: float = 0.90

@export_range(0.0, 1.0, 0.01) var hunger_warning_threshold: float = 0.75
@export_range(0.0, 1.0, 0.01) var hunger_critical_threshold: float = 0.90

@export_range(0.0, 1.0, 0.01) var focus_warning_threshold: float = 0.30
@export_range(0.0, 1.0, 0.01) var focus_critical_threshold: float = 0.10

@export_group("")

@export_group("Collapse")

@export_range(0.0, 1.0, 0.01) var collapse_hunger_cost: float = 0.20
@export_range(0.0, 1.0, 0.01) var collapse_fatigue_recovery: float = 0.30
@export_range(0.0, 1.0, 0.01) var collapse_focus_recovery: float = 0.25

@export_group("")

@onready var player_movement_state: Node = $PlayerStateMachine/PlayerMovementState
@onready var time_component_manager = TimeComponentManager
@onready var player_visual: PlayerVisual = $PlayerVisual

var player_sprite_direction: Vector2 = Vector2.RIGHT
var current_interactable: Node = null
var nearby_interactables: Array[Node] = []
var current_npc_dialogue: NPCBase = null

var can_move: bool = true
var can_interact: bool = false
var dialogue_finished: bool = false
var total_collapse_count: int = 0

var claim_menu_is_open: bool = false
var inventory_is_open: bool = false
var claim_menu_workshop: WorkShop = null
var selected_workshop_job: JobData = null
var claim_menu_claimable_index: int = 0
var is_sleeping: bool = false
var last_sleep_day: int = -1
var is_collapsing: bool = false
var last_collapse_day: int = -1


# Lifecycle and time updates

func _ready() -> void:
	PlayerRuntimeState.restore(self)
	if debug_disable_player_needs:
		_reset_debug_needs()

	BaseDialogueManager.dialogue_activated.connect(on_dialogue_activated)
	BaseDialogueManager.dialogue_deactivated.connect(on_dialogue_deactivated)
	TimeComponentManager.minute_changed.connect(on_minute_changed)

func _exit_tree() -> void:
	PlayerRuntimeState.capture(self)

func _process(_delta: float) -> void:
	if can_move and not nearby_interactables.is_empty():
		_refresh_current_interactable()

func on_minute_changed(_minute: int) -> void:
	if debug_disable_player_needs:
		_reset_debug_needs()
		return
	if is_sleeping:
		hunger = clampf(
			hunger + hunger_increase_per_min,
			min_hunger,
			max_hunger
		)
		return

	increase_hunger(hunger_increase_per_min)
	increase_fatigue(fatigue_increase_per_min)
	_apply_awake_focus_loss()
	_check_for_collapse()

# Input routing

func _unhandled_input(event: InputEvent) -> void:
	if not can_move:
		return

	if not event.is_action_pressed("interact"):
		return
	if not can_interact or current_interactable == null:
		return

	if current_interactable is NPCBase:
		var npc: NPCBase = current_interactable as NPCBase

		current_interactable = npc
		current_npc_dialogue = npc

		if npc.global_position.x >= global_position.x:
			npc.animated_sprite_2d.flip_h = true
		else:
			npc.animated_sprite_2d.flip_h = false

		if not npc.start_dialogue():
			current_npc_dialogue = null # dialog gagal mulai: jangan pause waktu, jangan simpan referensi stale
			return

		time_component_manager.toggle_pause()
		npc.interactable_label_component.hide()
		return

	# selain NPC: panggil method interact khusus kalau ada
	elif current_interactable is WorkShop:
		var work_shop: WorkShop = current_interactable as WorkShop
		work_shop.on_player_interact(self)
		work_shop.interactable_label_component.hide()

	elif current_interactable is PickUpItem:
		var pickup_item: PickUpItem = current_interactable as PickUpItem
		pickup_item.on_player_interact(self)
		if pickup_item.is_collecting:
			_on_interactable_deactivated(pickup_item)
		_play_pickup_action()

	elif current_interactable is JobBoard:
		var job_board: JobBoard = current_interactable as JobBoard
		job_board.on_player_interact(self)

	elif current_interactable is SleepSpot:
		var sleep_spot: SleepSpot = current_interactable as SleepSpot
		sleep_spot.on_player_interact(self)

# Interactable state

func _on_interactable_activated(interactable_owner: Node):
	if interactable_owner is NPCBase and not (interactable_owner as NPCBase).can_start_dialogue():
		return # NPC tanpa dialog valid: jangan tampilkan prompt interact palsu, jangan jadikan interactable

	if not nearby_interactables.has(interactable_owner):
		nearby_interactables.append(interactable_owner)

	if can_move:
		_refresh_current_interactable()

func _on_interactable_deactivated(interactable_owner: Node):
	nearby_interactables.erase(interactable_owner)
	if current_interactable == interactable_owner:
		_refresh_current_interactable()

func _refresh_current_interactable() -> void:
	for index: int in range(nearby_interactables.size() - 1, -1, -1):
		var candidate: Node = nearby_interactables[index]
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			nearby_interactables.remove_at(index)

	var nearest_interactable: Node = null
	var nearest_distance_squared: float = INF
	for candidate: Node in nearby_interactables:
		if not candidate is Node2D:
			continue

		var candidate_node: Node2D = candidate as Node2D
		var distance_squared: float = global_position.distance_squared_to(
			candidate_node.global_position
		)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_interactable = candidate

	_set_current_interactable(nearest_interactable)

func _set_current_interactable(next_interactable: Node) -> void:
	if current_interactable == next_interactable:
		can_interact = current_interactable != null
		return

	if is_instance_valid(current_interactable):
		if current_interactable is PickUpItem:
			(current_interactable as PickUpItem).on_player_exit_interaction()

		var previous_label: CanvasItem = _get_interactable_label(current_interactable)
		if previous_label != null:
			previous_label.hide()

	current_interactable = next_interactable
	can_interact = current_interactable != null
	if current_interactable == null:
		return

	if current_interactable is PickUpItem:
		(current_interactable as PickUpItem).on_player_enter_interaction()

	var current_label: CanvasItem = _get_interactable_label(current_interactable)
	if current_label != null:
		current_label.show()

func _get_interactable_label(interactable_owner: Node) -> CanvasItem:
	if not is_instance_valid(interactable_owner):
		return null

	var label_node: Variant = interactable_owner.get("interactable_label_component")
	if label_node is CanvasItem:
		return label_node as CanvasItem
	return null

# Dialogue flow

func on_dialogue_activated() -> void:
	can_move = false
	velocity = Vector2.ZERO

	if current_npc_dialogue:
		current_npc_dialogue.on_dialogue  = true
		current_npc_dialogue.can_walk = false
		current_npc_dialogue.walk_cycle_duration.stop()

func on_dialogue_deactivated() -> void:
	can_move = true

	time_component_manager.toggle_pause()
	if current_npc_dialogue:
		current_npc_dialogue.on_dialogue  = false
		current_npc_dialogue.can_walk = true
		current_npc_dialogue.walk_cycle_duration.start()

	current_npc_dialogue  = null

# Workshop main menu flow

func open_workshop_menu(workshop: WorkShop, claimable_index: int) -> void:
	claim_menu_is_open = true
	claim_menu_workshop = workshop
	claim_menu_claimable_index = claimable_index

	var storage_state: Dictionary = workshop.get_storage_state()

	var menu_scene: PackedScene = preload("res://scenes/ui/workshop_menu_ui/workshop_menu_ui.tscn")
	var menu_ui: WorkshopMenuUI = menu_scene.instantiate()

	get_tree().current_scene.add_child(menu_ui)

	menu_ui.action_selected.connect(_on_work_shop_menu_action_selected)
	menu_ui.closed.connect(_on_workshop_menu_closed)

	menu_ui.open_menu(storage_state)

# Workshop fee actions

func _close_claim_menu() -> void:
	selected_workshop_job = null
	claim_menu_is_open = false
	claim_menu_workshop = null
	claim_menu_claimable_index = 0

# Fatigue, hunger, and condition accessors

func reduce_fatigue(amount: float) -> bool:
	if fatigue > min_fatigue and amount > 0.0:
		fatigue = clampf(fatigue- amount, min_fatigue, max_fatigue)
		condition_changed.emit()
		return true

	return false

func increase_fatigue(amount: float) -> bool:
	if debug_disable_player_needs:
		return false
	if fatigue < max_fatigue and amount > 0.0:
		fatigue = clampf(fatigue + amount, min_fatigue, max_fatigue)
		condition_changed.emit()
		return true
	return false

func reduce_hunger(amount: float) -> bool:
	if hunger > min_hunger and amount > 0.0:
		hunger = clampf(hunger - amount, min_hunger, max_hunger)
		condition_changed.emit()
		return true

	return false

func increase_hunger(amount: float) -> bool:
	if debug_disable_player_needs:
		return false
	if hunger < max_hunger and amount > 0.0:
		hunger = clampf(hunger + amount, min_hunger, max_hunger)
		condition_changed.emit()
		return true
	return false

func get_focus() -> float:
	return focus

func get_fatigue_percent() -> int:
	return int(fatigue * 100.0)

func get_hunger_percent() -> int:
	return int(hunger * 100.0)

func get_focus_percent() -> int:
	return int(get_focus() * 100.0)

# Workshop storage menu flow

func _open_workshop_storage_menu_ui() -> void:
	if claim_menu_workshop == null:
		return

	var workshop_storage_scene: PackedScene = preload("res://scenes/ui/workshop_storage_menu_ui/workshop_storage_menu_ui.tscn")
	var workshop_storage_menu: WorkshopStorageMenuUI = workshop_storage_scene.instantiate()

	get_tree().current_scene.add_child(workshop_storage_menu)

	workshop_storage_menu.action_selected.connect(_on_workshop_storage_menu_action_selected)
	workshop_storage_menu.pay_lot_requested.connect(
		_on_workshop_output_lot_payment_requested
	)
	workshop_storage_menu.pay_all_requested.connect(
		_on_workshop_storage_pay_all_requested
	)
	workshop_storage_menu.withdraw_items_requested.connect(
		_on_workshop_free_stock_withdraw_requested
	)
	workshop_storage_menu.closed.connect(_on_workshop_storage_menu_closed)

	claim_menu_is_open = false
	workshop_storage_menu.open_menu(
		claim_menu_workshop.get_storage_state()
	)

# Workshop production selection flow

func _open_workshop_build_ui() -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		_show_current_interact_label()
		return

	var build_scene: PackedScene = preload(
		"res://scenes/ui/workshop_build_ui/workshop_build_ui.tscn"
	)
	var build_ui: WorkshopBuildUI = build_scene.instantiate()
	get_tree().current_scene.add_child(build_ui)
	build_ui.back_requested.connect(_on_workshop_build_back_requested)
	build_ui.cancelled.connect(_on_workshop_build_cancelled)

	claim_menu_is_open = false
	build_ui.open_menu()

func _on_workshop_build_back_requested() -> void:
	return_to_workshop_main_menu()

func _on_workshop_build_cancelled() -> void:
	_close_claim_menu()
	_show_current_interact_label()

func _open_workshop_production_ui() -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		_show_current_interact_label()
		return

	var production_scene: PackedScene = preload(
		"res://scenes/ui/workshop_production_ui/workshop_production_ui.tscn"
	)
	var production_ui: WorkshopProductionUI = production_scene.instantiate()
	get_tree().current_scene.add_child(production_ui)

	production_ui.work_order_selected.connect(
		_on_workshop_work_order_selected
	)

	production_ui.back_requested.connect(
		_on_workshop_production_back_requested
	)

	production_ui.cancelled.connect(
		_on_workshop_production_cancelled
	)

	claim_menu_is_open = false
	production_ui.open_menu(claim_menu_workshop)

func _on_workshop_work_order_selected(
	work_order_id: String,
	work_order_type: int
) -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		_show_current_interact_label()
		return

	if (work_order_type == WorkOrderCard.WorkOrderType.JOB):
		var job_data: JobData = (claim_menu_workshop.get_job_data(work_order_id))

		if job_data == null:
			print("Workshop job is unavailable: ", work_order_id)
			_open_workshop_production_ui()
			return

		selected_workshop_job = job_data
		_open_workshop_worker_assignment_ui(claim_menu_workshop.get_assigned_worker_ids())
		return

	selected_workshop_job = null

	if work_order_type == WorkOrderCard.WorkOrderType.PROCESS:
		_start_selected_workshop_process(work_order_id)
		return

	print("Unsupported work order: ", work_order_id)
	_open_workshop_production_ui()

func _start_selected_workshop_process(process_id: String) -> void:
	var availability: Dictionary = (
		ProcessManager.get_process_availability(process_id)
	)
	var quantity: int = int(availability.get("startable_quantity", 0))

	if (
		not bool(availability.get("can_start", false))
		or quantity <= 0
	):
		print("Process is no longer available: ", process_id)
		_open_workshop_production_ui()
		return

	var process_started: bool = (
		ProcessManager.start_registered_process(
			process_id,
			quantity
		)
	)
	if not process_started:
		print("Process failed to start: ", process_id)
		_open_workshop_production_ui()
		return

	print("Process started: ", process_id, " x", quantity)
	_close_claim_menu()
	_show_current_interact_label()

func _on_workshop_production_back_requested() -> void:
	return_to_workshop_main_menu()

func _on_workshop_production_cancelled() -> void:
	_close_claim_menu()
	_show_current_interact_label()

# Workshop worker assignment flow

func _open_workshop_worker_assignment_ui(current_worker_ids: Array[String] = []) -> void:
	if claim_menu_workshop == null:
		return

	var worker_assignment_scene: PackedScene = preload("res://scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.tscn")
	var worker_assignment_menu: WorkshopWorkerAssignmentUI = worker_assignment_scene.instantiate()

	get_tree().current_scene.add_child(worker_assignment_menu)

	worker_assignment_menu.assignment_next_requested.connect(_on_workshop_worker_assignment_next_requested)
	worker_assignment_menu.assignment_changed.connect(_on_workshop_worker_assignment_changed)
	worker_assignment_menu.assignment_back_requested.connect(_on_workshop_worker_assignment_back_requested)
	worker_assignment_menu.assignment_cancelled.connect(_on_workshop_worker_assignment_cancelled)

	claim_menu_is_open = false
	worker_assignment_menu.open_assignment(
		current_worker_ids,
		claim_menu_workshop.get_max_assigned_worker_slots(),
		selected_workshop_job.requirement_profession if selected_workshop_job != null else WorkerData.Profession.NONE
	)

func _on_workshop_worker_assignment_changed(
	worker_ids: Array[String]
) -> void:
	if claim_menu_workshop == null:
		return

	claim_menu_workshop.assign_workers(worker_ids)

func _on_workshop_worker_assignment_next_requested(worker_ids: Array[String]) -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		_show_current_interact_label()
		return

	if worker_ids.is_empty():
		_open_workshop_production_ui()
		return

	_open_workshop_job_ui(
		claim_menu_workshop.get_assigned_worker_ids()
	)

func _on_workshop_worker_assignment_back_requested() -> void:
	_open_workshop_production_ui()

func _on_workshop_worker_assignment_cancelled() -> void:
	_close_claim_menu()
	_show_current_interact_label()

# Workshop transfer flow

func _on_workshop_storage_menu_action_selected(action_id: int) -> void:
	match action_id:
		WorkshopStorageMenuUI.Action.DEPOSIT_ITEMS:
			_open_workshop_deposit_transfer()

func _on_workshop_output_lot_payment_requested(
	lot_id: String,
	menu_ui: WorkshopStorageMenuUI
) -> void:
	if claim_menu_workshop == null or not is_instance_valid(menu_ui):
		return

	var payment_result: Dictionary = claim_menu_workshop.pay_output_lot(
		self,
		lot_id
	)
	menu_ui.show_payment_result(
		bool(payment_result.get("success", false)),
		str(payment_result.get("message", "Could not pay output fee.")),
		claim_menu_workshop.get_storage_state()
	)

func _on_workshop_storage_pay_all_requested(
	menu_ui: WorkshopStorageMenuUI
) -> void:
	if claim_menu_workshop == null or not is_instance_valid(menu_ui):
		return

	var payment_success: bool = claim_menu_workshop.pay_all_held_output_fees(self)
	menu_ui.show_payment_result(
		payment_success,
		(
			""
			if payment_success
			else "Not enough currency to pay all Held Output fees."
		),
		claim_menu_workshop.get_storage_state()
	)

func _on_workshop_free_stock_withdraw_requested(
	selected_items: Dictionary,
	menu_ui: WorkshopStorageMenuUI
) -> void:
	if claim_menu_workshop == null or not is_instance_valid(menu_ui):
		return

	if selected_items.is_empty():
		menu_ui.show_payment_result(
			false,
			"Invalid withdrawal.",
			claim_menu_workshop.get_storage_state()
		)
		return

	var withdraw_success: bool = claim_menu_workshop.withdraw_selected_items_to_player(
		selected_items
	)
	menu_ui.show_payment_result(
		withdraw_success,
		(
			"Withdrew selected Free Stock to Inventory."
			if withdraw_success
			else "Could not withdraw. Check stock and Inventory capacity."
		),
		claim_menu_workshop.get_storage_state()
	)

func _open_workshop_deposit_transfer() -> void:
	if claim_menu_workshop == null:
		return

	var item_transfer_scene: PackedScene = preload("res://scenes/ui/item_transfer_ui/item_transfer_ui.tscn")
	var item_transfer_menu: ItemTransferUI = item_transfer_scene.instantiate()

	get_tree().current_scene.add_child(item_transfer_menu)

	item_transfer_menu.transfer_confirmed.connect(_on_workshop_deposit_confirmed)
	item_transfer_menu.transfer_back_requested.connect(_on_workshop_deposit_back_requested)
	item_transfer_menu.transfer_cancelled.connect(_on_workshop_deposit_cancelled)

	claim_menu_is_open = false
	item_transfer_menu.open_transfer("Deposit to Workshop", Inventory.items, "Deposit")

func _on_workshop_deposit_confirmed(selected_items: Dictionary) -> void:
	if claim_menu_workshop == null:
		return

	var workshop: WorkShop = claim_menu_workshop

	var deposit_success: bool = workshop.deposit_selected_items_from_player(selected_items)

	if not deposit_success:
		_close_claim_menu()
		_show_current_interact_label()
		return

	var index: int = 0

	for item_id in selected_items.keys():
		var qty: int = int(selected_items[item_id])
		var stack_offset: Vector2 = Vector2(0, -12 * index)

		_spawn_item_change_popup(
			item_id,
			qty,
			false,
			global_position + Vector2(0, -28) + stack_offset
		)

		_spawn_item_change_popup(
			item_id,
			qty,
			true,
			workshop.global_position + Vector2(0, -32) + stack_offset
		)

		index += 1

	_close_claim_menu()
	_show_current_interact_label()

func _on_workshop_deposit_back_requested() -> void:
	_return_to_workshop_storage_menu()

func _on_workshop_deposit_cancelled() -> void:
	_close_claim_menu()
	_show_current_interact_label()

func _on_workshop_storage_menu_closed() -> void:
	return_to_workshop_main_menu()
	_show_current_interact_label()

# Workshop job flow

func _open_workshop_job_ui(worker_ids: Array[String]) -> void:
	if selected_workshop_job == null:
		_open_workshop_production_ui()
		return

	if claim_menu_workshop == null:
		_close_claim_menu()
		_show_current_interact_label()
		return

	var workshop_job_scene: PackedScene = preload("res://scenes/ui/workshop_job_ui/workshop_job_ui.tscn")
	var workshop_job_ui: WorkshopJobUI = workshop_job_scene.instantiate()

	get_tree().current_scene.add_child(workshop_job_ui)

	workshop_job_ui.start_job_requested.connect(_on_workshop_job_start_requested.bind(workshop_job_ui))
	workshop_job_ui.back_requested.connect(_on_workshop_job_back_requested)
	workshop_job_ui.cancelled.connect(_on_workshop_job_cancelled)

	workshop_job_ui.open_job(
		claim_menu_workshop,
		worker_ids,
		selected_workshop_job
		)

func _on_workshop_job_start_requested(
	job_data: JobData,
	worker_ids: Array[String],
	work_days: int,
	workshop_job_ui: WorkshopJobUI) -> void:

	if claim_menu_workshop == null:
		workshop_job_ui.show_start_result(false, "Workshop is no longer available.")
		return

	var start_success: bool = claim_menu_workshop.start_job_from_storage(job_data, worker_ids, work_days)
	if start_success:
		workshop_job_ui.show_start_result(true, "Workshop job started.")
		return

	var message: String = "Could not start workshop job."
	if claim_menu_workshop.has_method("get_last_start_job_error"):
		message = claim_menu_workshop.get_last_start_job_error()

	workshop_job_ui.show_start_result(false, message)

func _on_workshop_job_back_requested(worker_ids: Array[String]) -> void:
	_open_workshop_worker_assignment_ui(worker_ids)

func _on_workshop_job_cancelled() -> void:
	_close_claim_menu()
	_show_current_interact_label()

# Shared workshop UI helpers

func _on_work_shop_menu_action_selected(action_id: int) -> void:
	match action_id:
		WorkshopMenuUI.Action.MANAGE_STORAGE:
			_open_workshop_storage_menu_ui()
		WorkshopMenuUI.Action.ASSIGN_WORK:
			_open_workshop_production_ui()
		WorkshopMenuUI.Action.BUILD_AND_UPGRADE:
			_open_workshop_build_ui()

func _on_workshop_menu_closed() -> void:
	_close_claim_menu()
	_show_current_interact_label()

func _show_current_interact_label() -> void:
	if current_interactable == null:
		return

	if not can_interact:
		return

	current_interactable.interactable_label_component.show()

func _spawn_item_change_popup(item_id: String, amount: int, is_positive: bool, pos: Vector2) -> void:
	var popup_scene: PackedScene = preload("res://scenes/ui/item_change_popup/item_change_popup.tscn")
	var item_popup = popup_scene.instantiate()
	get_tree().current_scene.add_child(item_popup)
	item_popup.global_position = pos
	item_popup.setup(item_id, amount, is_positive)

func return_to_workshop_main_menu() -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		_show_current_interact_label()
		return

	open_workshop_menu(claim_menu_workshop, claim_menu_claimable_index)

func _return_to_workshop_storage_menu() -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		_show_current_interact_label()
		return

	_open_workshop_storage_menu_ui()

# Pickup visual helpers

func _get_visual_direction_name() -> String:
	if player_sprite_direction == Vector2.LEFT:
		return "left"

	return "right"

func _play_pickup_action() -> void:
	can_move = false
	velocity = Vector2.ZERO

	await player_visual.play_pickup(_get_visual_direction_name())

	can_move = true

# Focus and experience

func consume_focus(amount: float) -> bool:
	if debug_disable_player_needs:
		return amount > 0.0
	if amount <= 0.0 or focus <= 0.0:
		return false

	focus = clampf(focus - amount, 0.0, 1.0)
	condition_changed.emit()
	return true

func recover_focus(amount: float) -> bool:
	if amount <= 0.0 or focus >= 1.0:
		return false

	focus = clampf(focus + amount, 0.0, 1.0)
	condition_changed.emit()
	return true

func add_experience(amount: int) -> bool:
	if amount <= 0 or current_experience >= experience_required:
		return false

	current_experience = mini(
		current_experience + amount,
		experience_required
	)

	experience_changed.emit()
	return true

func _apply_awake_focus_loss() -> void:
	var fatigue_pressure: float = clampf(
		(fatigue - 0.5) / 0.5,
		0.0,
		1.0
	)

	var hunger_pressure: float = clampf(
		(hunger - 0.5) / 0.5,
		0.0,
		1.0
	)

	var total_focus_loss: float = (
		focus_loss_per_min
		+ focus_loss_from_fatigue_per_min * fatigue_pressure
		+ focus_loss_from_hunger_per_min * hunger_pressure
	)

	consume_focus(total_focus_loss)

# Sleep flow

func get_sleep_recovery_quality() -> float:
	return clampf(
		1.0 - hunger * 0.75,
		0.25,
		1.0
	)

func sleep() -> bool:
	return sleep_for_minutes(sleep_duration_minutes)

func sleep_for_minutes(duration_minutes: int) -> bool:
	if not can_sleep() or duration_minutes <= 0:
		return false

	var recovery_quality: float = get_sleep_recovery_quality()
	var duration_ratio: float = clampf(
		float(duration_minutes) / float(sleep_duration_minutes),
		0.0,
		1.0
	)

	var previous_can_move: bool = can_move

	is_sleeping = true
	can_move = false
	velocity = Vector2.ZERO

	time_component_manager.advance_minutes(duration_minutes)
	last_sleep_day = TimeComponentManager.current_day

	var fatigue_recovery: float = (
		sleep_fatigue_recovery
		* recovery_quality
		* duration_ratio
	)

	var focus_recovery: float = (
		sleep_focus_recovery
		* recovery_quality
		* duration_ratio
	)

	fatigue = clampf(
		fatigue - fatigue_recovery,
		min_fatigue,
		max_fatigue
	)

	focus = clampf(
		focus + focus_recovery,
		0.0,
		1.0
	)

	condition_changed.emit()

	is_sleeping = false
	can_move = previous_can_move

	sleep_completed.emit(duration_minutes, recovery_quality)
	return true

func can_sleep() -> bool:
	if is_sleeping:
		return false

	return TimeComponentManager.current_day != last_sleep_day

# Condition severity

func get_fatigue_severity() -> int:
	if fatigue >= fatigue_critical_threshold:
		return ConditionSeverity.CRITICAL
	if fatigue >= fatigue_warning_threshold:
		return ConditionSeverity.WARNING
	return ConditionSeverity.NORMAL

func get_hunger_severity() -> int:
	if hunger >= hunger_critical_threshold:
		return ConditionSeverity.CRITICAL
	if hunger >= hunger_warning_threshold:
		return ConditionSeverity.WARNING
	return ConditionSeverity.NORMAL

func get_focus_severity() -> int:
	if focus <= focus_critical_threshold:
		return ConditionSeverity.CRITICAL
	if focus <= focus_warning_threshold:
		return ConditionSeverity.WARNING
	return ConditionSeverity.NORMAL

func has_critical_condition() -> bool:
	# Hunger affects collapse indirectly by accelerating Focus loss.
	return (
		get_fatigue_severity() == ConditionSeverity.CRITICAL
		or get_focus_severity() == ConditionSeverity.CRITICAL
	)

# Collapse and Nightmare flow

func _check_for_collapse() -> void:
	if debug_disable_player_needs:
		return
	if is_sleeping or is_collapsing or SceneTransition.is_transitioning:
		return

	if has_critical_condition():
		collapse()

func _reset_debug_needs() -> void:
	focus = 1.0
	fatigue = min_fatigue
	hunger = min_hunger
	condition_changed.emit()

func collapse() -> void:
	if is_collapsing:
		return

	is_collapsing = true
	var previous_can_move: bool = can_move
	can_move = false
	velocity = Vector2.ZERO
	collapse_started.emit()

	await player_visual.play_faint(
		_get_visual_direction_name()
	)

	var succeeded: bool = await SceneTransition.run_with_fade(
		Callable(self, "_enter_nightmare"),
		0.35,
		2.5,
		NIGHTMARE_ENTRY_MESSAGE
	)

	can_move = previous_can_move
	is_collapsing = false

	if not succeeded:
		last_collapse_day = TimeComponentManager.current_day
		push_warning("Player failed to enter Nightmare World.")

func apply_nightmare_consequences(total_world_minutes: int) -> void:
	is_sleeping = true
	time_component_manager.advance_minutes(total_world_minutes)

	hunger = clampf(
		hunger + collapse_hunger_cost,
		min_hunger,
		max_hunger
	)

	fatigue = clampf(
		fatigue - collapse_fatigue_recovery,
		min_fatigue,
		max_fatigue
	)

	focus = clampf(
		focus + collapse_focus_recovery,
		0.0,
		1.0
	)

	is_sleeping = false
	last_collapse_day = TimeComponentManager.current_day
	last_sleep_day = TimeComponentManager.current_day
	condition_changed.emit()
	collapse_completed.emit(total_world_minutes)

func _enter_nightmare() -> bool:
	var nightmare_world: NightmareWorld = (
		get_tree().get_first_node_in_group("nightmare_world")
		as NightmareWorld
	)

	if nightmare_world == null:
		push_warning("Nightmare World was not found.")
		return false

	var next_tier: int = total_collapse_count + 1

	if not nightmare_world.start_nightmare(self, next_tier):
		player_visual.play_visual(
			"idle",
			_get_visual_direction_name()
		)
		return false

	player_visual.play_visual(
		"idle",
		_get_visual_direction_name()
	)

	total_collapse_count = next_tier
	return true
