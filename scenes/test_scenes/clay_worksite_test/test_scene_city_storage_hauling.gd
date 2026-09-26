extends Node

const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const HAULING_SCRIPT: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd")
const SITE: StringName = &"ClaySiteA"
const LABORER: String = "city_storage_filter_test_laborer"
const HAULER: String = "city_storage_filter_test_hauler"
const BARLEY_BREAD: String = "barley_bread"
const CLAY: String = "clay_lump"
const RAW_ITEMS: Array[String] = [
	CLAY, "wood_log", "barley_grain_sack", "butchers_cut", "egg", "gold_nugget"
]
const ACCEPTED_ITEMS: Array[String] = [
	BARLEY_BREAD, "simple_clothes", "clay_worn_wrap", "plain_linen_wrap",
	"plain_head_wrap", "simple_robe", "trimmed_robe", "reed_sandal", "shekel",
	"cart", "basic_glove", "stone_hammer"
]
const BREAD_SOURCE_CAPACITY: int = 5

var failures: int = 0
var content: Node
var worksite
var player: Player
var area: Area2D
var destination: StorageDestination
var storage: Node
var storage_a: StorageDestination
var storage_b: StorageDestination
var deliveries: Array[Dictionary] = []
var inventory_changes: int = 0
var city_changes: int = 0
var saved: Dictionary = {}
var restored: bool = false


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	_prepare_fixture()
	await _load_content()
	if not is_instance_valid(worksite) or not is_instance_valid(destination) or not is_instance_valid(storage):
		_expect(false, "The content scene must expose the real City Storage endpoint and shared provider.")
		_finish()
		return
	_check_connections()
	Inventory.items_changed.connect(_on_inventory_changed)
	storage.changed.connect(_on_city_changed)
	destination.delivery_received.connect(_on_received)
	_check_provider_policy()
	_check_raw_deposit_and_direct_rejection()
	await _check_clay_destination_gate()
	_check_storage_a_b()
	_check_raw_pre_pickup()
	_check_stale_raw_cargo_return()
	_check_positive_food_hauling()
	await _check_stock_ui()
	await _check_reload()
	_finish()


func _prepare_fixture() -> void:
	var previous_storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	saved = {
		"inventory": Inventory.items.duplicate(true),
		"storage": previous_storage,
		"workers": WorkerDatabase.workers_by_id.duplicate(),
		"dismissed": WorkerDatabase.dismissed_workers.duplicate(),
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"clock_paused": TimeComponentManager.is_paused,
		"tree_paused": get_tree().paused
	}
	if is_instance_valid(previous_storage):
		saved.units = previous_storage.units.duplicate(true)
		saved.items = previous_storage.items.duplicate(true)
		saved.food_portions = previous_storage.food_portions.duplicate(true)
		saved.sequence = previous_storage._unit_sequence
		previous_storage.units.clear()
		previous_storage.items.clear()
		previous_storage.food_portions.clear()
		previous_storage._unit_sequence = 0
	# This process-local fixture never opens or overwrites a disk save slot.
	Inventory.items.clear()
	for item_id: String in RAW_ITEMS:
		if ItemDatabase.get_item_data(item_id) != null:
			Inventory.add_item(item_id, 1)
	for item_id: String in [BARLEY_BREAD, "simple_clothes", "cart", "basic_glove", "stone_hammer", "shekel"]:
		if ItemDatabase.get_item_data(item_id) != null:
			Inventory.add_item(item_id, 1)
	for id: String in [LABORER, HAULER]:
		var worker := WorkerData.new()
		worker.worker_id = id
		worker.display_name = "Arad" if id == LABORER else "Belum"
		worker.profession = WorkerData.Profession.LABORER if id == LABORER else WorkerData.Profession.HAULER
		WorkerDatabase.workers_by_id[id] = worker
		WorkerDatabase.dismissed_workers.erase(id)
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 6
	TimeComponentManager.current_minute = 0
	TimeComponentManager.is_paused = true
	get_tree().paused = false


