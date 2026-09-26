extends Node

const STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")

var storage: Node
var failures: int = 0
var signal_count: int = 0
var reentrant_probe: bool = false
var nested_result: bool = true
var original_inventory: Dictionary = {}
var original_food_supply: int = 0
var original_clothing_supply: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	original_inventory = Inventory.items.duplicate(true)
	original_food_supply = CityStockManager.food_supply
	original_clothing_supply = CityStockManager.clothing_supply
	storage = STORAGE_SCRIPT.new()
	add_child(storage)
	storage.connect("changed", Callable(self, "_on_storage_changed"))

	_test_sum_and_ready_food_gate()
	_test_small_units_first_and_physical_ownership()
	_test_remainder_is_conserved_across_calls()
	_test_rejections_are_atomic()
	_test_reentrant_consumption_is_rejected()

	_expect(Inventory.items == original_inventory, "Food consumption never mutates personal Inventory.")
	_expect(CityStockManager.food_supply == original_food_supply
		and CityStockManager.clothing_supply == original_clothing_supply,
		"Food consumption never mutates legacy CityStockManager counters.")
	storage.queue_free()
	print("CityFoodStockTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)


func _test_sum_and_ready_food_gate() -> void:
	_set_fixture({
		"barley_bread": 2,
		"roasted_drumstick": 2,
		"date_cluster": 1,
		"barley_grain_sack": 3,
		"egg": 4,
		"butchers_cut": 5,
		"clay_lump": 6,
		"basic_glove": 1,
		"simple_clothes": 2
	})
	_expect(_food_supply_points() == 7,
		"Supply sums ready whole food only: bread 2, drumstick 4, and date 1.")
	_expect(_food_portion_points() == 0, "A fresh physical stock fixture has no retained portions.")
	_expect(not bool(storage.call("consume_food_points", 8)),
		"Raw grain, egg, meat, clay, tools, and clothes cannot satisfy a food request.")
	_expect(signal_count == 0, "An insufficient request emits no City Storage signal.")

	_set_fixture({"date_cluster": 1, "barley_bread": 1})
	_expect(bool(storage.call("consume_food_points", 1)),
		"A positive request can consume one ready food point.")
	var after_tie: Dictionary = _storage_items()
	_expect(int(after_tie.get("barley_bread", 0)) == 0 and int(after_tie.get("date_cluster", 0)) == 1,
		"Equal-value ready foods use the stable item_id tie-break.")


func _test_small_units_first_and_physical_ownership() -> void:
	var units: Dictionary = {
		"hammer_unit": {"tool_id": "stone_hammer", "name": "Stone Hammer", "worker_id": "worker_a"}
	}
	_set_fixture({
		"barley_bread": 1,
		"roasted_drumstick": 2,
		"barley_grain_sack": 2,
		"clay_lump": 3,
		"simple_clothes": 1
	}, units)
	var before_units: Dictionary = _storage_units()
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_food_supply: int = CityStockManager.food_supply
	var before_clothing_supply: int = CityStockManager.clothing_supply

	_expect(bool(storage.call("consume_food_points", 1)),
		"A one-point request succeeds against the smallest ready food unit.")
	var after_items: Dictionary = _storage_items()
	_expect(int(after_items.get("barley_bread", 0)) == 0
		and int(after_items.get("roasted_drumstick", 0)) == 2,
		"Small-value bread is consumed before the higher-value drumstick.")
	_expect(_food_supply_points() == 4 and signal_count == 1,
		"Successful consumption leaves the exact remaining physical supply and emits once.")
	_expect(_storage_units() == before_units, "Unique tools and worker allocation remain unchanged.")
	_expect(Inventory.items == before_inventory
		and CityStockManager.food_supply == before_food_supply
		and CityStockManager.clothing_supply == before_clothing_supply,
		"Physical city food consumption leaves personal and legacy supply state untouched.")


func _test_remainder_is_conserved_across_calls() -> void:
	_set_fixture({"roasted_drumstick": 2})
	_expect(bool(storage.call("consume_food_points", 1)),
		"Opening one two-point food unit for one point succeeds.")
	_expect(int(_storage_items().get("roasted_drumstick", 0)) == 1
		and _storage_portions() == {"roasted_drumstick": 1}
		and _food_supply_points() == 3 and _food_portion_points() == 1,
		"Unused high-value points are retained under the source item id without double counting.")

	_expect(bool(storage.call("consume_food_points", 1)),
		"A later request consumes the retained portion before opening another whole unit.")
	_expect(int(_storage_items().get("roasted_drumstick", 0)) == 1
		and _storage_portions().is_empty() and _food_supply_points() == 2,
		"Retained points are removed first and the untouched whole unit remains available.")

	_expect(bool(storage.call("consume_food_points", 1)),
		"The final whole unit can be opened for a partial request.")
	_expect(_storage_items().is_empty() and _storage_portions() == {"roasted_drumstick": 1}
		and _food_supply_points() == 1,
		"The final unit's unused point is retained as prepared food for the next call.")
	_expect(bool(storage.call("consume_food_points", 1))
		and _storage_items().is_empty() and _storage_portions().is_empty()
		and _food_supply_points() == 0,
		"Retained prepared food can be consumed without creating hidden food.")


func _test_rejections_are_atomic() -> void:
	_set_fixture({"barley_bread": 1, "roasted_drumstick": 1})
	var before_items: Dictionary = _storage_items()
	var before_portions: Dictionary = _storage_portions()
	for amount: int in [0, -1, 4]:
		var before_signals: int = signal_count
		_expect(not bool(storage.call("consume_food_points", amount)),
			"Zero, negative, and insufficient requests are rejected.")
		_expect(_storage_items() == before_items and _storage_portions() == before_portions
			and signal_count == before_signals,
			"Rejected food requests preserve state and emit no signal.")

	_set_fixture({}, {}, {"barley_bread": 1})
	_expect(_food_supply_points() == 0 and _food_portion_points() == 0
		and not bool(storage.call("consume_food_points", 1)),
		"A corrupt full-unit portion is treated as unavailable and rejected.")
	_set_fixture({"unknown_food": 1})
	_expect(_food_supply_points() == 0 and not bool(storage.call("consume_food_points", 1)),
		"An unregistered physical item invalidates food availability and is rejected safely.")
	_set_fixture({"barley_bread": -1})
	_expect(_food_supply_points() == 0 and not bool(storage.call("consume_food_points", 1)),
		"A negative physical quantity invalidates food availability and is rejected safely.")
	_set_fixture({}, {}, {"roasted_drumstick": -1})
	_expect(_food_supply_points() == 0 and not bool(storage.call("consume_food_points", 1)),
		"A negative retained portion is rejected without mutation or notification.")
	_expect(signal_count == 0, "All invalid food-state requests emit no City Storage signal.")

	_set_fixture({"roasted_drumstick": 9223372036854775807})
	var overflow_items: Dictionary = _storage_items()
	_expect(_food_supply_points() == 0 and _food_portion_points() == 0
		and not bool(storage.call("consume_food_points", 1))
		and _storage_items() == overflow_items and signal_count == 0,
		"An int64 product overflow is unavailable and cannot mutate or emit.")
	_set_fixture({"barley_bread": 9223372036854775807, "date_cluster": 1})
	_expect(_food_supply_points() == 0 and not bool(storage.call("consume_food_points", 1))
		and signal_count == 0,
		"An int64 total overflow is unavailable instead of wrapping negative.")


func _test_reentrant_consumption_is_rejected() -> void:
	_set_fixture({"barley_bread": 1, "roasted_drumstick": 1})
	nested_result = true
	reentrant_probe = true
	_expect(bool(storage.call("consume_food_points", 1)),
		"The outer food request commits successfully.")
	reentrant_probe = false
	_expect(not nested_result and signal_count == 1,
		"A reentrant request from the changed callback is rejected while the transfer is guarded.")
	_expect(int(_storage_items().get("barley_bread", 0)) == 0
		and int(_storage_items().get("roasted_drumstick", 0)) == 1
		and _storage_portions().is_empty(),
		"Reentrant rejection leaves only the outer request's committed state.")


func _set_fixture(next_items: Dictionary, next_units: Dictionary = {}, next_portions: Dictionary = {}) -> void:
	storage.set("items", next_items.duplicate(true))
	storage.set("units", next_units.duplicate(true))
	storage.set("food_portions", next_portions.duplicate(true))
	signal_count = 0
	reentrant_probe = false
	nested_result = true


func _on_storage_changed() -> void:
	signal_count += 1
	if reentrant_probe:
		nested_result = bool(storage.call("consume_food_points", 1))


func _storage_items() -> Dictionary:
	return (storage.get("items") as Dictionary).duplicate(true)


func _storage_units() -> Dictionary:
	return (storage.get("units") as Dictionary).duplicate(true)


func _storage_portions() -> Dictionary:
	return (storage.get("food_portions") as Dictionary).duplicate(true)


func _food_supply_points() -> int:
	return int(storage.call("get_food_supply_points"))


func _food_portion_points() -> int:
	return int(storage.call("get_food_portion_points"))


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
