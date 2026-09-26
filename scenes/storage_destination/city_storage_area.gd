extends Area2D

## Physical access to the shared city stock. Worker Hub only manages allocation.
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent
@onready var access_shape: CollisionShape2D = $CollisionShape2D
@onready var delivery_point: StorageDestination = $DeliveryPoint

var player: Player
var storage: Node
var can_open: Callable
var menu: CanvasLayer
var _previous_can_move: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("city_storage_areas")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func configure(next_player: Player, next_storage: Node, open_gate: Callable) -> void:
	player = next_player
	storage = next_storage
	can_open = open_gate
	delivery_point.storage_path = NodePath("")
	if is_instance_valid(next_storage) and is_inside_tree() and next_storage.is_inside_tree():
		delivery_point.storage_path = delivery_point.get_path_to(next_storage)

func _on_body_entered(body: Node2D) -> void:
	if body == player:
		player._on_interactable_activated(self)

func _on_body_exited(body: Node2D) -> void:
	if body == player:
		close_menu()
		player._on_interactable_deactivated(self)

func has_player_access() -> bool:
	if not is_inside_tree() or not is_instance_valid(player) or not is_instance_valid(storage):
		return false
	if not player.is_inside_tree() or player.is_collapsing or player.is_sleeping or SceneTransition.is_transitioning:
		return false
	if access_shape.disabled or not overlaps_body(player):
		return false
	# Also check live position: physics overlap lists can be stale while the tree is paused.
	return access_shape.shape.get_rect().has_point(access_shape.to_local(player.global_position))

func on_player_interact(interacting_player: Player) -> void:
	if interacting_player != player or is_instance_valid(menu) or not has_player_access():
		return
	if not can_open.is_valid() or not bool(can_open.call()):
		return
	_previous_can_move = player.can_move
	player.can_move = false
	player.velocity = Vector2.ZERO
	interactable_label_component.hide()
	menu = preload("res://scenes/storage_destination/city_storage_access_ui.tscn").instantiate()
	add_child(menu)
	menu.closed.connect(_on_menu_closed.bind(menu))
	menu.open(storage, has_player_access)
	get_viewport().set_input_as_handled()

func close_menu() -> void:
	if is_instance_valid(menu):
		menu.close()

func _on_menu_closed(source: CanvasLayer) -> void:
	if menu != source:
		return
	menu = null
	if is_instance_valid(player):
		player.can_move = _previous_can_move and not player.is_collapsing and not player.is_sleeping and not SceneTransition.is_transitioning
		if has_player_access() and player.current_interactable == self:
			interactable_label_component.show()

func _exit_tree() -> void:
	close_menu()
	if is_instance_valid(player) and player.is_inside_tree():
		player._on_interactable_deactivated(self)