func _load_content() -> void:
	content = CONTENT_SCENE.instantiate()
	add_child(content)
	await _frames(3)
	worksite = content.get_node_or_null("YSortWorld/Worksites")
	player = content.get_node_or_null("YSortWorld/Player") as Player
	if is_instance_valid(player):
		player.debug_disable_player_needs = true
	area = worksite.get_node_or_null("CityStorageArea") as Area2D if is_instance_valid(worksite) else null
	destination = area.get_node_or_null("DeliveryPoint") as StorageDestination if is_instance_valid(area) else null
	storage = worksite.city_tools if is_instance_valid(worksite) else null
	storage_a = worksite.get_node_or_null("StorageA") as StorageDestination if is_instance_valid(worksite) else null
	storage_b = worksite.get_node_or_null("StorageB") as StorageDestination if is_instance_valid(worksite) else null


func _check_connections() -> void:
	_expect(destination.get_storage() == storage and area.storage == storage
		and worksite.worker_management.storage == storage
		and storage == WorkStateRuntime.get_node_or_null("CityToolStorage"),
		"Content City Storage, its physical endpoint, and worker equipment must share one runtime provider.")
	_expect(destination.is_in_group("storage_destinations") and destination.is_available(),
		"The real City Storage endpoint remains discoverable for accepted cargo.")
	_expect(is_instance_valid(storage_a) and is_instance_valid(storage_b)
		and storage_a.is_available() and storage_b.is_available(),
		"Both authored Storage A and Storage B remain available endpoints.")


func _check_provider_policy() -> void:
	for item_id: String in ACCEPTED_ITEMS:
		_expect(storage.accepts_item(item_id), "City Storage accepts approved item: " + item_id)
	for item_id: String in RAW_ITEMS:
		_expect(not storage.accepts_item(item_id), "City Storage rejects raw item: " + item_id)
	var listed_ids: Array[String] = []
	for row: Dictionary in storage.get_depositable_items():
		listed_ids.append(str(row.item_id))
	for item_id: String in ACCEPTED_ITEMS:
		if Inventory.items.get(item_id, 0) > 0:
			_expect(listed_ids.has(item_id), "Deposit list exposes approved inventory item: " + item_id)
	for item_id: String in RAW_ITEMS:
		_expect(not listed_ids.has(item_id), "Deposit list hides raw inventory item: " + item_id)


func _check_raw_deposit_and_direct_rejection() -> void:
	var accepted_deposit: Dictionary = storage.deposit_items_from_inventory({BARLEY_BREAD: 1})
	_expect(bool(accepted_deposit.ok) and int(storage.items.get(BARLEY_BREAD, 0)) == 1,
		"A ready bread unit can be deposited into the real City provider.")
	var cart_deposit: Dictionary = storage.deposit_items_from_inventory({"cart": 1})
	_expect(bool(cart_deposit.ok) and cart_deposit.unit_ids.size() == 1,
		"A deposited cart creates one physical City Storage unit.")
	if bool(cart_deposit.ok) and not cart_deposit.unit_ids.is_empty():
		_expect(worksite.worker_management.equip(HAULER, str(cart_deposit.unit_ids[0])) == "Tool equipped.",
			"The Hauler equips the cart from the same shared City provider.")
	for item_id: String in RAW_ITEMS:
		var inventory_before: Dictionary = Inventory.items.duplicate(true)
		var items_before: Dictionary = storage.items.duplicate(true)
		var units_before: Dictionary = storage.units.duplicate(true)
		var city_changes_before: int = city_changes
		var deposit: Dictionary = storage.deposit_items_from_inventory({item_id: 1})
		_expect(not bool(deposit.ok) and Inventory.items == inventory_before
			and storage.items == items_before and storage.units == units_before
			and city_changes == city_changes_before,
			"Raw deposit rejects " + item_id + " atomically without Inventory, stock, unit, or signal changes.")
		var cargo: Dictionary = {"item_id": item_id, "quantity": 2}
		var direct_items_before: Dictionary = storage.items.duplicate(true)
		var direct_units_before: Dictionary = storage.units.duplicate(true)
		var direct_city_changes_before: int = city_changes
		var direct_delivery_count_before: int = deliveries.size()
		_expect(not destination.accepts_cargo(item_id, 2)
			and not destination.try_deliver_at_position(destination.get_arrival_position(), cargo)
			and cargo == {"item_id": item_id, "quantity": 2}
			and storage.items == direct_items_before and storage.units == direct_units_before
			and city_changes == direct_city_changes_before
			and deliveries.size() == direct_delivery_count_before,
			"Direct City endpoint rejection preserves complete " + item_id + " cargo and provider state.")


