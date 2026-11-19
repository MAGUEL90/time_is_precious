class_name StorageDestination
extends Area2D

## Reusable unloading endpoint. The storage owns item validation and capacity.
## Its try_add_item(item_id, quantity) must return bool and reject atomically.
signal delivery_received(item_id: String, quantity: int)
static var _active_receipts: int = 0

@export var storage_path: NodePath
@export var accepting_deliveries: bool = true
@export var display_name: String = "Storage"
@onready var arrival_point: Marker2D = $ArrivalPoint
var _receiving: bool = false

func _ready() -> void:
	add_to_group("storage_destinations")

func get_arrival_position() -> Vector2:
	return arrival_point.global_position

func get_storage() -> Node:
	return get_node_or_null(storage_path) if not storage_path.is_empty() else null

func is_available() -> bool:
	var storage: Node = get_storage()
	return accepting_deliveries and storage != null and storage.has_method("try_add_item")

func is_delivery_busy() -> bool:
	return _receiving

static func is_any_delivery_busy() -> bool:
	return _active_receipts > 0

func accepts_cargo(item_id: String, quantity: int) -> bool:
	var storage: Node = get_storage()
	return is_available() and quantity > 0 and not item_id.is_empty() and storage.has_method("has_capacity_for") and bool(storage.call("has_capacity_for", item_id, quantity))

## Clock-driven carriers use their authoritative position even during time skips,
## when physics overlap caches have not had a chance to update.
func try_deliver_at_position(world_position: Vector2, cargo: Dictionary) -> bool:
	var collision: CollisionShape2D = $CollisionShape2D
	if collision.disabled or not collision.shape is RectangleShape2D:
		return false
	var bounds := Rect2(-collision.shape.size / 2.0, collision.shape.size)
	if not bounds.has_point(collision.to_local(world_position)):
		return false
	return _receive(cargo)

## Cargo stays with the caller on failure. On success this method clears the
## transferred quantity, so retrying the same cargo cannot deliver it twice.
## Cargo contract: {"item_id": String, "quantity": int}.
func try_deliver(carrier: PhysicsBody2D, cargo: Dictionary) -> bool:
	if not is_available() or not is_instance_valid(carrier) or not overlaps_body(carrier):
		return false
	return _receive(cargo)

func _receive(cargo: Dictionary) -> bool:
	# The storage may emit a synchronous changed signal before it returns. Hold
	# both an endpoint lock and a cargo lock so a listener cannot deliver this
	# same dictionary again, including through a different endpoint.
	if _receiving or cargo.has("_delivery_in_progress") or not is_available():
		return false
	var item_id: String = str(cargo.get("item_id", ""))
	var quantity: int = int(cargo.get("quantity", 0))
	if item_id.is_empty() or quantity <= 0:
		return false
	_receiving = true
	_active_receipts += 1
	cargo["_delivery_in_progress"] = true
	if not get_storage().call("try_add_item", item_id, quantity):
		cargo.erase("_delivery_in_progress")
		_receiving = false
		_active_receipts -= 1
		return false
	cargo["quantity"] = 0
	delivery_received.emit(item_id, quantity)
	cargo.erase("_delivery_in_progress")
	_receiving = false
	_active_receipts -= 1
	return true
