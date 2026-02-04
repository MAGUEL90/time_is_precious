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

func on_player_interact(_player: Player) -> void:
	var workshop_storage: Node = get_node("/root/WorkShopStorage")
	if workshop_storage == null:
		return
	
	# DEBUG: cek apakah claim kepanggil dan hasilnya
	if workshop_storage.has_method("claim_output"):
		var claim_success: bool = bool(workshop_storage.call("claim_output", 0))
		print("Claim Success: ", claim_success)
		print("Workshop_storage items: ", workshop_storage.get("items"))
		print("Claimable outputs count: ", workshop_storage.get("claimable_outputs").size())
		