func _check_clay_destination_gate() -> void:
	var choices: Array[Dictionary] = worksite._storage_choices()
	var names: Array[String] = []
	var city_choice: Dictionary = {}
	var storage_a_choice: Dictionary = {}
	var storage_b_choice: Dictionary = {}
	for choice: Dictionary in choices:
		names.append(str(choice.name))
		if str(choice.name) == "City Storage":
			city_choice = choice
		elif str(choice.name) == "Storage A":
			storage_a_choice = choice
		elif str(choice.name) == "Storage B":
			storage_b_choice = choice
	_expect(names == ["City Storage", "Storage A", "Storage B"],
		"Content exposes City Storage, Storage A, and Storage B in the Hauler destination list.")
	_expect(not bool(city_choice.get("available", true))
		and str(city_choice.get("reason", "")).contains("City Storage"),
		"The real City destination is disabled for the clay worksite with a policy reason.")
	_expect(bool(storage_a_choice.get("available", false)) and bool(storage_b_choice.get("available", false)),
		"Storage A and Storage B stay enabled for clay Hauling.")

	worksite._open_site_panel(worksite.get_node("WorksiteMarkers/ClaySiteA"))
	worksite.inspector.select_mode("Daily")
	var assignment = worksite.inspector.assignment_ui
	assignment._open_worker_selection(0)
	assignment._on_worker_selected(LABORER)
	assignment._open_worker_selection(1)
	assignment._on_worker_selected(HAULER)
	var panel = assignment.hauler_setup
	var city_index: int = _find_destination_index(panel, destination)
	var a_index: int = _find_destination_index(panel, storage_a)
	_expect(panel.visible and panel.destination_button.item_count == 3
		and city_index >= 0 and panel.destination_button.is_item_disabled(city_index),
		"The actual Hauler setup disables City Storage for clay.")
	if city_index >= 0:
		panel.destination_button.select(city_index)
		panel.destination_button.item_selected.emit(city_index)
		panel.target_edit.text = "3"
		panel._validate()
		_expect(panel.assign_button.disabled
			and panel.feedback.text == "City Storage does not accept Clay Lump.",
			"A forced City selection remains disabled and shows the policy reason.")
		await _capture("city-hauler-raw-blocked.png")
		panel.assign_button.pressed.emit()
	_expect(panel.visible and not worksite.daily.selected[SITE].has(HAULER)
		and worksite.daily.hauler_setups.is_empty(),
		"A forced disabled City choice cannot assign the Hauler.")
	var assign_reason: String = worksite._assign_hauler(HAULER, worksite.get_path_to(destination), 3)
	_expect(assign_reason == "City Storage does not accept Clay Lump."
		and not worksite.daily.selected[SITE].has(HAULER) and worksite.daily.hauler_setups.is_empty(),
		"A stale assignment callback also rejects City Storage before changing the worker draft.")
	assignment._cancel_hauler()
	worksite._close_inspector()

	# Simulate a stale draft that bypassed the option control; Start must revalidate it.
	worksite._open_site_panel(worksite.get_node("WorksiteMarkers/ClaySiteA"))
	worksite.daily.selected[SITE] = [LABORER, HAULER]
	worksite.daily.hauler_setups[HAULER] = {
		"destination_path": worksite.get_path_to(destination),
		"destination_name": "City Storage", "daily_target": 3
	}
	var start_reason: String = worksite._hauler_ready(SITE, 1)
	_expect(not start_reason.is_empty() and start_reason.contains("City Storage"),
		"Start revalidation rejects a stale City Storage clay route.")
	worksite.inspector.start_button.pressed.emit()
	_expect(worksite.daily.jobs.is_empty() and not worksite.hauling.routes.has(HAULER),
		"A stale City route cannot start work or create a Hauler route.")
	worksite.daily.discard_setup(SITE)
	worksite._close_inspector()

	# Use the real UI to prove an authored clay destination still assigns and starts.
	worksite._open_site_panel(worksite.get_node("WorksiteMarkers/ClaySiteA"))
	worksite.inspector.select_mode("Daily")
	assignment = worksite.inspector.assignment_ui
	assignment._open_worker_selection(0)
	assignment._on_worker_selected(LABORER)
	assignment._open_worker_selection(1)
	assignment._on_worker_selected(HAULER)
	panel = assignment.hauler_setup
	a_index = _find_destination_index(panel, storage_a)
	_expect(a_index >= 0 and not panel.destination_button.is_item_disabled(a_index),
		"Storage A remains selectable in the real Hauler setup.")
	if a_index >= 0:
		panel.destination_button.select(a_index)
		panel.destination_button.item_selected.emit(a_index)
		panel.target_edit.text = "3"
		panel._validate()
		panel.assign_button.pressed.emit()
	assignment._on_next_pressed()
	worksite.inspector.start_button.pressed.emit()
	_expect(worksite.daily.jobs.has(SITE) and worksite.hauling.routes.has(HAULER)
		and worksite.hauling.routes[HAULER].destination_path == worksite.get_path_to(storage_a),
		"Storage A can still be assigned and started for clay through the existing UI.")
	worksite.daily.cleanup()
	worksite._close_inspector()


