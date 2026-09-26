extends Node

const STORAGE_SCRIPT = preload("res://scenes/storage_destination/city_tool_storage.gd")
const SUPPORTED_IDS: Array[String] = ["cart", "basic_glove", "stone_hammer"]
const READY_FOOD_IDS: Array[String] = [
	"barley_bread", "date_cluster", "fresh_curd_cheese", "fresh_loaf",
	"orchard_apple", "pan_fried_egg", "roasted_drumstick", "village_cheese"
]
const CLOTHING_IDS: Array[String] = [
	"simple_clothes", "clay_worn_wrap", "plain_linen_wrap", "plain_head_wrap",
	"simple_robe", "trimmed_robe", "reed_sandal"
]
const ACCEPTED_IDS: Array[String] = [
	"barley_bread", "date_cluster", "fresh_curd_cheese", "fresh_loaf", "orchard_apple",
	"pan_fried_egg", "roasted_drumstick", "village_cheese", "simple_clothes",
	"clay_worn_wrap", "plain_linen_wrap", "plain_head_wrap", "simple_robe",
	"trimmed_robe", "reed_sandal", "shekel", "cart", "basic_glove", "stone_hammer"
]
const FORBIDDEN_IDS: Array[String] = [
	"gold_nugget", "egg", "butchers_cut", "barley_grain_sack", "clay_lump", "wood_log",
	"reed_bundle", "straw_bundle", "water_jar", "copper_ore", "copper_chunk",
	"limestone_piece", "large_stone", "stone", "bronze_ingot", "wet_mudbrick",
	"sun_dried_mudbrick", "raw_wool"
]

