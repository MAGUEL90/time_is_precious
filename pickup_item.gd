class_name PickUpItem extends Node2D

var player_reff: Player

@export var item_id: String
@export var quantity: int = 1
@onready var icon: Sprite2D = $Icon
@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent
@onready var collision_shape_2d: CollisionShape2D = $InteractableComponent/CollisionShape2D

var is_collecting: bool = false
var collecting_tween: Tween
var shake_tween: Tween

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		push_error("PickupItem: item_id '%s' not found in ItemDatabase." % item_id)
		return
		
	if item_data.icon == null:
		push_error("ItemData does not have icon.")
	
	icon.texture = item_data.icon
	
	player_reff = get_tree().get_first_node_in_group("player") as Player
	
	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))

func on_player_interact(player: Player) -> void:
	if is_collecting:
		return
	
	if Inventory != null and Inventory.has_method("try_add_item"):
		var is_success: bool = Inventory.call("try_add_item", item_id, quantity)
		if is_success:
			is_collecting = true
			collision_shape_2d.disabled = true
			interactable_label_component.hide()
			
			collecting_tween = create_tween()
			collecting_tween.tween_property(self, "global_position", player.global_position, 0.1).set_ease(Tween.EASE_IN_OUT)
			collecting_tween.tween_property(self, "scale", Vector2.ZERO, 0.05)
			await collecting_tween.tween_interval(0.2).finished
			queue_free()
		else:
			if not Inventory.has_capacity_for(item_id, quantity):
				play_failed_pickup_shake()
				
	else:
		print("Please double check")

func on_player_enter_interaction() -> void:
	if not Inventory.has_capacity_for(item_id, quantity):
		interactable_label_component.label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.18, 1.0))
		interactable_label_component.set_text("Inventory Full")
	
	else:
		interactable_label_component.label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		interactable_label_component.set_text("press E \n to collect")

func play_failed_pickup_shake() -> void:
	var original_position: Vector2 = position
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()
		
	shake_tween = create_tween()
	shake_tween.tween_property(self, "position", original_position + Vector2(4, 0), 0.04)
	shake_tween.tween_property(self, "position", original_position + Vector2(-4, 0), 0.04)
	shake_tween.tween_property(self, "position", original_position + Vector2(2, 0), 0.03)
	shake_tween.tween_property(self, "position", original_position, 0.03)
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
