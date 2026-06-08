class_name WorkShop extends Node2D

var player_reff: Player

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent

var job_lists: Array[String] = ["Mudbrick Making"]
var assigned_worker_ids: Array[String] = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

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
	if WorkShopStorage != null and WorkShopStorage.has_method("get_unpaid_fee_summary"):
		var unpaid_summary: Dictionary = WorkShopStorage.call("get_unpaid_fee_summary")
		print("Unpaid fee summary: ", unpaid_summary)

	# buka mode pilihan 1/2/3 di player
	if player != null and player.has_method("open_workshop_menu"):
		player.call("open_workshop_menu", self, 0)

func pay_all_unpaid_fees(_player: Player) -> bool:
	if WorkShopStorage == null:
		return false

	if not WorkShopStorage.has_method("settle_unpaid_fees"):
		return false
	return bool(WorkShopStorage.call("settle_unpaid_fees", Inventory, false))

func pay_overdue_fees(_player: Player) -> bool:
	if WorkShopStorage == null:
		return false

	if not WorkShopStorage.has_method("settle_unpaid_fees"):
		return false

	return bool(WorkShopStorage.call("settle_unpaid_fees", Inventory, true))

func claim_with_action(
	_player: Player,
	claimable_index: int,
	claim_action: int,
	will_pay_fee: bool = true) -> bool:

	if WorkShopStorage == null:
		return false

	if claim_action == WorkShopStorage.ClaimAction.TAKE_TO_PLAYER:
		var claimables: Array = WorkShopStorage.get("claimable_outputs") if WorkShopStorage != null else []
		if claimables.is_empty():
			print("No Claimable output.")
			return false

	var player_inventory: Node = Inventory if claim_action == WorkShopStorage.ClaimAction.TAKE_TO_PLAYER else null
	var claim_success: bool = bool(
		WorkShopStorage.call(
			"claim_output_with_action",
			claimable_index,
			claim_action,
			player_inventory,
			will_pay_fee))
	print("Claim Success: ", claim_success)
	return claim_success

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
		if not WorkShopStorage.has_item(item_id, qty):
			return false

		if not Inventory.has_capacity_for(item_id, qty):
			print("Inventory is Full.")
			return false

	for item_id in selected_items.keys():
		var qty: int = int(selected_items[item_id])
		WorkShopStorage.remove_item(item_id, qty)
		Inventory.add_item(item_id, qty)

	print("Selected items: ", selected_items)
	print("Inventory remaining capacity: ", Inventory.get_remaining_capacity())
	print("Selected item weight: ", Inventory.get_bulk_item_total_weight(selected_items))
	return true

func has_assigned_worker() -> bool:
	return not assigned_worker_ids.is_empty()

func get_first_available_assigned_worker_id() -> String:
	if has_assigned_worker():
		for worker_id in assigned_worker_ids:
			var worker_data: WorkerData = WorkerDatabase.get_worker_data(worker_id)
			if worker_data and worker_data.current_work_status != WorkerData.WorkStatus.WORKING:
				return worker_data.worker_id
	return ""

func assign_test_worker() -> bool:
	for worker in WorkerDatabase.get_all_workers():
		var worker_data: WorkerData = worker as WorkerData

		if worker_data == null:
			continue

		if worker_data.current_work_status == WorkerData.WorkStatus.WORKING:
			continue

		assigned_worker_ids.append(worker_data.worker_id)
		print("Assigned worker: ", worker_data.worker_id)
		return true

	print("No available worker.")
	return false

func start_mudbrick_job_from_storage() -> bool:
	var worker_id: String = get_first_available_assigned_worker_id()
	if worker_id == "":
		print("Assign a worker first.")
		return false

	var mudbrick_make: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	var order_id: String = WorkManager.start_job(
		mudbrick_make,
		WorkOrder.Worker_Type.NPC,
		worker_id,
		null,
		WorkShopStorage,
		WorkShopStorage,
		5
	)

	if order_id.is_empty():
		print(WorkManager.get_last_start_job_error())
		return false

	print("Started mudbrick job: ", order_id)
	return true
