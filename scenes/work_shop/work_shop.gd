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

func on_player_interact(_player: Player) -> void:
	var workshop_storage: Node = get_node("/root/WorkShopStorage")
	if workshop_storage == null:
		return
	
	# DEBUG: cek apakah claim kepanggil dan hasilnya
	if workshop_storage.has_method("claim_output"):
		var claim_success: bool = bool(workshop_storage.call("claim_output", 0))
		print("Claim Success: ", claim_success)
		
