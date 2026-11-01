extends Node

## Isolated functional coverage for work accounting and the replacement UI.
class PlotState extends RefCounted:
	var order_id: String = ""

class PlotFixture extends Node2D:
	var construction := PlotState.new()
	func _ready() -> void:
		add_to_group("workshop_plots")
	func begin_worker_approach(worker_id: String, task: String) -> void:
		var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
		worker.begin_physical_approach("plot", task, construction.order_id, Vector2(0, 12), Vector2.ZERO)

class CallbackStore extends Node:
	var items: Dictionary[String, int] = {}
	var on_remove: Callable
	func remove_item(id: String, quantity: int) -> bool:
		if int(items.get(id, 0)) < quantity:
			return false
		items[id] -= quantity
		if on_remove.is_valid():
			on_remove.call()
		return true
	func add_item(id: String, quantity: int) -> void:
		items[id] = int(items.get(id, 0)) + quantity

var failures: int = 0
var now_total: int = 0
var callback_observations: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _set_now(total: int, tick: bool = true) -> void:
	now_total = total
	TimeComponentManager.current_day = total / 1440
	TimeComponentManager.current_hour = (total % 1440) / 60
	TimeComponentManager.current_minute = total % 60
	if tick:
		WorkManager.on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute)

func _make_worker(id: String, profession: WorkerData.Profession) -> WorkerData:
	var person := CitizenData.new()
	person.citizen_id = id
	person.display_name = id
	person.profession = profession
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.HIRED
	person.satisfaction = 0.8
	CitizenManager.citizens_by_id[id] = person
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = id
	worker.profession = profession
	WorkerDatabase.workers_by_id[id] = worker
	return worker

