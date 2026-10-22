extends Node
## Transaction fixture: explicit grants, no claim of normal player progression.
var failures := 0
var storage: Node
var signal_count := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	TimeComponentManager.set_process(false)
	storage = preload("res://scenes/storage_destination/city_tool_storage.gd").new()
	add_child(storage)
	Inventory.items = {"shekel": 5, "barley_bread": 2, "basic_glove": 1}
	CityStockManager.treasury_shekel = 3
	Inventory.items_changed.connect(_observe_commit)
	storage.changed.connect(_observe_commit)
	var result: Dictionary = storage.deposit_items_from_inventory({"shekel": 2, "barley_bread": 1}, true)
	check(result.ok and signal_count == 2, "Mixed deposit publishes complete balances to both listeners")
	Inventory.items_changed.disconnect(_observe_commit)
	storage.changed.disconnect(_observe_commit)
	var before := snapshot()
	check(not storage.deposit_items_from_inventory({"shekel": 4, "basic_glove": 1}, true).ok, "Insufficient wallet rejects mixed selection")
	check(snapshot() == before, "Rejected wallet transaction changes nothing")
	CityStockManager.treasury_shekel = CityStockManager.MAX_SHEKEL
	before = snapshot()
	check(not storage.deposit_items_from_inventory({"shekel": 1, "basic_glove": 1}, true).ok, "Treasury cap rejects entire selection")
	check(snapshot() == before, "Cap failure retains goods, wallet and unit sequence")
	check(storage.deposit_items_from_inventory({"barley_bread": 1}, true).ok, "Full treasury still permits goods-only deposits")
	for invalid: Dictionary in [{"shekel": 0}, {"shekel": -1}, {"shekel": 1.5}, {"shekel": 1, "gold_nugget": 1}]:
		before = snapshot()
		check(not storage.deposit_items_from_inventory(invalid, true).ok and snapshot() == before, "Invalid selection remains atomic")
	CityStockManager.treasury_shekel = 5
	check(storage.deposit_items_from_inventory({"shekel": 1}).ok, "Legacy generic receipt remains supported")
	check(storage.items.get("shekel", 0) == 1 and CityStockManager.treasury_shekel == 5, "Legacy physical coins are not silently converted")
	print("StorageTreasury fixture: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _observe_commit() -> void:
	signal_count += 1
	check(Inventory.items.get("shekel", 0) == 3 and CityStockManager.treasury_shekel == 5 and storage.items.get("barley_bread", 0) == 1 and not storage.items.has("shekel"), "Listener sees every committed balance")
	check(not storage.deposit_items_from_inventory({"shekel": 1}, true).ok, "Signal reentry cannot deposit twice")

func snapshot() -> Array:
	return [Inventory.items.duplicate(true), CityStockManager.treasury_shekel, storage.items.duplicate(true), storage.units.duplicate(true), storage._unit_sequence]

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
