extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Two-process checkpoint coverage for a level-3 kit weighing 108 with the
## normal 100-weight bag. The items and initial level are explicit test setup.
const SAVE_PATH: String = "user://facility_contribution_continue/checkpoint.json"
const FACILITY: String = "drying_yard"
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
var store: Node
var continued: bool = false

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--facility-phase="):
			phase = argument.trim_prefix("--facility-phase=")
	_expect(phase in ["write", "read"], "Choose --facility-phase=write or read.")
	if stopped:
		return
	_expect(FileAccess.file_exists(SAVE_PATH) == (phase == "read"), "Use an isolated profile in write/read order.")
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SAVE_PATH) if phase == "read" else PackedByteArray()
	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(func(from_save: bool):
		continued = from_save
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.continue_button if phase == "read" else menu.new_game_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched and continued == (phase == "read"), "The real Start Menu opens the requested session.")
	if stopped:
		return
	bind_map()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	store = WorkStateRuntime.get_node("CitySave")
	if phase == "write":
		_write_flow()
	else:
		_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == original_bytes, "Continue leaves checkpoint bytes untouched.")
		_read_flow()
	if stopped:
		return
	print("FacilityContributionContinueTest ", phase, ": PASS")
	get_tree().quit(0)

func _write_flow() -> void:
	_expect(is_equal_approx(Inventory.max_load, 100.0), "Start with the normal Inventory capacity.")
	_expect(WorkshopFacilityManager.set_facility_level(FACILITY, 2), "The fixture starts at an existing level-two facility.")
	_expect(Inventory.try_add_item("wood_log", 6) and Inventory.try_add_item("reed_bundle", 10) and Inventory.try_add_item("sun_dried_mudbrick", 17), "Carry a 96-weight partial kit using normal capacity checks.")
	_expect(is_equal_approx(Inventory.get_total_inventory_weight(), 96.0) and not Inventory.try_add_item("sun_dried_mudbrick", 2), "The normal bag cannot hold the full 108-weight kit.")
	Inventory.add_item("shekel", 10) # Weightless fixture funds for reentrancy probes.
	var before_city: Dictionary = WorkStateRuntime.get_node("CityToolStorage").items.duplicate(true)
	var before_treasury: int = CityStockManager.treasury_shekel
	var observation: Dictionary = {"calls": 0, "conserved": true, "reentered": false, "save_blocked": false}
	var on_items := func():
		observation.calls += 1
		var entry: Dictionary = WorkshopFacilityManager.facility_contributions.get(FACILITY, {})
		var items: Dictionary = entry.get("items", {})
		for id: String in ["wood_log", "reed_bundle", "sun_dried_mudbrick"]:
			var expected: int = {"wood_log": 6, "reed_bundle": 10, "sun_dried_mudbrick": 17}[id]
			observation.conserved = bool(observation.conserved) and int(Inventory.items.get(id, 0)) + int(items.get(id, 0)) == expected
		observation.reentered = bool(observation.reentered) or bool(WorkshopFacilityManager.refund_facility_contributions(FACILITY).get("success", false)) or TimeComponentManager.advance_minutes(1)
		observation.reentered = bool(observation.reentered) or CityStockManager.deposit_wallet_shekel(1)
		observation.reentered = bool(observation.reentered) or bool(WorkStateRuntime.get_node("CityToolStorage").deposit_items_from_inventory({"shekel": 1}, true).get("ok", false))
		observation.reentered = bool(observation.reentered) or WorkerDatabase.hire_applicant("initial_workshop_laborer", 1) != null
		observation.save_blocked = store.snapshot.busy_reason(content) == "Wait for the current transaction."
	Inventory.items_changed.connect(on_items)
	var result: Dictionary = WorkshopFacilityManager.contribute_facility_materials(FACILITY)
	Inventory.items_changed.disconnect(on_items)
	_expect(bool(result.get("success", false)) and Inventory.items == {"shekel": 10} and int(observation.calls) == 1 and bool(observation.conserved) and not bool(observation.reentered) and bool(observation.save_blocked), "The first contribution commits once, conserves stock, and blocks reentrant time/save/refund/deposit/hire.")
	_expect(WorkStateRuntime.get_node("CityToolStorage").items == before_city and CityStockManager.treasury_shekel == before_treasury and WorkshopFacilityManager.get_facility_level(FACILITY) == 2, "Contributing does not use city stock or grant the upgrade.")
	_expect(Inventory.remove_item("shekel", 10), "Remove the explicit reentrancy-probe funds before saving.")
	_expect(store.save_checkpoint(), "Save the partially funded upgrade: " + store.last_error)
	_test_invalid_escrow()