func _arrive(worker: WorkerData, task: String) -> void:
	worker.physical_approach.position = worker.physical_approach.target
	_expect(worker.mark_physical_arrival(task), "The worker can physically arrive for this plot task.")

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	var start: int = 3 * 1440 + 14 * 60 + 50
	_set_now(start, false)
	WorkManager._last_total_minutes = start
	var plot_a := PlotFixture.new()
	plot_a.construction.order_id = "construction:shift_fixture_a"
	add_child(plot_a)
	var workshop: WorkShop = preload("res://scenes/workshop/workshop.tscn").instantiate()
	plot_a.add_child(workshop)
	var plot_b := PlotFixture.new()
	plot_b.construction.order_id = "construction:shift_fixture_b"
	add_child(plot_b)
	var other_workshop: WorkShop = preload("res://scenes/workshop/workshop.tscn").instantiate()
	plot_b.add_child(other_workshop)
	WorkShopStorage.max_load = 1000.0
	var job: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	var first: WorkerData = _make_worker("shift_first", job.requirement_profession)
	var replacement: WorkerData = _make_worker("shift_replacement", job.requirement_profession)
	var coworker: WorkerData = _make_worker("shift_coworker", job.requirement_profession)
	var wrong_role: WorkerData = _make_worker("shift_wrong_role", WorkerData.Profession.CRAFTER if job.requirement_profession != WorkerData.Profession.CRAFTER else WorkerData.Profession.LABORER)
	for item_id: String in job.inputs:
		WorkShopStorage.add_item(item_id, int(job.inputs[item_id]) * 4)
	_expect(workshop.assign_workers([first.worker_id] as Array[String]), "The initial worker can be assigned.")
	_expect(workshop.start_job_from_storage(job, [first.worker_id] as Array[String]), "The original shaping batch starts.")
	var shaping: WorkOrder = WorkManager.active_orders.get(first.current_order_id)
	if shaping == null:
		_finish()
		return
	_arrive(first, shaping.order_id)
	var inputs_after_start: Dictionary = WorkShopStorage.items.duplicate(true)
	var other_job: JobData = job.duplicate(true)
	other_job.job_id = "unrelated_fixture_job"
	other_job.base_duration_minutes = 120
	var other_id: String = WorkManager.start_job(other_job, WorkOrder.Worker_Type.NPC, coworker.worker_id, null, WorkShopStorage, Inventory, 0)
	_expect(not other_id.is_empty(), "An unrelated NPC job starts alongside shaping.")
	var player_job: JobData = job.duplicate(true)
	var player_id: String = WorkManager.start_job(player_job, WorkOrder.Worker_Type.PLAYER, "player", null, WorkShopStorage, Inventory, 0)
	_expect(not player_id.is_empty(), "The player can start a matching job independently.")
	var source_after_all_starts: Dictionary = WorkShopStorage.items.duplicate(true)
	_set_now(start + 10)
	_expect(shaping.end_time_total_minutes - now_total == 20, "Shaping earns exactly ten minutes through 15:00.")
	_expect(not first.physical_approach.arrived and int(first.physical_approach.arrival_minute) == -2, "The shift boundary requires the original worker to depart.")
	_set_now(start + 30)
	_expect(shaping.end_time_total_minutes - now_total == 20, "Shaping remains frozen after 15:00.")
	_expect(not WorkManager.active_orders.has(player_id), "The player's job is not subject to the NPC shift.")
	var other: WorkOrder = WorkManager.active_orders.get(other_id)
	_expect(other != null and other.end_time_total_minutes - now_total == 90, "Another NPC job continues outside the shaping shift.")
	var progress: Array[Dictionary] = WorkManager.get_active_progress_entries()
	var row: Dictionary = {}
	for entry: Dictionary in progress:
		if entry.id == shaping.order_id:
			row = entry
	_expect(row.get("status_text") == "Resting until 07:00" and row.get("active_worker_count") == 0, "Progress identifies the off-shift worker as resting.")
	CitizenManager.citizens_by_id[first.worker_id].satisfaction = 0.0
	var paused: Array[String] = WorkManager.pause_orders_for_worker(first.worker_id)
	_expect(paused == [shaping.order_id] and shaping.worker_id.is_empty() and shaping.current_status == WorkOrder.Status.QUEUED, "Resignation pauses the same unfinished batch.")
	_expect(first.current_order_id.is_empty() and first.physical_approach.is_empty(), "The departing worker's reservation and route are released.")
	workshop.assigned_worker_ids.erase(first.worker_id)
	_expect(WorkerDatabase.unassign_worker(first.worker_id) and WorkerDatabase.dismiss_worker(first.worker_id), "The now-idle worker can leave employment.")
	var paused_id: String = shaping.order_id
	var paid_fee: int = int(WorkManager.service_fee_by_order[paused_id])
	var lot_count: int = WorkShopStorage.output_lots.size()
	_set_now(4 * 1440 + 7 * 60 + 5)
	_expect(WorkManager.active_orders.has(paused_id) and shaping.end_time_total_minutes - now_total == 20, "The batch and remaining work survive an overnight jump.")
	_expect(WorkShopStorage.output_lots.size() == lot_count, "A workerless batch creates no output or fee.")
	_expect(WorkManager.source_item_store_by_order_id[paused_id] == WorkShopStorage and WorkManager.output_item_store_by_order_id[paused_id] == WorkShopStorage and int(WorkManager.service_fee_by_order[paused_id]) == paid_fee, "Pause preserves both storage bindings and the original fee.")
	_expect(not other_workshop.get_paused_orders().has(shaping) and not other_workshop.resume_paused_job(paused_id, replacement.worker_id), "A different plot cannot claim this batch.")
	_expect(not workshop.resume_paused_job(paused_id, wrong_role.worker_id), "A worker with the wrong profession cannot resume the batch.")
	var options: Array[Dictionary] = workshop.get_replacement_options(paused_id)
	var replacement_available: bool = false
	for option: Dictionary in options:
		if option.id == replacement.worker_id:
			replacement_available = bool(option.available)
	_expect(replacement_available, "A matching idle replacement is offered.")
	var production: WorkshopProductionUI = preload("res://scenes/ui/workshop_production_ui/workshop_production_ui.tscn").instantiate()
	add_child(production)
	production.open_menu(workshop)
	var paused_card: WorkOrderCard
	for card: Node in production.work_order_grid.get_children():
		if card is WorkOrderCard and str(card.get_meta("paused_order_id", "")) == paused_id:
			paused_card = card
	_expect(paused_card != null, "Production displays the paused batch as a selectable card.")
	if paused_card != null:
		paused_card.pressed.emit()
		_expect(production.next_button.text == "Assign" and not production.next_button.disabled, "The paused card opens replacement assignment.")
		production.next_button.pressed.emit()
		var selector: WorkshopWorkerAssignmentUI
		for child: Node in get_tree().current_scene.get_children():
			if child is WorkshopWorkerAssignmentUI:
				selector = child
		_expect(selector != null, "The existing worker selector opens for the paused batch.")
		if selector != null:
			selector._on_worker_selected(replacement.worker_id)
			selector.next_button.pressed.emit()
	_expect(shaping.current_status == WorkOrder.Status.RUNNING and shaping.worker_id == replacement.worker_id, "The selected replacement resumes the existing order.")
	_expect(WorkShopStorage.items == source_after_all_starts and int(WorkManager.service_fee_by_order[paused_id]) == paid_fee, "Resuming does not consume inputs or assess the fee again.")
	production._on_back_pressed()
	_set_now(now_total + 5)
	_expect(shaping.end_time_total_minutes - now_total == 20, "No production accrues while the replacement is travelling.")
	_arrive(replacement, paused_id)
	_set_now(now_total + 19)
	_expect(WorkManager.active_orders.has(paused_id) and WorkShopStorage.output_lots.size() == lot_count, "The batch does not finish before its final paid minute.")
	_set_now(now_total + 1)
	_expect(not WorkManager.active_orders.has(paused_id) and WorkShopStorage.output_lots.size() == lot_count + 1, "The replacement completes one output lot at the exact remaining minute.")
	_expect(CitizenManager.citizens_by_id[replacement.worker_id].employment_status == CitizenData.EmploymentStatus.ASSIGNED and workshop.assigned_worker_ids.has(replacement.worker_id), "Completing work preserves a live workshop selection.")
	_expect(inputs_after_start != source_after_all_starts, "Other jobs' input use was distinct from the paused batch.")
	_test_coarse_jump(job, workshop)
	_test_unlocated_legacy(job, workshop, other_workshop)
	_test_unlocated_coarse(job)
	_test_start_guards(job)
	_test_native_start_notification(job)
	_finish()

