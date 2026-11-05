extends "res://scenes/components/scene_door/scene_door.gd"

## A pre-layout checkpoint may restore the player onto this moved doorway.
## Let them leave that overlap before the normal entry trigger is armed again.
var _checkpoint_store: Node
var _restored_inside: WeakRef

func _ready() -> void:
	super._ready()
	body_exited.connect(_on_body_exited)
	WorkStateRuntime.child_entered_tree.connect(_on_runtime_child_entered)
	_bind_checkpoint(WorkStateRuntime.get_node_or_null("CitySave"))

func _on_runtime_child_entered(child: Node) -> void:
	if child.name == "CitySave":
		_bind_checkpoint(child)

func _bind_checkpoint(store: Node) -> void:
	if store == null or store == _checkpoint_store:
		return
	if is_instance_valid(_checkpoint_store) and _checkpoint_store.changed.is_connected(_on_checkpoint_changed):
		_checkpoint_store.changed.disconnect(_on_checkpoint_changed)
	_checkpoint_store = store
	_checkpoint_store.changed.connect(_on_checkpoint_changed)

func _on_checkpoint_changed() -> void:
	if not is_instance_valid(_checkpoint_store) or _checkpoint_store.status != "Loaded":
		return
	var city: Node = get_parent().get_parent()
	if _checkpoint_store.map != city:
		return
	var player: Player = city.get_node_or_null("YSortWorld/Player") as Player
	var door_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	var player_shape: CollisionShape2D = player.get_node_or_null("CollisionShape2D") as CollisionShape2D if player != null else null
	if player != null and door_shape != null and player_shape != null \
			and door_shape.shape != null and player_shape.shape != null \
			and not door_shape.disabled and not player_shape.disabled \
			and door_shape.shape.collide(door_shape.global_transform, player_shape.shape, player_shape.global_transform):
		_restored_inside = weakref(player)
	else:
		_restored_inside = null

func _on_body_entered(body: Node2D) -> void:
	if _restored_inside != null and _restored_inside.get_ref() == body:
		return
	super._on_body_entered(body)

func _on_body_exited(body: Node2D) -> void:
	if _restored_inside != null and _restored_inside.get_ref() == body:
		_restored_inside = null

func _exit_tree() -> void:
	if is_instance_valid(WorkStateRuntime) and WorkStateRuntime.child_entered_tree.is_connected(_on_runtime_child_entered):
		WorkStateRuntime.child_entered_tree.disconnect(_on_runtime_child_entered)
	if is_instance_valid(_checkpoint_store) and _checkpoint_store.changed.is_connected(_on_checkpoint_changed):
		_checkpoint_store.changed.disconnect(_on_checkpoint_changed)
