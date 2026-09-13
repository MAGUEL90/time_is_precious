extends Node2D

class TestStorage extends Node:
	var quantity: int = 0
	var capacity: int = 6
	func has_capacity_for(item_id: String, amount: int) -> bool:
		return item_id == "clay" and amount > 0 and quantity + amount <= capacity
	func try_add_item(item_id: String, amount: int) -> bool:
		if item_id != "clay" or amount <= 0 or quantity + amount > capacity:
			return false
		quantity += amount
		return true

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var storage := TestStorage.new()
	add_child(storage)
	var destination = preload("res://scenes/storage_destination/storage_destination.tscn").instantiate()
	add_child(destination)
	_expect(not destination.is_available(), "Unconfigured destination rejects deliveries.")
	destination.storage_path = destination.get_path_to(storage)
	var carrier := CharacterBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 2
	collision.shape = shape
	carrier.add_child(collision)
	carrier.position = Vector2(100, 0)
	add_child(carrier)
	var cargo: Dictionary = {"item_id": "clay", "quantity": 3}
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(not destination.try_deliver(carrier, cargo) and cargo.quantity == 3, "Distant carrier retains cargo.")
	carrier.global_position = destination.get_arrival_position()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(destination.try_deliver(carrier, cargo) and storage.quantity == 3 and cargo.quantity == 0, "Arrival transfers all three items.")
	_expect(not destination.try_deliver(carrier, cargo) and storage.quantity == 3, "Retry cannot duplicate delivered cargo.")
	cargo.quantity = 3
	_expect(destination.try_deliver(carrier, cargo) and storage.quantity == 6, "Repeated trip fills remaining capacity.")
	cargo.quantity = 3
	_expect(not destination.try_deliver(carrier, cargo) and cargo.quantity == 3 and storage.quantity == 6, "Full storage preserves carried cargo.")
	storage.quantity = 0
	cargo.item_id = "unknown"
	_expect(not destination.try_deliver(carrier, cargo) and cargo.quantity == 3, "Storage validates item identity.")
	cargo.item_id = "clay"
	destination.accepting_deliveries = false
	_expect(not destination.try_deliver(carrier, cargo), "Disabled destination rejects unloading.")
	destination.accepting_deliveries = true
	var other_storage := TestStorage.new()
	add_child(other_storage)
	var other = preload("res://scenes/storage_destination/storage_destination.tscn").instantiate()
	other.position = Vector2(200, 30)
	other.rotation = PI / 4.0
	add_child(other)
	other.storage_path = other.get_path_to(other_storage)
	_expect(other.accepts_cargo("clay", 3), "Destination exposes capacity preflight.")
	_expect(not other.try_deliver_at_position(Vector2.ZERO, cargo), "Clock-driven delivery still requires arrival within its own area.")
	_expect(other.try_deliver_at_position(other.get_arrival_position(), cargo) and other_storage.quantity == 3 and storage.quantity == 0, "Independent transformed destinations store in their own backend.")
	cargo.quantity = 3
	storage.free()
	_expect(not destination.try_deliver(carrier, cargo) and cargo.quantity == 3, "Missing storage preserves cargo.")
	print("StorageDestinationTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)