func _test_coarse_jump(job: JobData, workshop: WorkShop) -> void:
	var worker: WorkerData = _make_worker("shift_coarse_jump", job.requirement_profession)
	var start: int = 5 * 1440 + 14 * 60 + 50
	_set_now(start)
	_expect(workshop.start_job_from_storage(job, [worker.worker_id] as Array[String]), "A second shaping batch starts for a coarse clock jump.")
	var order: WorkOrder = WorkManager.active_orders.get(worker.current_order_id)
	if order == null:
		return
	_arrive(worker, order.order_id)
	_set_now(6 * 1440 + 7 * 60 + 5)
	_expect(order.end_time_total_minutes - now_total == 20 and not worker.physical_approach.arrived, "A jump across both shifts credits only the ten minutes before 15:00.")
	_expect(int(worker.physical_approach.arrival_minute) == -2, "The skipped night still requires the outbound journey before return.")

func _test_unlocated_legacy(job: JobData, first_plot: WorkShop, chosen_plot: WorkShop) -> void:
	var start: int = 7 * 1440 + 14 * 60 + 50
	_set_now(start)
	var worker: WorkerData = _make_worker("shift_unlocated_legacy", job.requirement_profession)
	worker.payroll_start_day = 7
	worker.payroll_paid_from_day = 7
	worker.payroll_paid_until_day = 7
	worker.payroll_contract_days = 3
	worker.payroll_paid_start_minute = 7 * 1440 + 8 * 60
	for item_id: String in job.inputs:
		WorkShopStorage.add_item(item_id, int(job.inputs[item_id]))
	var order_id: String = WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, worker.worker_id, null, WorkShopStorage, WorkShopStorage, job.workshop_fee_amount)
	var order: WorkOrder = WorkManager.active_orders.get(order_id)
	_expect(order != null and str(order.get_meta("visual_plot_id", "")).is_empty() and worker.physical_approach.is_empty(), "The old direct start has no invented plot or route.")
	if order == null:
		return
	_set_now(start + 10)
	_expect(order.end_time_total_minutes - now_total == 20 and worker.current_work_status == WorkerData.WorkStatus.RESTING, "The unlocated worker rests after its paid shift.")
	_set_now(8 * 1440 + 7 * 60 + 10)
	_expect(order.end_time_total_minutes - now_total == 20 and worker.is_payroll_blocked() and worker.current_work_status == WorkerData.WorkStatus.RESTING, "An expired contract prevents next-morning production.")
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	Inventory.add_item("shekel", price)
	_expect(WorkerDatabase.renew_contract(worker.worker_id, 3), "The original contract can be renewed through its normal payment path.")
	_set_now(now_total + 1)
	_expect(order.end_time_total_minutes - now_total == 19 and worker.current_work_status == WorkerData.WorkStatus.WORKING, "A renewed unlocated worker resumes the paid daytime shift without inventing a route.")
	CitizenManager.citizens_by_id[worker.worker_id].satisfaction = 0.0
	_expect(WorkManager.pause_orders_for_worker(worker.worker_id) == [order_id], "An unlocated batch pauses when its worker resigns.")
	_expect(first_plot.get_paused_orders().has(order) and chosen_plot.get_paused_orders().has(order), "The player can choose an actual workshop for an unlocated batch.")
	var replacement: WorkerData = _make_worker("shift_unlocated_replacement", job.requirement_profession)
	var inputs_before: Dictionary = WorkShopStorage.items.duplicate(true)
	_expect(chosen_plot.resume_paused_job(order_id, replacement.worker_id), "The explicitly chosen workshop adopts the unlocated order.")
	_expect(str(order.get_meta("visual_plot_id", "")) == chosen_plot.get_plot_order_id() and not replacement.physical_approach.is_empty() and WorkShopStorage.items == inputs_before, "Adoption binds the chosen entrance without consuming inputs again.")
	_expect(not first_plot.get_paused_orders().has(order), "The adopted order cannot also be selected at another plot.")