func _find_destination_index(panel: Control, target: Node) -> int:
	if not is_instance_valid(panel) or target == null:
		return -1
	for index: int in range(panel.destination_button.item_count):
		if panel.destination_button.get_item_metadata(index) == worksite.get_path_to(target):
			return index
	return -1


func _check_storage_a_b() -> void:
	for target: StorageDestination in [storage_a, storage_b]:
		var target_storage: Node = target.get_storage()
		var before: int = int(target_storage.quantity)
		var cargo: Dictionary = {"item_id": CLAY, "quantity": 1}
		_expect(target.is_available() and target.accepts_cargo(CLAY, 1)
			and target.try_deliver_at_position(target.get_arrival_position(), cargo)
			and int(cargo.quantity) == 0 and int(target_storage.quantity) == before + 1,
			str(target.display_name) + " remains usable for clay cargo.")


func _check_raw_pre_pickup() -> void:
	for item_id: String in RAW_ITEMS:
		var source: Dictionary = {"quantity": 3, "takes": 0}
		var raw_hauling = HAULING_SCRIPT.new()
		raw_hauling.item_id = item_id
		raw_hauling.destination_provider = func(_site_id: StringName): return destination
		raw_hauling.origin_provider = func(_site_id: StringName, _id: String): return Vector2.ZERO
		raw_hauling.output_count = func(_site_id: StringName): return source.quantity
		raw_hauling.take_output = func(_site_id: StringName, maximum: int):
			source.takes += 1
			var bounded: int = mini(maximum, source.quantity)
			source.quantity -= bounded
			return bounded
		raw_hauling.return_output = func(_site_id: StringName, quantity: int):
			source.quantity += maxi(quantity, 0)
			return true
		raw_hauling.speed = 100.0
		var route_id: String = "raw_pre_pickup_" + item_id
		raw_hauling.begin(route_id, &"RawSource", 100, {"daily_target": 3})
		var items_before: Dictionary = storage.items.duplicate(true)
		raw_hauling.tick(100, func(_id: String): return true, func(_site_id: StringName): return false)
		var route: Dictionary = raw_hauling.routes[route_id]
		_expect(str(route.phase) == "idle" and int(route.cargo.quantity) == 0
			and source.quantity == 3 and source.takes == 0 and storage.items == items_before,
			"Raw " + item_id + " is rejected before pickup, leaving the complete source output in place.")
		raw_hauling.routes.clear()


