extends StorageDestination

@onready var interactable_label_component: CanvasItem = $InteractableLabelComponent
var player: Player

func _ready() -> void:
	super._ready()
	add_to_group("worksite_stockpiles")
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)

func _on_entered(body: Node2D) -> void:
	if body is Player:
		player = body
		player._on_interactable_activated(self)

func _on_exited(body: Node2D) -> void:
	if body == player:
		player._on_interactable_deactivated(self)

func on_player_interact(body: Player) -> void:
	var shape: CollisionShape2D = $CollisionShape2D
	if body != player or not overlaps_body(body) or shape.disabled:
		return
	if not shape.shape.get_rect().has_point(shape.to_local(body.global_position)):
		return
	if get_tree().paused or not body.can_move or body.is_sleeping or body.is_collapsing or SceneTransition.is_transitioning:
		return
	var storage: Node = get_storage()
	var taken: int = storage.withdraw_to_inventory()
	$Feedback.text = "Taken: %d" % taken if taken > 0 else ("Empty" if storage.quantity == 0 else "Bag full")

func _exit_tree() -> void:
	if is_instance_valid(player) and player.is_inside_tree():
		player._on_interactable_deactivated(self)