func _test_unlocated_coarse(job: JobData) -> void:
	var start: int = 9 * 1440 + 14 * 60 + 50
	_set_now(start)
	var worker: WorkerData = _make_worker("shift_unlocated_coarse", job.requirement_profession)
	for item_id: String in job.inputs:
		WorkShopStorage.add_item(item_id, int(job.inputs[item_id]))
	var lots_before: int = WorkShopStorage.output_lots.size()
	var order_id: String = WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, worker.worker_id, null, WorkShopStorage, WorkShopStorage, job.workshop_fee_amount)
	var finish: int = 10 * 1440 + 7 * 60 + 20
	_set_now(finish)
	_expect(not WorkManager.active_orders.has(order_id) and WorkShopStorage.output_lots.size() == lots_before + 1, "An unlocated legacy order counts both paid shift windows across a coarse jump.")
	if not WorkShopStorage.unpaid_claims_ledger.is_empty():
		_expect(int(WorkShopStorage.unpaid_claims_ledger.back().completed_total_minutes) == finish, "The legacy fee uses the actual last productive minute.")

func _test_start_guards(template: JobData) -> void:
	var job: JobData = template.duplicate(true)
	job.job_id = "guard_fixture_job"
	job.requirement_profession = WorkerData.Profession.SCAVENGER
	var zero: WorkerData = _make_worker("shift_zero_guard", job.requirement_profession)
	var pending: WorkerData = _make_worker("shift_pending_guard", job.requirement_profession)
	CitizenManager.citizens_by_id[zero.worker_id].satisfaction = 0.0
	pending.resignation_pending = true
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var orders_before: int = WorkManager.active_orders.size()
	_expect(WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, zero.worker_id, null, Inventory, WorkShopStorage).is_empty(), "Direct assignment rejects a zero-Satisfaction worker.")
	_expect(WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, pending.worker_id, null, Inventory, WorkShopStorage).is_empty(), "Direct assignment rejects a pending resignation.")
	_expect(WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, "missing_worker", null, Inventory, WorkShopStorage).is_empty(), "Automatic matching skips both zero and pending workers.")
	_expect(Inventory.items == inventory_before and WorkManager.active_orders.size() == orders_before, "Rejected workers consume no input and create no order.")
	var worker: WorkerData = _make_worker("shift_callback_guard", job.requirement_profession)
	var store := CallbackStore.new()
	add_child(store)
	for item_id: String in job.inputs:
		store.items[item_id] = int(job.inputs[item_id])
	var initial: Dictionary = store.items.duplicate(true)
	job.required_tool_id = "stone_hammer"
	job.tool_durability_loss = 1
	var tool := ToolInstance.new()
	tool.tool_id = "stone_hammer"
	tool.durability = 5
	add_child(tool)
	callback_observations.clear()
	store.on_remove = _during_input_removal.bind(worker, job, store)
	var result: String = WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, worker.worker_id, tool, store, WorkShopStorage)
	_expect(result.is_empty() and store.items == initial, "A resignation during removal rolls every consumed input back.")
	_expect(worker.current_order_id.is_empty() and tool.durability == 5 and WorkManager.active_orders.size() == orders_before, "An aborted start releases the worker and consumes no durability or output.")
	_expect(bool(callback_observations.get("busy", false)) and bool(callback_observations.get("nested_rejected", false)) and bool(callback_observations.get("clock_rejected", false)), "Reentrant work and elapsed-time callbacks are rejected during the transaction.")
	_expect(not WorkManager.is_transaction_busy(), "The work guard is released after rollback.")