func _check_stale_raw_cargo_return() -> void:
	var source: Dictionary = {"quantity": 3}
	var raw_hauling = HAULING_SCRIPT.new()
	raw_hauling.item_id = CLAY
	raw_hauling.destination_provider = func(_site_id: StringName): return storage_a
	raw_hauling.origin_provider = func(_site_id: StringName, _id: String): return Vector2.ZERO
	raw_hauling.output_count = func(_site_id: StringName): return source.quantity
	raw_hauling.take_output = func(_site_id: StringName, maximum: int):
		var bounded: int = mini(maximum, source.quantity)
		source.quantity -= bounded
		return bounded
	raw_hauling.return_output = func(_site_id: StringName, quantity: int):
		source.quantity += maxi(quantity, 0)
		return true
	raw_hauling.speed = 100.0
	var route_id: String = HAULER
	raw_hauling.delivered.connect(worksite.worker_management.record_contribution)
	raw_hauling.begin(route_id, &"RawSource", 200, {"daily_target": 3})
	raw_hauling.tick(200, func(_id: String): return true, func(_site_id: StringName): return false)
	var route: Dictionary = raw_hauling.routes[route_id]
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_xp: int = WorkerDatabase.get_worker_data(HAULER).profession_xp
	_expect(str(route.phase) == "outbound" and int(route.cargo.quantity) == 3 and source.quantity == 0,
		"The raw test fixture can establish a bounded in-flight cargo before the destination policy changes.")
	# Simulate a stale route whose raw destination became City Storage after pickup.
	route.destination = destination
	route.target = destination.get_arrival_position()
	route.arrival = 201
	raw_hauling.tick(201, func(_id: String): return true, func(_site_id: StringName): return false)
	_expect(str(route.phase) == "returning" and int(route.cargo.quantity) == 3
		and deliveries.is_empty() and storage.items == before_items
		and raw_hauling.delivered_on_day(route_id, 0) == 0
		and WorkerDatabase.get_worker_data(HAULER).profession_xp == before_xp,
		"A stale in-flight raw City delivery returns intact without credit, receipt, or XP.")
	var return_arrival: int = int(route.arrival)
	raw_hauling.tick(return_arrival, func(_id: String): return true, func(_site_id: StringName): return false)
	_expect(str(route.phase) == "idle" and int(route.cargo.quantity) == 0 and source.quantity == 3,
		"Rejected in-flight raw cargo returns to its source exactly once.")
	raw_hauling.routes.clear()