var failures: int = 0
var storage
var original_inventory: Dictionary
var original_max_load: float

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	original_inventory = Inventory.items.duplicate(true)
	original_max_load = Inventory.max_load
	storage = STORAGE_SCRIPT.new()
	add_child(storage)
	_reset_inventory()
	_test_registered_items_and_listing()
	_test_acceptance_catalog()
	_test_invalid_requests_are_atomic()
	_test_hauler_receipt_contract()
	_test_mixed_batch_physical_stacks()
	_test_stacked_transfer_and_signal_conservation()
	_test_batch_deposit_and_no_return()
	_test_batch_atomic_validation()
	_test_existing_unsupported_stock_is_preserved()
	_test_withdraw_rejected_before_and_after_unequip()
	_test_withdraw_rejection_is_atomic()
	_test_batch_repeated_requests()
	_test_reentrant_requests_are_rejected()
	_test_existing_ownership_is_untouched()
	_test_restore_collision_path()
	_test_repeated_transfer_has_no_phantom_units()
	_restore_global_state()
	print("CityToolSupplyTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _test_registered_items_and_listing() -> void:
	for item_id: String in SUPPORTED_IDS:
		_expect(ItemDatabase.get_item_data(item_id) != null, "Supported item is registered: " + item_id)
	_reset_inventory({
		"cart": 2,
		"basic_glove": 1,
		"stone_hammer": 3,
		"barley_bread": 3,
		"simple_clothes": 1,
		"shekel": 4,
		"clay_lump": 8,
		"gold_nugget": 1
	})
	var rows: Array[Dictionary] = storage.get_depositable_items()
	_expect(
		_row_ids(rows) == ["barley_bread", "basic_glove", "cart", "shekel", "simple_clothes", "stone_hammer"],
		"Deposit listing includes only accepted items with positive Inventory stock in deterministic order."
	)
	_expect(rows[0].name == "Barley Bread" and rows[0].quantity == 3, "Food listing exposes ItemDatabase name and inventory quantity.")
	_expect(rows[1].name == "Basic Glove" and rows[1].quantity == 1, "Equipment listing exposes ItemDatabase name and inventory quantity.")
	_expect(rows[2].name == "Cart" and rows[2].quantity == 2, "Cart listing is available when registered.")
	_expect(rows[3].name == "Shekel" and rows[3].quantity == 4, "Shekel listing is available when registered.")
	_expect(rows[4].name == "Simple Clothes" and rows[4].quantity == 1, "Clothing listing is available when registered.")
	_expect(rows[5].name == "Stone Hammer" and rows[5].quantity == 3, "Hammer listing does not depend on category.")
	_expect(not _row_ids(rows).has("clay_lump") and not _row_ids(rows).has("gold_nugget"), "Raw and gold stock stays out of the player deposit listing.")
	for row: Dictionary in rows:
		_expect(row.keys().size() == 3 and row.has_all(["item_id", "name", "quantity"]), "Listing row has the exact public fields.")

func _test_acceptance_catalog() -> void:
	for item_value: Variant in ItemDatabase.get_all_items():
		var item_data := item_value as ItemData
		if item_data == null:
			continue
		var expected: bool = ACCEPTED_IDS.has(item_data.id)
		if READY_FOOD_IDS.has(item_data.id):
			expected = item_data.category == ItemEnums.ItemCategory.CONSUMABLE and item_data.food_supply_value > 0
		_expect(bool(storage.call("accepts_item", item_data.id)) == expected,
			"Acceptance catalog matches the ready-food, clothing, Shekel, and tool contract: " + item_data.id)
	_expect(not bool(storage.call("accepts_item", "unknown_item")), "Unregistered item is rejected by accepts_item.")
	_expect(not bool(storage.call("accepts_item", "")), "Empty item id is rejected by accepts_item.")
	for item_id: String in CLOTHING_IDS:
		_expect(bool(storage.call("accepts_item", item_id)), "Supported clothing remains accepted: " + item_id)
	_expect(bool(storage.call("accepts_item", "shekel")), "Shekel remains accepted as city currency.")
	for item_id: String in FORBIDDEN_IDS:
		_expect(not bool(storage.call("accepts_item", item_id)), "Raw or unsupported stock is rejected: " + item_id)

func _test_invalid_requests_are_atomic() -> void:
	_reset_inventory({"cart": 2, "clay_lump": 4})
	var invalid_requests: Array[Array] = [
		["unknown_tool", 1], ["", 1], ["cart", 0], ["cart", -1], ["cart", 3]
	]
	for request: Array in invalid_requests:
		_assert_failed_without_mutation(str(request[0]), int(request[1]), "invalid request")
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_units: Dictionary = storage.units.duplicate(true)
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_portions: Dictionary = storage.food_portions.duplicate(true)
	var before_sequence: int = storage._unit_sequence
	var inventory_signal_count: Array[int] = [0]
	var city_signal_count: Array[int] = [0]
	var on_inventory_changed := func():
		inventory_signal_count[0] += 1
	var on_city_changed := func():
		city_signal_count[0] += 1
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var invalid_type_result: Variant = storage.call("deposit_from_inventory", StringName("unknown_tool"), 1)
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(invalid_type_result is Dictionary and not bool(invalid_type_result.ok), "Invalid item identifier type returns a structured failure.")
	_expect(Inventory.items == before_inventory and storage.units == before_units and storage.items == before_items
		and storage.food_portions == before_portions and storage._unit_sequence == before_sequence,
		"Invalid item identifier type does not mutate Inventory, city storage, portions, or sequence.")
	_expect(inventory_signal_count[0] == 0 and city_signal_count[0] == 0,
		"Invalid item identifier type emits no transfer signals.")

func _test_hauler_receipt_contract() -> void:
	_reset_storage()
	_reset_inventory({"barley_bread": 4, "cart": 1, "shekel": 2})
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var inventory_signal_count: Array[int] = [0]
	var city_signal_count: Array[int] = [0]
	var nested_results: Array[bool] = []
	var on_inventory_changed := func():
		inventory_signal_count[0] += 1
	var on_city_changed := func():
		city_signal_count[0] += 1
		nested_results.append(storage.try_add_item("barley_bread", 1))
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	_expect(storage.has_capacity_for("barley_bread", 3), "Hauler receipt accepts a positive quantity of ready food.")
	_expect(storage.try_add_item("barley_bread", 3), "Hauler receipt installs the first counted food stack.")
	_expect(storage.items == {"barley_bread": 3}, "First Hauler receipt creates a counted city food stack.")
	_expect(city_signal_count[0] == 1 and inventory_signal_count[0] == 0 and Inventory.items == inventory_before,
		"Hauler receipt emits City Storage once and never changes Inventory.")
	_expect(storage.try_add_item("barley_bread", 2), "A second Hauler receipt stacks onto the existing city food stock.")
	_expect(storage.items == {"barley_bread": 5} and city_signal_count[0] == 2 and inventory_signal_count[0] == 0,
		"Repeated Hauler receipts preserve counted stock and signal exactly once per receipt.")
	_expect(nested_results == [false, false], "Reentrant Hauler receipt attempts are rejected during both City Storage callbacks.")
	storage.changed.disconnect(on_city_changed)
	Inventory.items_changed.disconnect(on_inventory_changed)
	_expect(storage.has_capacity_for("shekel", 2) and storage.try_add_item("shekel", 2),
		"Hauler receipt accepts Shekel currency.")
	_expect(storage.has_capacity_for("clay_worn_wrap", 1) and storage.try_add_item("clay_worn_wrap", 1),
		"Hauler receipt accepts legacy clothing with RESOURCE category.")
	_expect(storage.items == {"barley_bread": 5, "shekel": 2, "clay_worn_wrap": 1},
		"Hauler receipts retain ready food, currency, and legacy clothing as counted stacks.")

	_reset_storage()
	storage.food_portions = {"roasted_drumstick": 1}
	var forbidden_inventory: Dictionary = Inventory.items.duplicate(true)
	var forbidden_units: Dictionary = storage.units.duplicate(true)
	var forbidden_items: Dictionary = storage.items.duplicate(true)
	var forbidden_portions: Dictionary = storage.food_portions.duplicate(true)
	var forbidden_sequence: int = storage._unit_sequence
	var forbidden_signal_count: Array[int] = [0]
	var on_forbidden_changed := func():
		forbidden_signal_count[0] += 1
	storage.changed.connect(on_forbidden_changed)
	for item_id: String in FORBIDDEN_IDS:
		_expect(not storage.has_capacity_for(item_id, 1) and not storage.try_add_item(item_id, 1),
			"Hauler receipt rejects forbidden item: " + item_id)
	storage.changed.disconnect(on_forbidden_changed)
	_expect(Inventory.items == forbidden_inventory and storage.units == forbidden_units
		and storage.items == forbidden_items and storage.food_portions == forbidden_portions
		and storage._unit_sequence == forbidden_sequence and forbidden_signal_count[0] == 0,
		"Forbidden Hauler receipts preserve Inventory, city stacks, portions, sequence, and signals.")
	var units_before_fake: Dictionary = storage.units.duplicate(true)
	var sequence_before_fake: int = storage._unit_sequence
	_expect(not storage.add_tool_unit("fake_clay_unit", "clay_lump", "Clay Lump"),
		"A direct fake tool-unit insertion cannot bypass the accepted equipment catalog.")
	_expect(storage.units == units_before_fake and storage._unit_sequence == sequence_before_fake,
		"Rejected direct fake tool insertion leaves units and sequence unchanged.")

	_reset_storage()
	var existing_inventory: Dictionary = Inventory.items.duplicate(true)
	_expect(storage.add_tool_unit("owned_cart", "cart", "Cart"), "Existing allocated-owner fixture is installed.")
	_expect(storage.allocate("owned_cart", "worker_a"), "Existing owner fixture is allocated before receipt.")
	var existing_owner: Dictionary = storage.units.owned_cart.duplicate(true)
	storage._unit_sequence = 0
	storage.units["city_tool_cart_1"] = {"tool_id": "cart", "name": "Cart", "worker_id": "worker_b"}
	var equipment_signal_count: Array[int] = [0]
	var on_equipment_changed := func():
		equipment_signal_count[0] += 1
	storage.changed.connect(on_equipment_changed)
	_expect(storage.has_capacity_for("cart", 2), "Hauler receipt accepts a positive quantity of a registered equipment item.")
	_expect(storage.try_add_item("cart", 2), "Hauler receipt installs equipment as unique physical units.")
	storage.changed.disconnect(on_equipment_changed)
	var new_unit_ids: Array[String] = []
	for unit_id: String in storage.units:
		var unit: Dictionary = storage.units[unit_id]
		if unit_id != "owned_cart" and unit_id != "city_tool_cart_1":
			new_unit_ids.append(unit_id)
	_expect(new_unit_ids.size() == 2 and new_unit_ids[0] != new_unit_ids[1], "Equipment receipt creates distinct unit ids.")
	_expect(not new_unit_ids.has("city_tool_cart_1") and storage.units.owned_cart == existing_owner
		and storage.units.city_tool_cart_1.worker_id == "worker_b",
		"Equipment receipt preserves existing owners and skips restored unit-id collisions.")
	_expect(equipment_signal_count[0] == 1 and Inventory.items == existing_inventory,
		"Equipment receipt emits one City Storage signal and leaves Inventory untouched.")

	_reset_storage()
	var invalid_inventory: Dictionary = Inventory.items.duplicate(true)
	var invalid_items_before: Dictionary = storage.items.duplicate(true)
	var invalid_signal_count: Array[int] = [0]
	var on_invalid_changed := func():
		invalid_signal_count[0] += 1
	storage.changed.connect(on_invalid_changed)
	var invalid_requests: Array[Array] = [
		["unknown_item", 1], ["barley_bread", 0], ["barley_bread", -1], ["clay_lump", 1]
	]
	for request: Array in invalid_requests:
		_expect(not storage.has_capacity_for(str(request[0]), int(request[1]))
			and not storage.try_add_item(str(request[0]), int(request[1])),
			"Invalid Hauler receipt is rejected before mutation.")
	storage.items["barley_bread"] = -1
	_expect(not storage.has_capacity_for("barley_bread", 1) and not storage.try_add_item("barley_bread", 1),
		"Corrupt current city stack rejects Hauler receipt atomically.")
	storage.changed.disconnect(on_invalid_changed)
	_expect(storage.items == {"barley_bread": -1} and invalid_items_before.is_empty()
		and Inventory.items == invalid_inventory and invalid_signal_count[0] == 0,
		"Rejected and corrupt Hauler receipts emit no signal and preserve Inventory/state.")

func _test_mixed_batch_physical_stacks() -> void:
	_reset_storage()
	_reset_inventory({"cart": 2, "barley_bread": 3, "simple_clothes": 2, "shekel": 2})
	var original_food_supply: int = CityStockManager.food_supply
	var original_clothing_supply: int = CityStockManager.clothing_supply
	var inventory_signal_count: Array[int] = [0]
	var city_signal_count: Array[int] = [0]
	var on_inventory_changed := func():
		inventory_signal_count[0] += 1
	var on_city_changed := func():
		city_signal_count[0] += 1
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var deposited: Dictionary = storage.deposit_items_from_inventory({
		"cart": 1,
		"barley_bread": 2,
		"simple_clothes": 1,
		"shekel": 1
	})
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(deposited.has_all(["ok", "message", "unit_ids"]) and bool(deposited.ok), "Mixed equipment, food, and clothing deposit succeeds with the existing result fields.")
	_expect(deposited.unit_ids.size() == 1, "Mixed deposit returns only the physical equipment unit ids.")
	_expect(_inventory_quantity("cart") == 1 and _inventory_quantity("barley_bread") == 1
		and _inventory_quantity("simple_clothes") == 1 and _inventory_quantity("shekel") == 1,
		"Mixed deposit removes exact quantities from Inventory.")
	_expect(storage.items == {"barley_bread": 2, "simple_clothes": 1, "shekel": 1}, "Allowed non-equipment deposits are retained as counted physical stacks.")
	_expect(_available_quantity("cart") == 1 and _available_quantity("barley_bread") == 2
		and _available_quantity("simple_clothes") == 1 and _available_quantity("shekel") == 1,
		"Available items aggregates free equipment units and allowed physical stacks.")
	_expect(CityStockManager.food_supply == original_food_supply and CityStockManager.clothing_supply == original_clothing_supply, "Food and clothing deposits do not create CityStockManager supply points.")
	_expect(inventory_signal_count[0] == 1 and city_signal_count[0] == 1, "Mixed deposit emits each change signal once after all stores commit.")

	_assert_withdraw_rejected_without_mutation(
		{"cart": 1, "barley_bread": 1, "simple_clothes": 1},
		"Mixed equipment, food, and clothing withdrawal"
	)
	_expect(_inventory_quantity("cart") == 1 and _inventory_quantity("barley_bread") == 1 and _inventory_quantity("simple_clothes") == 1, "Rejected mixed withdrawal leaves Inventory unchanged.")
	_expect(storage.items == {"barley_bread": 2, "simple_clothes": 1, "shekel": 1}, "Rejected mixed withdrawal leaves counted city stacks unchanged.")
	_expect(CityStockManager.food_supply == original_food_supply and CityStockManager.clothing_supply == original_clothing_supply, "Rejected mixed withdrawal leaves CityStockManager supply points unchanged.")
	var helper_result: Dictionary = storage.deposit_from_inventory("shekel")
	_expect(bool(helper_result.ok) and helper_result.message == "Stored 1 Shekel." and helper_result.unit_ids.is_empty(), "Single-item deposit helper also stores an allowed currency stack.")
	_expect(storage.items == {"barley_bread": 2, "simple_clothes": 1, "shekel": 2}, "Single-item allowed stack deposit does not create a tool unit or alter existing city stacks.")

func _test_stacked_transfer_and_signal_conservation() -> void:
	_reset_storage()
	_reset_inventory({"stone_hammer": 3})
	var initial_total: int = _combined_item_count("stone_hammer")
	var inventory_observed_totals: Array[int] = []
	var city_signal_count: Array[int] = [0]
	var on_inventory_changed := func():
		inventory_observed_totals.append(_combined_item_count("stone_hammer"))
	var on_city_changed := func():
		city_signal_count[0] += 1
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var result: Dictionary = storage.deposit_from_inventory("stone_hammer", 3)
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(bool(result.ok) and result.unit_ids.size() == 3, "A stacked transfer succeeds for the exact quantity.")
	_expect(result.unit_ids[0] != result.unit_ids[1] and result.unit_ids[1] != result.unit_ids[2] and result.unit_ids[0] != result.unit_ids[2], "Stacked tools split into distinct physical units.")
	_expect(inventory_observed_totals == [initial_total], "Inventory observers see conserved inventory plus city total during transfer.")
	_expect(city_signal_count[0] == 1, "City Storage emits changed once per transfer.")
	_expect(_combined_item_count("stone_hammer") == initial_total, "Successful transfer conserves the combined item count.")
	for unit_id: String in result.unit_ids:
		_expect(storage.units[unit_id].tool_id == "stone_hammer" and storage.units[unit_id].worker_id.is_empty(), "Transferred tool is unallocated and keeps the existing unit schema.")

func _test_batch_deposit_and_no_return() -> void:
	_reset_storage()
	_reset_inventory({"cart": 2, "basic_glove": 1, "stone_hammer": 2})
	var initial_total: int = _combined_supported_count()
	var inventory_observed_totals: Array[int] = []
	var city_observed_totals: Array[int] = []
	var inventory_signal_count: Array[int] = [0]
	var city_signal_count: Array[int] = [0]
	var on_inventory_changed := func():
		inventory_signal_count[0] += 1
		inventory_observed_totals.append(_combined_supported_count())
	var on_city_changed := func():
		city_signal_count[0] += 1
		city_observed_totals.append(_combined_supported_count())
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var deposited: Dictionary = storage.deposit_items_from_inventory({"stone_hammer": 1, "cart": 2})
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(bool(deposited.ok) and deposited.unit_ids.size() == 3, "Batch deposit succeeds for multiple supported items.")
	_expect(_inventory_quantity("cart") == 0 and _inventory_quantity("stone_hammer") == 1 and _inventory_quantity("basic_glove") == 1, "Batch deposit removes exact quantities from Inventory.")
	_expect(_available_quantity("cart") == 2 and _available_quantity("stone_hammer") == 1, "Batch deposit creates grouped free physical units.")
	_expect(inventory_signal_count[0] == 1 and city_signal_count[0] == 1, "Batch deposit emits each change signal once.")
	_expect(inventory_observed_totals == [initial_total] and city_observed_totals == [initial_total], "Both batch deposit signals observe conserved combined stock.")

	var inventory_before_withdraw: Dictionary = Inventory.items.duplicate(true)
	var units_before_withdraw: Dictionary = storage.units.duplicate(true)
	var items_before_withdraw: Dictionary = storage.items.duplicate(true)
	_assert_withdraw_rejected_without_mutation({"cart": 1, "stone_hammer": 1}, "Batch equipment withdrawal")
	_expect(Inventory.items == inventory_before_withdraw and storage.units == units_before_withdraw and storage.items == items_before_withdraw, "Rejected batch withdrawal preserves Inventory, equipment units, and city stacks.")
	_expect(_available_quantity("cart") == 2 and _available_quantity("stone_hammer") == 1, "Rejected batch withdrawal leaves all free physical units available.")

func _test_batch_atomic_validation() -> void:
	_reset_storage()
	_reset_inventory({"cart": 2, "stone_hammer": 1, "barley_bread": 2, "clay_lump": 1})
	storage.add_tool_unit("free_cart", "cart", "Cart")
	storage.add_tool_unit("free_hammer", "stone_hammer", "Stone Hammer")
	var invalid_deposits: Array[Dictionary] = [
		{}, {"cart": 0}, {"cart": -1}, {"cart": 1.0}, {1: 1},
		{"cart": 1, "unknown_tool": 1}, {"cart": 3, "stone_hammer": 1}, {"cart": 1, "clay_lump": 1}
	]
	for selected: Dictionary in invalid_deposits:
		_assert_batch_deposit_failed(selected, "invalid batch deposit")
	for forbidden_id: String in FORBIDDEN_IDS:
		var forbidden_inventory: Dictionary = {"cart": 1}
		forbidden_inventory[forbidden_id] = 1
		_reset_inventory(forbidden_inventory)
		var mixed_selection: Dictionary = {"cart": 1}
		mixed_selection[forbidden_id] = 1
		_assert_batch_deposit_failed(mixed_selection, "mixed allowed and forbidden deposit: " + forbidden_id)
		var single_forbidden_selection: Dictionary = {}
		single_forbidden_selection[forbidden_id] = 1
		_assert_batch_deposit_failed(single_forbidden_selection, "single forbidden deposit: " + forbidden_id)
	var rejected_withdrawals: Array[Dictionary] = [
		{}, {"cart": 0}, {"cart": -1}, {"cart": 1.0}, {1: 1},
		{"cart": 1}, {"stone_hammer": 1}, {"clay_lump": 1},
		{"cart": 1, "unknown_tool": 1}, {"cart": 2, "stone_hammer": 1}
	]
	for selected: Dictionary in rejected_withdrawals:
		_assert_batch_withdraw_failed(selected, "no-return batch withdrawal")
	_expect(_available_quantity("cart") == 1 and _available_quantity("stone_hammer") == 1, "Failed mixed batch requests preserve all free stock.")
	_expect(storage.items.is_empty(), "Failed valid non-equipment requests do not create or consume stack stock.")

func _test_existing_unsupported_stock_is_preserved() -> void:
	_reset_storage()
	storage.items = {"clay_lump": 2, "raw_wool": 1}
	_reset_inventory({"clay_lump": 3, "raw_wool": 1, "barley_bread": 1})
	var bread_result: Dictionary = storage.deposit_from_inventory("barley_bread", 1)
	_expect(bool(bread_result.ok) and storage.items == {"clay_lump": 2, "raw_wool": 1, "barley_bread": 1},
		"An eligible bread deposit succeeds alongside existing unsupported city stock.")
	var available: Dictionary = storage.get_available_items()
	_expect(available.get("clay_lump", 0) == 2 and available.get("raw_wool", 0) == 1
		and available.get("barley_bread", 0) == 1,
		"Existing unsupported city stock remains available for display after an eligible receipt.")
	var rows: Array[Dictionary] = storage.get_depositable_items()
	_expect(not _row_ids(rows).has("clay_lump") and not _row_ids(rows).has("raw_wool"),
		"Existing unsupported city stock does not become depositable player stock.")

func _test_withdraw_rejected_before_and_after_unequip() -> void:
	_reset_storage()
	_reset_inventory({"stone_hammer": 1})
	storage.items = {"clay_lump": 2}
	storage.add_tool_unit("equipped_cart", "cart", "Cart")
	storage.allocate("equipped_cart", "worker_a")
	storage.add_tool_unit("free_cart", "cart", "Cart")
	storage.add_tool_unit("free_glove", "basic_glove", "Basic Glove")
	storage.add_tool_unit("free_hammer", "stone_hammer", "Stone Hammer")
	_expect(_available_quantity("cart") == 1 and storage.has_equipped("worker_a", "cart"), "Available stock excludes the equipped cart unit.")
	_assert_withdraw_rejected_without_mutation(
		{"cart": 1, "stone_hammer": 1, "clay_lump": 1},
		"Withdrawal before unequip"
	)
	_expect(storage.has_equipped("worker_a", "cart") and _available_quantity("cart") == 1, "Rejected withdrawal leaves the equipped and free cart units unchanged.")
	_expect(storage.release("equipped_cart", "worker_a"), "Equipped tool fixture can be unequipped for no-return coverage.")
	_expect(not storage.has_equipped("worker_a", "cart") and _available_quantity("cart") == 2, "Unequip releases the same physical cart back to City Storage.")
	_assert_withdraw_rejected_without_mutation(
		{"cart": 2, "stone_hammer": 1, "clay_lump": 1},
		"Withdrawal after unequip"
	)
	_expect(_available_quantity("cart") == 2 and _inventory_quantity("stone_hammer") == 1 and storage.items == {"clay_lump": 2}, "Rejected withdrawal after unequip preserves all available stock and Inventory.")

func _test_withdraw_rejection_is_atomic() -> void:
	_reset_storage()
	_reset_inventory({"cart": 1, "barley_bread": 2, "simple_clothes": 1})
	var deposited: Dictionary = storage.deposit_items_from_inventory({"cart": 1, "barley_bread": 2, "simple_clothes": 1})
	_expect(bool(deposited.ok), "Mixed fixture deposits physical stock before no-return rejection.")
	_assert_withdraw_rejected_without_mutation(
		{"cart": 1, "barley_bread": 2, "simple_clothes": 1},
		"Mixed no-return withdrawal"
	)
	_expect(_inventory_quantity("cart") == 0 and _inventory_quantity("barley_bread") == 0 and _inventory_quantity("simple_clothes") == 0, "Rejected mixed withdrawal leaves Inventory empty after deposit.")
	_expect(_available_quantity("cart") == 1 and storage.items == {"barley_bread": 2, "simple_clothes": 1}, "Rejected mixed withdrawal preserves every deposited physical item.")

func _test_batch_repeated_requests() -> void:
	_reset_storage()
	_reset_inventory({"cart": 1, "basic_glove": 1})
	var first_deposit: Dictionary = storage.deposit_items_from_inventory({"cart": 1, "basic_glove": 1})
	var stale_deposit: Dictionary = storage.deposit_items_from_inventory({"cart": 1, "basic_glove": 1})
	_expect(bool(first_deposit.ok) and not bool(stale_deposit.ok), "A stale repeated batch deposit is rejected after inventory is consumed.")
	_expect(_unit_count("cart") == 1 and _unit_count("basic_glove") == 1 and Inventory.items.is_empty(), "Repeated deposit cannot duplicate physical units.")
	_assert_withdraw_rejected_without_mutation({"cart": 1, "basic_glove": 1}, "First repeated no-return withdrawal")
	_assert_withdraw_rejected_without_mutation({"cart": 1, "basic_glove": 1}, "Repeated no-return withdrawal")
	_expect(_available_quantity("cart") == 1 and _available_quantity("basic_glove") == 1 and _inventory_quantity("cart") == 0 and _inventory_quantity("basic_glove") == 0, "Repeated no-return withdrawal cannot duplicate inventory items.")

func _test_reentrant_requests_are_rejected() -> void:
	_reset_storage()
	_reset_inventory({"cart": 2, "barley_bread": 2})
	var nested_results: Array[Dictionary] = []
	var on_inventory_changed := func():
		nested_results.append(storage.deposit_items_from_inventory({"cart": 1, "barley_bread": 1}))
	var on_city_changed := func():
		nested_results.append(storage.deposit_items_from_inventory({"cart": 1, "barley_bread": 1}))
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var result: Dictionary = storage.deposit_items_from_inventory({"cart": 2, "barley_bread": 2})
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(bool(result.ok) and nested_results.size() == 2, "Transfer notification hooks were both exercised.")
	for nested: Dictionary in nested_results:
		_expect(not bool(nested.ok) and nested.unit_ids.is_empty(), "Reentrant transfer fails without mutation.")
	_expect(Inventory.items.is_empty() and _unit_count("cart") == 2 and storage.items == {"barley_bread": 2}, "Reentrant attempts cannot create phantom transfers or stack duplication.")

func _test_existing_ownership_is_untouched() -> void:
	_reset_storage()
	_expect(storage.add_tool_unit("owned_hammer", "stone_hammer", "Stone Hammer"), "Existing tool fixture added.")
	_expect(storage.allocate("owned_hammer", "worker_a"), "Existing tool fixture allocated.")
	var existing_snapshot: Dictionary = storage.units.owned_hammer.duplicate(true)
	_reset_inventory({"stone_hammer": 2})
	var result: Dictionary = storage.deposit_from_inventory("stone_hammer", 2)
	_expect(bool(result.ok), "Transfer beside an equipped unit succeeds.")
	_expect(storage.units.owned_hammer == existing_snapshot and storage.has_equipped("worker_a", "stone_hammer"), "Existing equipped unit and worker ownership remain unchanged.")
	for unit_id: String in result.unit_ids:
		_expect(storage.units[unit_id].worker_id.is_empty(), "New units do not auto-equip onto an existing worker.")

func _test_restore_collision_path() -> void:
	_reset_storage()
	storage._unit_sequence = 0
	storage.units = {"city_tool_cart_1": {"tool_id": "cart", "name": "Cart", "worker_id": "worker_a"}}
	_reset_inventory({"cart": 1})
	var first: Dictionary = storage.deposit_from_inventory("cart", 1)
	_expect(bool(first.ok) and first.unit_ids[0] != "city_tool_cart_1", "Generated id skips a restored unit collision.")
	var restored_units: Dictionary = storage.units.duplicate(true)
	storage.units = {"city_tool_cart_1": restored_units[first.unit_ids[0]]}
	storage._unit_sequence = 0
	_reset_inventory({"cart": 1})
	var second: Dictionary = storage.deposit_from_inventory("cart", 1)
	_expect(bool(second.ok) and second.unit_ids[0] != "city_tool_cart_1", "Generated id remains collision-safe after units are replaced/restored.")
	_expect(storage.units.size() == 2 and storage.units["city_tool_cart_1"].worker_id == "", "Restored unit schema remains intact after a later transfer.")

func _test_repeated_transfer_has_no_phantom_units() -> void:
	_reset_storage()
	_reset_inventory({"basic_glove": 2})
	var first: Dictionary = storage.deposit_from_inventory("basic_glove")
	var second: Dictionary = storage.deposit_from_inventory("basic_glove")
	var before_failed_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_failed_units: Dictionary = storage.units.duplicate(true)
	var failed: Dictionary = storage.deposit_from_inventory("basic_glove")
	_expect(bool(first.ok) and bool(second.ok) and not bool(failed.ok), "Repeated available submissions transfer each available item then reject exhaustion.")
	_expect(Inventory.items == before_failed_inventory and storage.units == before_failed_units and _unit_count("basic_glove") == 2, "Unavailable repeated submission makes no phantom transfer.")

func _assert_failed_without_mutation(item_id: String, quantity: int, label: String) -> void:
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_units: Dictionary = storage.units.duplicate(true)
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_portions: Dictionary = storage.food_portions.duplicate(true)
	var before_sequence: int = storage._unit_sequence
	var inventory_signal_count: Array[int] = [0]
	var city_signal_count: Array[int] = [0]
	var on_inventory_changed := func():
		inventory_signal_count[0] += 1
	var on_city_changed := func():
		city_signal_count[0] += 1
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var result: Dictionary = storage.deposit_from_inventory(item_id, quantity)
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(not bool(result.ok) and result.unit_ids.is_empty(), label + " returns a structured failure.")
	_expect(Inventory.items == before_inventory and storage.units == before_units and storage.items == before_items
		and storage.food_portions == before_portions and storage._unit_sequence == before_sequence,
		label + " does not mutate inventory, city storage, portions, or unit sequence.")
	_expect(inventory_signal_count[0] == 0 and city_signal_count[0] == 0, label + " emits no transfer signals.")

func _assert_batch_deposit_failed(selected_items: Dictionary, label: String) -> void:
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_units: Dictionary = storage.units.duplicate(true)
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_portions: Dictionary = storage.food_portions.duplicate(true)
	var before_sequence: int = storage._unit_sequence
	var inventory_signal_count: Array[int] = [0]
	var city_signal_count: Array[int] = [0]
	var on_inventory_changed := func():
		inventory_signal_count[0] += 1
	var on_city_changed := func():
		city_signal_count[0] += 1
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var result: Dictionary = storage.deposit_items_from_inventory(selected_items)
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(not bool(result.ok) and result.unit_ids.is_empty(), label + " returns a structured failure.")
	_expect(Inventory.items == before_inventory and storage.units == before_units and storage.items == before_items
		and storage.food_portions == before_portions and storage._unit_sequence == before_sequence,
		label + " does not partially mutate Inventory, city stock, portions, or unit sequence.")
	_expect(inventory_signal_count[0] == 0 and city_signal_count[0] == 0, label + " emits no Inventory or City Storage signals.")

func _assert_batch_withdraw_failed(selected_items: Dictionary, label: String) -> void:
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_units: Dictionary = storage.units.duplicate(true)
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_sequence: int = storage._unit_sequence
	var before_food_supply: int = CityStockManager.food_supply
	var before_clothing_supply: int = CityStockManager.clothing_supply
	var inventory_signal_count: Array[int] = [0]
	var city_signal_count: Array[int] = [0]
	var on_inventory_changed := func():
		inventory_signal_count[0] += 1
	var on_city_changed := func():
		city_signal_count[0] += 1
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var result: Dictionary = storage.withdraw_items_to_inventory(selected_items)
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(not bool(result.ok) and result.unit_ids.is_empty(), label + " returns a structured failure.")
	_expect(Inventory.items == before_inventory and storage.units == before_units and storage.items == before_items and storage._unit_sequence == before_sequence, label + " does not mutate Inventory, city stock, or unit ids.")
	_expect(CityStockManager.food_supply == before_food_supply and CityStockManager.clothing_supply == before_clothing_supply, label + " does not mutate CityStockManager supply.")
	_expect(inventory_signal_count[0] == 0 and city_signal_count[0] == 0, label + " emits no Inventory or City Storage signals.")

func _assert_withdraw_rejected_without_mutation(selected_items: Dictionary, label: String) -> void:
	_assert_batch_withdraw_failed(selected_items, label)

func _combined_item_count(item_id: String) -> int:
	return int(Inventory.items.get(item_id, 0)) + _unit_count(item_id) + int(storage.items.get(item_id, 0))

func _combined_supported_count() -> int:
	var total: int = 0
	for item_id: String in SUPPORTED_IDS:
		total += _combined_item_count(item_id)
	return total

func _available_quantity(item_id: String) -> int:
	return int(storage.get_available_items().get(item_id, 0))

func _inventory_quantity(item_id: String) -> int:
	return int(Inventory.items.get(item_id, 0))

func _unit_count(item_id: String) -> int:
	var count: int = 0
	for unit: Dictionary in storage.units.values():
		if str(unit.get("tool_id", "")) == item_id:
			count += 1
	return count

func _row_ids(rows: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in rows:
		ids.append(str(row.item_id))
	return ids

func _reset_storage() -> void:
	storage.units.clear()
	storage.items.clear()
	storage.food_portions.clear()
	storage._unit_sequence = 0

func _reset_inventory(seed: Dictionary = {}) -> void:
	Inventory.items.clear()
	for item_id: String in seed:
		Inventory.add_item(item_id, int(seed[item_id]))

func _restore_global_state() -> void:
	Inventory.items = original_inventory.duplicate(true)
	Inventory.max_load = original_max_load

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
