class_name PickUpItem extends Node2D

var player_reff: Player

@export var item_id: String = "stone"
@export var quantity: int = 1
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
	if Inventory != null and Inventory.has_method("try_add_item"):
		var is_success: bool = Inventory.call("try_add_item", item_id, quantity)
		print(Inventory.items)
		if is_success:
			Inventory.call("try_add_item", item_id, quantity)
			queue_free()
		else:
			print("Inventory FULL")