func _check_positive_food_hauling() -> void:
	var source: Dictionary = {"quantity": BREAD_SOURCE_CAPACITY, "takes": 0}
	var food_hauling = HAULING_SCRIPT.new()
	food_hauling.item_id = BARLEY_BREAD
	food_hauling.destination_provider = func(_site_id: StringName): return destination
	food_hauling.origin_provider = func(_site_id: StringName, _id: String):
		return destination.get_arrival_position() + Vector2(-100, 0)
	food_hauling.output_count = func(_site_id: StringName): return source.quantity
	food_hauling.take_output = func(_site_id: StringName, maximum: int):
		if maximum <= 0 or source.quantity <= 0:
			return 0
		source.takes += 1
		# The callback is deliberately bounded by the test-owned source capacity.
		var bounded: int = mini(mini(maximum, source.quantity), BREAD_SOURCE_CAPACITY)
		source.quantity -= bounded
		return bounded
	food_hauling.return_output = func(_site_id: StringName, quantity: int):
		if quantity <= 0 or source.quantity + quantity > BREAD_SOURCE_CAPACITY:
			return false
		source.quantity += quantity
		return true
	food_hauling.speed = 100.0
	var route_id: String = HAULER
	var target: int = 5
	var initial_stock: int = int(storage.items.get(BARLEY_BREAD, 0))
	var initial_xp: int = WorkerDatabase.get_worker_data(HAULER).profession_xp
	var initial_city_changes: int = city_changes
	var initial_inventory_changes: int = inventory_changes
	food_hauling.delivered.connect(func(id: String, quantity: int):
		worksite.worker_management.record_contribution(id, quantity))
	food_hauling.begin(route_id, &"BreadSource", 300, {"daily_target": target})
	food_hauling.tick(300, func(_id: String): return true, func(_site_id: StringName): return false)
	var route: Dictionary = food_hauling.routes[route_id]
	_expect(str(route.phase) == "outbound" and int(route.cargo.quantity) == 3
		and source.quantity == 2 and source.takes == 1 and storage.items.get(BARLEY_BREAD, 0) == initial_stock,
		"The independent bread Hauler takes one full three-item load without early City credit.")
	var committed_receipt := func(item_id: String, quantity: int):
		_expect(item_id == BARLEY_BREAD and quantity > 0 and int(route.cargo.quantity) == 0
			and int(storage.items.get(BARLEY_BREAD, 0)) + int(source.quantity) == initial_stock + BREAD_SOURCE_CAPACITY,
			"Receipt observers see committed stock and empty cargo with the complete bread supply conserved.")
	destination.delivery_received.connect(committed_receipt)
	var first_arrival: int = int(route.arrival)
	food_hauling.tick(first_arrival, func(_id: String): return true, func(_site_id: StringName): return false)
	_expect(str(route.phase) == "returning" and int(route.cargo.quantity) == 0
		and deliveries == [{"item_id": BARLEY_BREAD, "quantity": 3}]
		and int(storage.items.get(BARLEY_BREAD, 0)) == initial_stock + 3
		and food_hauling.delivered_on_day(route_id, 0) == 3
		and not food_hauling.target_reached(route_id, 0),
		"Only the accepted full bread load counts toward City stock and the daily target.")
	var first_return: int = int(route.arrival)
	food_hauling.tick(first_return, func(_id: String): return true, func(_site_id: StringName): return false)
	food_hauling.tick(first_return + 1, func(_id: String): return true, func(_site_id: StringName): return false)
	route = food_hauling.routes[route_id]
	_expect(str(route.phase) == "outbound" and int(route.cargo.quantity) == 2 and source.quantity == 0,
		"The independent bread Hauler takes the bounded final partial load.")
	var second_arrival: int = int(route.arrival)
	destination.accepting_deliveries = false
	food_hauling.tick(second_arrival, func(_id: String): return true, func(_site_id: StringName): return false)
	_expect(str(route.phase) == "returning" and int(route.cargo.quantity) == 2
		and int(storage.items.get(BARLEY_BREAD, 0)) == initial_stock + 3
		and food_hauling.delivered_on_day(route_id, 0) == 3
		and WorkerDatabase.get_worker_data(HAULER).profession_xp == initial_xp + 3
		and city_changes == initial_city_changes + 1 and deliveries.size() == 1,
		"A closed endpoint preserves the partial load without stock, target, signal or XP credit.")
	var rejected_return: int = int(route.arrival)
	food_hauling.tick(rejected_return, func(_id: String): return true, func(_site_id: StringName): return false)
	food_hauling.tick(rejected_return + 1, func(_id: String): return true, func(_site_id: StringName): return false)
	_expect(str(route.phase) == "idle" and int(route.cargo.quantity) == 0 and source.quantity == 2
		and source.takes == 2, "The rejected load returns intact and cannot be picked up while City Storage is unavailable.")
	destination.accepting_deliveries = true
	food_hauling.tick(rejected_return + 2, func(_id: String): return true, func(_site_id: StringName): return false)
	_expect(str(route.phase) == "outbound" and int(route.cargo.quantity) == 2 and source.quantity == 0
		and source.takes == 3, "The restored partial load is retried once when City Storage reopens.")
	food_hauling.tick(int(route.arrival), func(_id: String): return true, func(_site_id: StringName): return false)
	_expect(str(route.phase) == "returning" and int(route.cargo.quantity) == 0
		and deliveries == [{"item_id": BARLEY_BREAD, "quantity": 3}, {"item_id": BARLEY_BREAD, "quantity": 2}]
		and int(storage.items.get(BARLEY_BREAD, 0)) == initial_stock + target
		and food_hauling.delivered_on_day(route_id, 0) == target
		and food_hauling.target_reached(route_id, 0)
		and WorkerDatabase.get_worker_data(HAULER).profession_xp == initial_xp + target
		and int(worksite.worker_management.contributions.get(HAULER, 0)) == target,
		"Accepted full and partial bread deliveries alone record the target and XP through WorkerManagement.")
	var second_return: int = int(route.arrival)
	food_hauling.tick(second_return, func(_id: String): return true, func(_site_id: StringName): return false)
	food_hauling.tick(second_return + 60, func(_id: String): return true, func(_site_id: StringName): return false)
	_expect(int(storage.items.get(BARLEY_BREAD, 0)) == initial_stock + target
		and deliveries.size() == 2 and city_changes == initial_city_changes + 2
		and inventory_changes == initial_inventory_changes,
		"Target completion prevents duplicate receipts, repeated ticks, and personal inventory signals.")
	var inventory_before_withdraw: Dictionary = Inventory.items.duplicate(true)
	var withdraw: Dictionary = storage.withdraw_items_to_inventory({BARLEY_BREAD: 1})
	_expect(not bool(withdraw.ok) and Inventory.items == inventory_before_withdraw
		and int(storage.items.get(BARLEY_BREAD, 0)) == initial_stock + target,
		"Accepted City food remains city-owned with no withdrawal or return path.")
	destination.delivery_received.disconnect(committed_receipt)
	food_hauling.routes.clear()


