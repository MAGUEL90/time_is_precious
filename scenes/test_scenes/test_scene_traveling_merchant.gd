extends Node

const MERCHANT_STATE_SCRIPT: Script = preload("res://scenes/traveling_merchant/merchant_state.gd")
const MERCHANT_CONFIG: Resource = preload("res://resources/traveling_merchant/common_merchant.tres")
const MAX_INT: int = 9223372036854775807
const TEST_STATE_NAME: String = "TravelingMerchantRegressionFixture"

var failures: int = 0
var merchant: Variant
var _saved_inventory: Dictionary = {}
var _saved_inventory_max_load: float = 0.0
var _saved_clock: Dictionary = {}
var _saved_clock_paused: bool = false
var _saved_clock_processing: bool = false
var _trade_watch_enabled: bool = false
var _expected_inventory: Dictionary = {}
var _expected_budget: int = 0
var _expected_clay_stock: int = 0
var _inventory_signal_count: int = 0
var _merchant_signal_count: int = 0
var _reentrant_trade_result: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	Inventory.items_changed.connect(_on_inventory_items_changed)
	_test_visit_schedule_and_ledger()
	_test_atomic_trades_and_catalog_copy()
	_test_rejections_are_transactional()
	_test_last_shekel_and_last_stock()
	_test_weightless_currency()
	_test_integer_overflow_guards()
	await _restore_globals()
	print("TravelingMerchantTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _snapshot_globals() -> void:
	_saved_inventory = Inventory.items.duplicate()
	_saved_inventory_max_load = Inventory.max_load
	_saved_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
	}
	_saved_clock_paused = TimeComponentManager.is_paused
	_saved_clock_processing = TimeComponentManager.is_processing()

func _new_merchant(starting_shekel: int = 120, clay_stock: int = -1) -> Variant:
	if is_instance_valid(merchant):
		merchant.free()
	merchant = null
	_set_clock(0, 0, 0)
	var config: Resource = MERCHANT_CONFIG.duplicate(true) as Resource
	config.set("starting_shekel", starting_shekel)
	if clay_stock >= 0:
		var offers: Array = config.get("offers")
		for index: int in range(offers.size()):
			var offer: Dictionary = offers[index]
			if str(offer.get("item_id", "")) == "clay_lump":
				offer["stock"] = clay_stock
				offers[index] = offer
		config.set("offers", offers)
	var state: Variant = MERCHANT_STATE_SCRIPT.new()
	state.set("config", config)
	state.name = TEST_STATE_NAME
	WorkStateRuntime.add_child(state)
	merchant = state
	return state