func _during_input_removal(worker: WorkerData, job: JobData, store: CallbackStore) -> void:
	callback_observations.busy = WorkManager.is_transaction_busy()
	callback_observations.nested_rejected = WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, worker.worker_id, null, store, WorkShopStorage).is_empty()
	callback_observations.clock_rejected = not TimeComponentManager.advance_one_minute()
	CitizenManager.citizens_by_id[worker.worker_id].satisfaction = 0.0
	WorkerDatabase.resign_idle_workers_at_zero()

func _test_native_start_notification(template: JobData) -> void:
	var job: JobData = template.duplicate(true)
	job.job_id = "native_atomic_fixture"
	job.requirement_profession = WorkerData.Profession.FARMER
	var worker: WorkerData = _make_worker("shift_native_notification", job.requirement_profession)
	for item_id: String in job.inputs:
		Inventory.add_item(item_id, int(job.inputs[item_id]))
	var before: Dictionary = Inventory.items.duplicate(true)
	callback_observations.clear()
	var callback: Callable = _during_native_notification.bind(worker, job)
	Inventory.items_changed.connect(callback)
	var order_id: String = WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, worker.worker_id, null, Inventory, WorkShopStorage)
	Inventory.items_changed.disconnect(callback)
	_expect(not order_id.is_empty() and bool(callback_observations.get("fully_published", false)), "The native inventory notification sees a fully published order and fee bindings.")
	_expect(bool(callback_observations.get("busy", false)) and bool(callback_observations.get("clock_rejected", false)), "The native notification runs inside the work and clock guards.")
	for item_id: String in job.inputs:
		_expect(int(Inventory.items.get(item_id, 0)) == int(before.get(item_id, 0)) - int(job.inputs[item_id]), "The committed native input is consumed exactly once: " + item_id)
	var order: WorkOrder = WorkManager.active_orders.get(order_id)
	var remaining: int = order.end_time_total_minutes - now_total if order != null else -1
	_set_now(now_total + 1)
	_expect(order != null and order.end_time_total_minutes - now_total == remaining, "A zero-Satisfaction worker earns no work while resignation is deferred.")
	WorkerDatabase.resign_idle_workers_at_zero()
	_expect(order != null and order.current_status == WorkOrder.Status.QUEUED and order.worker_id.is_empty(), "A resignation requested by the notification pauses the committed order once the guard clears.")

func _during_native_notification(worker: WorkerData, _job: JobData) -> void:
	var id: String = worker.current_order_id
	callback_observations.busy = WorkManager.is_transaction_busy()
	callback_observations.fully_published = WorkManager.active_orders.has(id) and WorkManager.source_item_store_by_order_id.has(id) and WorkManager.output_item_store_by_order_id.has(id) and WorkManager.service_fee_by_order.has(id)
	callback_observations.clock_rejected = not TimeComponentManager.advance_one_minute()
	CitizenManager.citizens_by_id[worker.worker_id].satisfaction = 0.0
	WorkerDatabase.resign_idle_workers_at_zero()

func _finish() -> void:
	get_tree().paused = false
	print("WorkshopResignationShiftTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