func _check_stock_ui() -> void:
	player.global_position = destination.get_arrival_position()
	for _index: int in range(3):
		await get_tree().physics_frame
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	get_viewport().push_input(interact)
	await _frames(3)
	_expect(is_instance_valid(area.menu), "Player E opens the shared City stock after accepted Hauler delivery.")
	if not is_instance_valid(area.menu):
		return
	var displayed_bread: int = 0
	for slot: ItemSlot in area.menu.grid.get_children():
		if slot._item_id == BARLEY_BREAD:
			displayed_bread = slot._quantity
	_expect(displayed_bread == 1 + BREAD_SOURCE_CAPACITY,
		"The City grid combines the player's bread deposit and accepted Hauler loads in one stack.")
	await _capture("city-hauler-food-stock.png")
	area.close_menu()
	await _frames(2)


func _on_received(item_id: String, quantity: int) -> void:
	deliveries.append({"item_id": item_id, "quantity": quantity})


func _on_inventory_changed() -> void:
	inventory_changes += 1


func _on_city_changed() -> void:
	city_changes += 1


func _check_reload() -> void:
	var provider: Node = storage
	var retained_items: Dictionary = storage.items.duplicate(true)
	var retained_units: Dictionary = storage.units.duplicate(true)
	var retained_food_portions: Dictionary = storage.food_portions.duplicate(true)
	if storage.changed.is_connected(_on_city_changed):
		storage.changed.disconnect(_on_city_changed)
	if destination.delivery_received.is_connected(_on_received):
		destination.delivery_received.disconnect(_on_received)
	if Inventory.items_changed.is_connected(_on_inventory_changed):
		Inventory.items_changed.disconnect(_on_inventory_changed)
	worksite.daily.cleanup()
	content.free()
	await _frames(2)
	await _load_content()
	_expect(storage == provider and storage.items == retained_items and storage.units == retained_units
		and storage.food_portions == retained_food_portions,
		"Accepted City stock and physical units survive replacement of the content scene through the shared provider.")
	_expect(destination.get_storage() == provider and worksite._storage_choices().size() == 3,
		"The replacement content scene binds one retained City endpoint without duplicates.")
	storage.changed.connect(_on_city_changed)
	destination.delivery_received.connect(_on_received)
	Inventory.items_changed.connect(_on_inventory_changed)


func _frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _capture(filename: String) -> void:
	await _frames(2)
	var directory: String = OS.get_environment("TIP_CITY_HAUL_CAPTURE_DIR")
	if DisplayServer.get_name() == "headless" or directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(directory.path_join(filename))
	_expect(error == OK, "The rendered integration capture must be saved: " + filename)


func _finish() -> void:
	_restore()
	print("CityStorageHaulingTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)


func _restore() -> void:
	if restored or saved.is_empty():
		return
	restored = true
	if Inventory.items_changed.is_connected(_on_inventory_changed):
		Inventory.items_changed.disconnect(_on_inventory_changed)
	if is_instance_valid(storage) and storage.changed.is_connected(_on_city_changed):
		storage.changed.disconnect(_on_city_changed)
	if is_instance_valid(destination) and destination.delivery_received.is_connected(_on_received):
		destination.delivery_received.disconnect(_on_received)
	if is_instance_valid(content):
		if is_instance_valid(worksite):
			worksite.daily.cleanup()
		content.free()
	Inventory.items = saved.inventory.duplicate(true)
	WorkerDatabase.workers_by_id = saved.workers
	WorkerDatabase.dismissed_workers = saved.dismissed
	if is_instance_valid(saved.storage):
		saved.storage.units = saved.units
		saved.storage.items = saved.items
		saved.storage.food_portions = saved.food_portions
		saved.storage._unit_sequence = saved.sequence
	elif is_instance_valid(storage):
		storage.free()
	TimeComponentManager.current_day = int(saved.day)
	TimeComponentManager.current_hour = int(saved.hour)
	TimeComponentManager.current_minute = int(saved.minute)
	TimeComponentManager.current_weather = str(saved.weather)
	TimeComponentManager.is_paused = bool(saved.clock_paused)
	get_tree().paused = bool(saved.tree_paused)


func _exit_tree() -> void:
	_restore()