func _test_visit_schedule_and_ledger() -> void:
	var state: Variant = _new_merchant()
	_set_inventory({"shekel": 1000})
	_jump_to(0, 8, 0)
	_expect(not state.is_present(), "The merchant stays away before the first scheduled day.")
	_jump_to(1, 7, 59)
	_expect(not state.is_present(), "The merchant is absent one minute before arrival.")
	_jump_to(1, 8, 0)
	_expect(state.is_present(), "The first visit starts at 08:00 on day 1.")
	_expect(state.get_budget() == 120 and _stock_for(state, "clay_lump") == 12,
		"The visit begins with its configured playtest budget and stock.")
	var first_purchase: Dictionary = state.trade("clay_lump", 1, true)
	_expect(bool(first_purchase.get("ok", false)), "The player can buy an available item during the visit.")
	_jump_to(1, 17, 59)
	_expect(state.is_present(), "The merchant remains available through 17:59.")
	_jump_to(1, 18, 0)
	_expect(not state.is_present(), "The merchant leaves at 18:00.")
	_expect(state.get_budget() == 122 and _stock_for(state, "clay_lump") == 11,
		"Leaving town preserves the remainder of the visit's budget and stock.")

	# Jump over the entire day-4 visit. It must not be synthesized on day 5.
	_jump_to(5, 9, 0)
	_expect(not state.is_present(), "Skipping the day-4 window does not create a late visit on day 5.")
	_expect(state.get_budget() == 122 and _stock_for(state, "clay_lump") == 11,
		"A skipped visit does not refill the merchant ledger.")
	_jump_to(7, 7, 59)
	_expect(not state.is_present(), "The next scheduled visit is still absent before 08:00.")
	_jump_to(7, 8, 0)
	_expect(state.is_present(), "The next scheduled visit arrives on day 7 at 08:00.")
	_expect(state.get_budget() == 120 and _stock_for(state, "clay_lump") == 12,
		"The next actual arrival resets the budget and stock once.")
	_jump_to(7, 8, 0)
	_expect(state.get_budget() == 120 and _stock_for(state, "clay_lump") == 12,
		"Repeated clock snapshots at arrival cannot grant another budget or stock refill.")
	state.trade("clay_lump", 1, true)
	_expect(state.get_budget() == 122 and _stock_for(state, "clay_lump") == 11,
		"A later visit can complete a normal purchase after its one-time reset.")

	# Debug time rewinds never restore a previously spent visit ledger.
	_jump_to(1, 8, 0)
	_expect(not state.is_present(), "Rewinding time hides the merchant instead of reopening a visit.")
	_expect(state.get_budget() == 122 and _stock_for(state, "clay_lump") == 11,
		"Rewinding time cannot refill spent budget or sold stock.")
	_jump_to(7, 8, 0)
	_expect(state.is_present(), "Returning to the already visited date restores its clock-based presence.")
	_expect(state.get_budget() == 122 and _stock_for(state, "clay_lump") == 11,
		"Returning forward to the same visit date still cannot refill its ledger.")

func _test_atomic_trades_and_catalog_copy() -> void:
	var state: Variant = _new_merchant()
	_set_inventory({"shekel": 100})
	_jump_to(1, 8, 0)
	var catalog: Array[Dictionary] = state.get_catalog()
	var clay_row: Dictionary = _row_for(catalog, "clay_lump")
	_expect(not clay_row.is_empty(), "The catalog exposes a configured clay offer.")
	if not clay_row.is_empty():
		clay_row["stock"] = 999
		_expect(_stock_for(state, "clay_lump") == 12,
			"Editing a catalog row cannot change the merchant's authoritative stock.")

	merchant.changed.connect(_on_merchant_changed)
	_inventory_signal_count = 0
	_merchant_signal_count = 0
	_expected_inventory = {"shekel": 98, "clay_lump": 1}
	_expected_budget = 122
	_expected_clay_stock = 11
	_trade_watch_enabled = true
	var buy_result: Dictionary = state.trade("clay_lump", 1, true)
	_trade_watch_enabled = false
	_expect(bool(buy_result.get("ok", false)) and int(buy_result.get("total", -1)) == 2,
		"Buying clay charges the quoted total.")
	_expect(_inventory_signal_count == 1 and _merchant_signal_count == 1,
		"One purchase emits one inventory signal and one merchant change signal.")
	_expect(not bool(_reentrant_trade_result.get("ok", true)),
		"A trade attempted reentrantly from the inventory signal is rejected.")
	_expect(Inventory.items == _expected_inventory and state.get_budget() == 122
		and _stock_for(state, "clay_lump") == 11,
		"The completed purchase conserves item and Shekel balances across both parties.")

	_expected_inventory = {"shekel": 99}
	_expected_budget = 121
	_expected_clay_stock = 12
	_trade_watch_enabled = true
	var sell_result: Dictionary = state.trade("clay_lump", 1, false)
	_trade_watch_enabled = false
	_expect(bool(sell_result.get("ok", false)) and int(sell_result.get("total", -1)) == 1,
		"Selling clay pays the configured player sale price.")
	_expect(_inventory_signal_count == 2 and _merchant_signal_count == 2,
		"One sale emits one inventory signal and one merchant change signal.")
	_expect(not bool(_reentrant_trade_result.get("ok", true)),
		"A reentrant sale signal cannot commit a second trade.")
	_expect(Inventory.items == _expected_inventory and state.get_budget() == 121
		and _stock_for(state, "clay_lump") == 12,
		"The completed sale returns the item to stock and debits the merchant's budget.")

