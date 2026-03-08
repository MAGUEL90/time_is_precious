class_name WorkShop extends Node2D

var player_reff: Player

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent


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
	if player != null and player.has_method("open_workshop_claim_menu"):
		player.call("open_workshop_claim_menu", self, 0)

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
	
	if claim_action == 0:
		var claimables: Array = WorkShopStorage.get("claimable_outputs") if WorkShopStorage != null else []
		if claimables.is_empty() and WorkShopStorage.has_method("transfer_all_items_to_player"):
			var transfer_success: bool = bool(WorkShopStorage.call("transfer_all_items_to_player", Inventory))
			print("Transfer workshop items to player inventory: ", transfer_success)
			return transfer_success
	
	if not WorkShopStorage.has_method("claim_output_with_action"):
		return false
	
	var player_inventory: Node = Inventory if claim_action == 0 else null
	var claim_success: bool = bool(
		WorkShopStorage.call(
			"claim_output_with_action", 
			claimable_index, 
			claim_action, 
			player_inventory,
			will_pay_fee))
	print("Claim Success: ", claim_success)
	print(player_inventory.items)
	return claim_success