func _test_invalid_escrow() -> void:
	var before: Dictionary = store.snapshot.capture(content)
	var codec = VALUES.new()
	for invalid_case: String in ["wrong_target", "extra_item", "too_many", "zero", "extra_field"]:
		var raw: Dictionary = codec.decode(before.state)
		var entry: Dictionary = raw.facilities.facility_contributions[FACILITY]
		match invalid_case:
			"wrong_target": entry.target_level = 2
			"extra_item": entry.items["water_jar"] = 1
			"too_many": entry.items["wood_log"] = 7
			"zero": entry.items["wood_log"] = 0
			"extra_field": entry["forged"] = true
		var malformed: Dictionary = before.duplicate(true)
		malformed.state = codec.encode(raw)
		_expect(not store.snapshot.prepare(malformed, content), "Reject malformed facility escrow: " + invalid_case)
		_expect(store.snapshot.capture(content) == before, "Rejected escrow has no live-world side effects: " + invalid_case)

func _read_flow() -> void:
	var entry: Dictionary = WorkshopFacilityManager.facility_contributions.get(FACILITY, {})
	_expect(WorkshopFacilityManager.get_facility_level(FACILITY) == 2 and entry.get("items", {}) == {"wood_log": 6, "reed_bundle": 10, "sun_dried_mudbrick": 17} and Inventory.items.is_empty(), "Continue restores the exact partial contribution and unbuilt level.")
	_expect(Inventory.try_add_item("clay_lump", 50), "Fill the bag to exercise refused refund.")
	var full_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_escrow: Dictionary = entry.duplicate(true)
	var refused: Dictionary = WorkshopFacilityManager.refund_facility_contributions(FACILITY)
	_expect(not bool(refused.get("success", false)) and Inventory.items == full_inventory and WorkshopFacilityManager.facility_contributions.get(FACILITY) == before_escrow, "A full Inventory refuses refund without losing or duplicating escrow.")
	_expect(Inventory.remove_item("clay_lump", 50) and Inventory.try_add_item("sun_dried_mudbrick", 3), "Make a second trip with the remaining three bricks.")
	_expect(bool(WorkshopFacilityManager.contribute_facility_materials(FACILITY).get("success", false)) and Inventory.items.is_empty(), "The complete 108-weight kit can be contributed in two trips.")
	var requirements: Dictionary = WorkshopFacilityManager.get_facility_upgrade_requirements(FACILITY, 3)
	_expect(bool(WorkshopFacilityManager.refund_facility_contributions(FACILITY).get("success", false)), "An empty 100-weight bag can reclaim a first portion of the 108-weight escrow.")
	var first_return: Dictionary = Inventory.items.duplicate(true)
	var remaining: Dictionary = WorkshopFacilityManager.facility_contributions.get(FACILITY, {}).get("items", {}).duplicate(true)
	_expect(not first_return.is_empty() and not remaining.is_empty() and Inventory.get_total_inventory_weight() <= Inventory.max_load, "The first refund leaves the uncarried remainder safely committed.")
	for id: String in requirements:
		_expect(int(first_return.get(id, 0)) + int(remaining.get(id, 0)) == int(requirements[id]), "Partial refund conserves each material: " + id)
	_expect(store.save_checkpoint() and store.load_checkpoint(), "A partial refund and its remaining escrow survive save/Continue: " + store.last_error)
	_expect(Inventory.items == first_return and WorkshopFacilityManager.facility_contributions.get(FACILITY, {}).get("items", {}) == remaining, "Continue preserves both owners after partial refund.")
	for id: String in first_return:
		_expect(Inventory.remove_item(id, int(first_return[id])), "Unload the first refunded trip into the isolated test fixture: " + id)
	_expect(bool(WorkshopFacilityManager.refund_facility_contributions(FACILITY).get("success", false)) and WorkshopFacilityManager.facility_contributions.is_empty(), "A second refund trip reclaims the complete remaining escrow.")
	var second_return: Dictionary = Inventory.items.duplicate(true)
	for id: String in requirements:
		_expect(int(first_return.get(id, 0)) + int(second_return.get(id, 0)) == int(requirements[id]), "Both refund trips together return the full original cost: " + id)
	_expect(bool(WorkshopFacilityManager.contribute_facility_materials(FACILITY).get("success", false)) and Inventory.try_add_bulk_items(first_return), "The same personal materials can be assembled again in two trips.")
	var preview: Dictionary = WorkshopFacilityManager.get_facility_upgrade_preview(FACILITY)
	_expect(bool(preview.get("can_upgrade", false)), "The contributed and carried materials together satisfy the original full requirement.")
	var upgraded: Dictionary = WorkshopFacilityManager.upgrade_facility(FACILITY)
	_expect(bool(upgraded.get("success", false)) and WorkshopFacilityManager.get_facility_level(FACILITY) == 3 and WorkshopFacilityManager.facility_contributions.is_empty() and Inventory.items.is_empty(), "The full 108-weight kit builds once from two personal trips.")
	_expect(store.save_checkpoint(), "Save the completed level-three facility: " + store.last_error)
	var completed: Dictionary = store.snapshot.capture(content)
	_expect(store.load_checkpoint() and store.snapshot.capture(content) == completed, "Repeated Continue preserves the completed level without another charge.")