func _test_rejections_are_transactional() -> void:
	var state: Variant = _new_merchant()
	Inventory.max_load = 100.0
	_set_inventory({"shekel": 1000})
	_jump_to(1, 8, 0)
	_assert_rejected_without_mutation(state, "clay_lump", 0, true, "Zero quantity")
	_assert_rejected_without_mutation(state, "clay_lump", -1, true, "Negative quantity")
	_assert_rejected_without_mutation(state, "missing_item", 1, true, "Unknown item")
	_assert_rejected_without_mutation(state, "clay_lump", 13, true, "Insufficient merchant stock")
	Inventory.max_load = 1.9
	_set_inventory({"shekel": 100})
	_assert_rejected_without_mutation(state, "clay_lump", 1, true, "Insufficient carry capacity")
	Inventory.max_load = 100.0
	_set_inventory({"shekel": 1})
	_assert_rejected_without_mutation(state, "clay_lump", 1, true, "Insufficient player Shekel")
	_assert_rejected_without_mutation(state, "clay_lump", 1, false, "Insufficient player inventory")

	state = _new_merchant(0)
	_set_inventory({"clay_lump": 1})
	_jump_to(1, 8, 0)
	_assert_rejected_without_mutation(state, "clay_lump", 1, false, "Insufficient merchant Shekel")

func _test_last_shekel_and_last_stock() -> void:
	var state: Variant = _new_merchant(1)
	_set_inventory({"clay_lump": 2})
	_jump_to(1, 8, 0)
	var sale: Dictionary = state.trade("clay_lump", 1, false)
	_expect(bool(sale.get("ok", false)) and state.get_budget() == 0,
		"Selling once can consume the merchant's final Shekel exactly.")
	_assert_rejected_without_mutation(state, "clay_lump", 1, false,
		"Sale after the merchant spends its last Shekel")
	_expect(state.get_budget() == 0,
		"The failed sale leaves the merchant's empty budget at zero.")

	state = _new_merchant(120, 1)
	_set_inventory({"shekel": 100})
	_jump_to(1, 8, 0)
	_expect(_stock_for(state, "clay_lump") == 1,
		"The limited-stock fixture starts with exactly one clay offer.")
	var purchase: Dictionary = state.trade("clay_lump", 1, true)
	_expect(bool(purchase.get("ok", false)) and _stock_for(state, "clay_lump") == 0,
		"Buying the final available unit leaves the merchant with zero stock.")
	_assert_rejected_without_mutation(state, "clay_lump", 1, true,
		"Purchase after the merchant sells its final stock")
	_expect(_stock_for(state, "clay_lump") == 0,
		"The failed purchase leaves the sold-out stock at zero.")

func _test_weightless_currency() -> void:
	var state: Variant = _new_merchant()
	_set_inventory({"shekel": 1000000})
	Inventory.max_load = 2.0
	_expect(Inventory.get_total_inventory_weight() == 0.0, "A large Shekel balance takes no inventory capacity.")
	_jump_to(1, 8, 0)
	var purchase: Dictionary = state.trade("clay_lump", 1, true)
	_expect(bool(purchase.get("ok", false)) and Inventory.get_total_inventory_weight() == 2.0,
		"Only the purchased clay contributes weight, filling the bag exactly.")
	_expect(Inventory.try_add_item("shekel", 10) and Inventory.get_remaining_capacity() == 0.0,
		"A full bag can receive weightless currency through the inventory API.")
	_assert_rejected_without_mutation(state, "clay_lump", 1, true, "Buying another clay into a full bag")
	var sale: Dictionary = state.trade("clay_lump", 1, false)
	_expect(bool(sale.get("ok", false)) and Inventory.get_total_inventory_weight() == 0.0,
		"Selling frees all item weight; received Shekel adds no weight.")

