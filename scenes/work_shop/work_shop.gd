class_name WorkShop extends Node2D

var player_reff: Player

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent

@export var available_jobs: Array[JobData] = []
@export var available_processes: Array[ProcessData] = []
@export_range(1, 4, 1) var max_assigned_worker_slots: int = 2
@export_range(0.0, 5000.0, 10.0) var storage_capacity: float = 200.0

var assigned_worker_ids: Array[String] = []
var last_start_job_error: String = ""

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if WorkShopStorage != null:
		WorkShopStorage.max_load = storage_capacity

	player_reff = get_tree().get_first_node_in_group("player") as Player

	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))

	# INI bagian penting untuk claim gate
	interactable_component.interactable_activated.connect(_on_claim_range_entered)
	interactable_component.interactable_deactivated.connect(_on_claim_range_exited)

func _on_claim_range_entered() -> void:
	var workshop_storage: Node = get_node_or_null("/root/WorkShopStorage")
	if workshop_storage != null and workshop_storage.has_method("set_player_in_claim_area"):
		workshop_storage.call("set_player_in_claim_area", true)

func _on_claim_range_exited() -> void:
	var workshop_storage: Node = get_node_or_null("/root/WorkShopStorage")
	if workshop_storage != null and workshop_storage.has_method("set_player_in_claim_area"):
		workshop_storage.call("set_player_in_claim_area", false)

func on_player_interact(player: Player) -> void:
	if player != null and player.has_method("open_workshop_menu"):
		player.call("open_workshop_menu", self, 0)

func get_job_data(job_id: String) -> JobData:
	for job_data in available_jobs:
		if job_data == null:
			continue
		if job_data.job_id == job_id:
			return job_data
	return null

func get_process_data(process_id: String) -> ProcessData:
	for process_data in available_processes:
		if process_data == null:
			continue
		if process_data.process_id == process_id:
			return process_data

	return null

func pay_all_held_output_fees(_player: Player) -> bool:
	if WorkShopStorage == null:
		return false

	if not WorkShopStorage.has_method("settle_held_output_fees"):
		return false
	return bool(WorkShopStorage.call("settle_held_output_fees", Inventory))

func pay_output_lot(_player: Player, lot_id: String) -> Dictionary:
	if WorkShopStorage == null:
		return {
			"success": false,
			"message": "Workshop storage is unavailable."
		}

	return WorkShopStorage.pay_output_lot(lot_id, Inventory)

func get_storage_state() -> Dictionary:
	if WorkShopStorage == null:
		return {}

	var storage_state: Dictionary = WorkShopStorage.get_storage_state()
	storage_state["active_processes"] = (
		ProcessManager.get_active_progress_entries()
	)
	return storage_state

func deposit_mudbrick_recipe_materials(required_items: Dictionary[String, int]) -> bool:

	if required_items.is_empty():
		return false

	for item_id in required_items.keys():
		var qty: int = required_items[item_id]
		if not Inventory.has_item(item_id, qty):
			print("Not enough material: ", item_id)
			return false

	if not WorkShopStorage.has_capacity_for_bulk(required_items):
		print("WorkShop Storage Full.")
		return false

	for item_id in required_items.keys():
		var qty: int = required_items[item_id]
		Inventory.remove_item(item_id, qty)
		WorkShopStorage.add_item(item_id, qty)

	print("Deposited raw materials to workshop: ", WorkShopStorage.items)
	return true

func deposit_mudbrick_materials() -> bool:
	var required_materials: Dictionary[String, int] = {
		"clay_lump": 3,
		"straw_bundle": 3,
		"water_jar": 3
	}

	return deposit_mudbrick_recipe_materials(required_materials)

func withdraw_stored_item() -> void:
	pass

func deposit_item_to_workshop(item_id: String, qty: int) -> bool:
	if item_id == "" or qty <= 0:
		return false

	if not Inventory.has_item(item_id, qty):
		return false

	if not WorkShopStorage.has_capacity_for(item_id, qty):
		return false

	Inventory.remove_item(item_id, qty)
	WorkShopStorage.add_item(item_id, qty)
	return true

func deposit_available_materials_from_player() -> void:
	var accepted_material_ids := ["clay_lump" , "straw_bundle", "water_jar"]
	for item_id in accepted_material_ids:
		if Inventory.has_item(item_id, 1):
			deposit_item_to_workshop(item_id, 1)

func deposit_selected_items_from_player(selected_items: Dictionary) -> bool:
	if selected_items.is_empty():
		return false

	for item_id in selected_items.keys():
		var qty: int = int(selected_items[item_id])
		if not Inventory.has_item(item_id, qty):
			return false

	if not WorkShopStorage.has_capacity_for_bulk(selected_items):
		print("WorkShop Storage Full.")
		return false

	for item_id in selected_items.keys():
		var qty: int = int(selected_items[item_id])
		Inventory.remove_item(item_id, qty)
		WorkShopStorage.add_item(item_id, qty)

	print("Selected items: ", selected_items)
	print("Workshop remaining capacity: ", WorkShopStorage.get_remaining_capacity())
	print("Selected item weight: ", WorkShopStorage.get_bulk_item_total_weight(selected_items))
	return true

func withdraw_selected_items_to_player(selected_items: Dictionary) -> bool:
	if selected_items.is_empty():
		return false

	for item_id in selected_items.keys():
		var qty: int = int(selected_items[item_id])
		if WorkShopStorage.get_free_item_quantity(item_id) < qty:
			return false

	if (
		Inventory.get_remaining_capacity()
		< Inventory.get_bulk_item_total_weight(selected_items)
	):
		print("Inventory is Full.")
		return false

	if not WorkShopStorage.remove_free_items(selected_items):
		return false

	for item_id in selected_items.keys():
		var qty: int = int(selected_items[item_id])
		Inventory.add_item(item_id, qty)

	print("Selected items: ", selected_items)
	print("Inventory remaining capacity: ", Inventory.get_remaining_capacity())
	print("Selected item weight: ", Inventory.get_bulk_item_total_weight(selected_items))
	return true