func _test_integer_overflow_guards() -> void:
	var state: Variant = _new_merchant()
	_set_inventory({"shekel": 1000})
	Inventory.max_load = 1.0e30
	_jump_to(1, 8, 0)
	var overflowing_quantity: int = MAX_INT / 2 + 1
	_assert_rejected_without_mutation(state, "clay_lump", overflowing_quantity, true,
		"Price multiplication overflow")

	_set_inventory({"shekel": 1000, "clay_lump": MAX_INT})
	_assert_rejected_without_mutation(state, "clay_lump", 1, true, "Player item stack overflow")

	_set_inventory({"shekel": MAX_INT, "clay_lump": 1})
	_assert_rejected_without_mutation(state, "clay_lump", 1, false, "Player Shekel overflow")

	state = _new_merchant(MAX_INT)
	_set_inventory({"shekel": 1000})
	_jump_to(1, 8, 0)
	_assert_rejected_without_mutation(state, "clay_lump", 1, true, "Merchant budget overflow")

func _assert_rejected_without_mutation(state: Variant, item_id: String, quantity: int,
		buying: bool, label: String) -> void:
	var before_inventory: Dictionary = Inventory.items.duplicate()
	var before_budget: int = state.get_budget()
	var before_catalog: Array = state.get_catalog().duplicate(true)
	var result: Dictionary = state.trade(item_id, quantity, buying)
	_expect(not bool(result.get("ok", true)), "%s is rejected." % label)
	_expect(Inventory.items == before_inventory and state.get_budget() == before_budget
		and state.get_catalog() == before_catalog,
		"%s leaves inventory, merchant budget, and stock unchanged." % label)

func _on_inventory_items_changed() -> void:
	if not _trade_watch_enabled:
		return
	_inventory_signal_count += 1
	_check_observed_trade_balances("Inventory.items_changed")
	_reentrant_trade_result = merchant.trade("straw_bundle", 1, true)

func _on_merchant_changed() -> void:
	if not _trade_watch_enabled:
		return
	_merchant_signal_count += 1
	_check_observed_trade_balances("merchant.changed")

func _check_observed_trade_balances(signal_name: String) -> void:
	_expect(Inventory.items == _expected_inventory,
		"%s observers see both player inventory changes already committed." % signal_name)
	_expect(merchant.get_budget() == _expected_budget
		and _stock_for(merchant, "clay_lump") == _expected_clay_stock,
		"%s observers see the completed merchant budget and stock." % signal_name)

func _set_inventory(stacks: Dictionary) -> void:
	Inventory.items.clear()
	for item_id: Variant in stacks:
		Inventory.items[str(item_id)] = int(stacks[item_id])

func _jump_to(day: int, hour: int, minute: int) -> void:
	_set_clock(day, hour, minute)

func _set_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.emit_time_signal()

func _stock_for(state: Variant, item_id: String) -> int:
	return int(_row_for(state.get_catalog(), item_id).get("stock", -1))

func _row_for(rows: Array, item_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.get("item_id", "")) == item_id:
			return row
	return {}

func _restore_globals() -> void:
	_trade_watch_enabled = false
	var inventory_callback: Callable = Callable(self, "_on_inventory_items_changed")
	if Inventory.items_changed.is_connected(inventory_callback):
		Inventory.items_changed.disconnect(inventory_callback)
	if is_instance_valid(merchant):
		var merchant_callback: Callable = Callable(self, "_on_merchant_changed")
		if merchant.changed.is_connected(merchant_callback):
			merchant.changed.disconnect(merchant_callback)
		merchant.free()
	merchant = null

	Inventory.items.clear()
	for item_id: Variant in _saved_inventory:
		Inventory.items[str(item_id)] = int(_saved_inventory[item_id])
	Inventory.max_load = _saved_inventory_max_load
	Inventory.items_changed.emit()

	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	TimeComponentManager.current_day = int(_saved_clock.day)
	TimeComponentManager.current_hour = int(_saved_clock.hour)
	TimeComponentManager.current_minute = int(_saved_clock.minute)
	TimeComponentManager.current_weather = str(_saved_clock.weather)
	TimeComponentManager.emit_time_signal()
	TimeComponentManager.is_paused = _saved_clock_paused
	TimeComponentManager.set_process(_saved_clock_processing)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