func has_assigned_worker() -> bool:
	return not assigned_worker_ids.is_empty()

func get_assigned_worker_ids() -> Array[String]:
	return assigned_worker_ids.duplicate(true)

func get_max_assigned_worker_slots() -> int:
	return max_assigned_worker_slots

func assign_workers(worker_ids: Array[String]) -> bool:
	var next_assigned_worker_ids: Array[String] = []

	for worker_id in worker_ids:
		if next_assigned_worker_ids.size() >= max_assigned_worker_slots:
			break
		if worker_id.strip_edges().is_empty():
			continue
		if next_assigned_worker_ids.has(worker_id):
			continue
		if not WorkerDatabase.has_worker_data(worker_id):
			continue

		next_assigned_worker_ids.append(worker_id)

	if next_assigned_worker_ids.is_empty():
		for previous_worker_id in assigned_worker_ids:
			WorkerDatabase.unassign_worker(previous_worker_id)

		assigned_worker_ids.clear()
		print("Assigned workers: ", assigned_worker_ids)
		return true

	var confirmed_worker_ids: Array[String] = []
	for worker_id in next_assigned_worker_ids:
		if WorkerDatabase.assign_worker(worker_id):
			confirmed_worker_ids.append(worker_id)

	if confirmed_worker_ids.is_empty():
		print("No eligible worker assigned.")
		return false

	for previous_worker_id in assigned_worker_ids:
		if not confirmed_worker_ids.has(previous_worker_id):
			WorkerDatabase.unassign_worker(previous_worker_id)

	assigned_worker_ids = confirmed_worker_ids
	print("Assigned workers: ", assigned_worker_ids)
	return true

func get_first_available_assigned_worker_id(job: JobData = null) -> String:
	if has_assigned_worker():
		for worker_id in assigned_worker_ids:
			var worker_data: WorkerData = WorkerDatabase.get_worker_data(worker_id)
			if worker_data == null:
				continue
			if worker_data.current_work_status == WorkerData.WorkStatus.WORKING:
				continue
			if job != null and worker_data.profession != job.requirement_profession:
				continue
			return worker_data.worker_id
	return ""

func assign_test_worker() -> bool:
	for worker in WorkerDatabase.get_all_workers():
		var worker_data: WorkerData = worker as WorkerData

		if worker_data == null:
			continue

		if worker_data.current_work_status == WorkerData.WorkStatus.WORKING:
			continue

		if assigned_worker_ids.has(worker_data.worker_id):
			continue

		if assigned_worker_ids.size() >= max_assigned_worker_slots:
			print("Worker slots are full.")
			return false

		assigned_worker_ids.append(worker_data.worker_id)
		print("Assigned worker: ", worker_data.worker_id)
		return true

	print("No available worker.")
	return false

func start_mudbrick_job_from_storage() -> bool:
	var mudbrick_make: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	var worker_id: String = get_first_available_assigned_worker_id(mudbrick_make)
	if worker_id == "":
		print("Assign a matching worker first.")
		return false

	var order_id: String = WorkManager.start_job(
		mudbrick_make,
		WorkOrder.Worker_Type.NPC,
		worker_id,
		null,
		WorkShopStorage,
		WorkShopStorage,
		mudbrick_make.workshop_fee_amount,
		max_assigned_worker_slots
	)

	if order_id.is_empty():
		print(WorkManager.get_last_start_job_error())
		return false

	print("Started mudbrick job: ", order_id)
	return true

func start_job_from_storage(
	job: JobData,
	worker_ids: Array[String],
	work_days: int = 1
	) -> bool:

	if job == null:
		last_start_job_error = "No job selected."
		return false

	for item_id in job.inputs.keys():
		var required_amount: int = int(job.inputs[item_id])

		if (
			WorkShopStorage.get_free_item_quantity(str(item_id))
			< required_amount
		):
			last_start_job_error = "Not enough %s." % str(item_id)
			return false

	if not WorkShopStorage.has_capacity_after_exchange(
		job.inputs,
		job.outputs
	):
		last_start_job_error = (
			"Workshop storage does not have enough room "
			+ "for this job output."
			)
		return false

	var worker_id: String = _get_first_available_worker_for_job(worker_ids, job)
	if worker_id == "":
		last_start_job_error = "No assigned worker matches this job."
		return false

	var runtime_job: JobData = job
	if work_days > 1:
		runtime_job = job.duplicate(true)
		runtime_job.base_duration_minutes = work_days * 24 * 60

	var order_id: String = WorkManager.start_job(
		runtime_job,
		WorkOrder.Worker_Type.NPC,
		worker_id,
		null,
		WorkShopStorage,
		WorkShopStorage,
		job.workshop_fee_amount,
		max_assigned_worker_slots
	)

	if order_id.is_empty():
		last_start_job_error = WorkManager.get_last_start_job_error()
		if last_start_job_error.is_empty():
			last_start_job_error = "Could not start workshop job."
		return false

	last_start_job_error = ""
	return true

func _get_first_available_worker_for_job(worker_ids: Array[String], job: JobData) -> String:
	for worker_id in worker_ids:
		var worker_data: WorkerData = WorkerDatabase.get_worker_data(worker_id)
		if worker_data == null:
			continue
		if worker_data.is_working():
			continue
		if worker_data.profession != job.requirement_profession:
			continue

		return worker_data.worker_id

	return ""

func get_last_start_job_error() -> String:
	return last_start_job_error
