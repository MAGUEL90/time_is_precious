extends Node

const CONTENT_SCENE: PackedScene = preload("res://scenes/test_scenes/fixtures/content_worksites_map.tscn")
const HOME_SCENE: PackedScene = preload("res://scenes/player_home_interior/player_home_interior.tscn")
const TEST_WORKER_ID: String = "city_storage_supply_flow_worker"
const INITIAL_CART_UNIT_ID: String = "initial_worksite_cart"
const FORBIDDEN_PLAYER_IDS: Array[String] = [
	"gold_nugget", "egg", "butchers_cut", "barley_grain_sack", "clay_lump", "wood_log",
	"reed_bundle", "straw_bundle", "water_jar", "copper_ore", "copper_chunk",
	"limestone_piece", "large_stone", "stone", "bronze_ingot", "wet_mudbrick",
	"sun_dried_mudbrick", "raw_wool"
]
const VISIBLE_ALLOWED_PLAYER_IDS: Array[String] = [
	"barley_bread", "simple_clothes", "clay_worn_wrap", "plain_linen_wrap", "shekel",
	"basic_glove", "cart", "stone_hammer"
]

var failures: int = 0
var content: Node
var home: Node
var worksite
var player: Player
var worker_control: WorkerControlUI
var storage: Node
var area: Area2D
var deposited_unit_id: String = ""

var original_inventory: Dictionary = {}
var original_max_load: float = 100.0
var original_storage: Node
var original_storage_units: Dictionary = {}
var original_storage_items: Dictionary = {}
var original_storage_portions: Dictionary = {}
var original_storage_sequence: int = 0
var original_food_supply: int = 0
var original_clothing_supply: int = 0
var original_worker: WorkerData
var original_dismissed_worker: WorkerData
var original_clock: Dictionary = {}
var original_tree_paused: bool = false
var original_transitioning: bool = false
var restored: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_snapshot_global_state()
	_prepare_global_fixture()
	await _load_content()
	if not is_instance_valid(worksite) or not is_instance_valid(worker_control) or not is_instance_valid(storage) or not is_instance_valid(area):
		_expect(false, "Content scene must expose Worksites, WorkerControlUI, CityToolStorage, and CityStorageArea.")
		_finish()
		return

	player.debug_disable_player_needs = true
	var expected_initial_units: Dictionary = {
		INITIAL_CART_UNIT_ID: {"tool_id": "cart", "name": "Cart", "worker_id": ""}
	}
	_expect(storage.units == expected_initial_units and storage.items.is_empty()
		and storage.food_portions.is_empty(),
		"City Storage starts with only one unallocated city-owned Cart and no other stock.")
	await _test_physical_city_storage()
	await _test_worker_equip_and_unequip_after_reload()
	await _test_access_lifecycle()
	_finish()


func _snapshot_global_state() -> void:
	original_inventory = Inventory.items.duplicate(true)
	original_max_load = Inventory.max_load
	original_storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if is_instance_valid(original_storage):
		original_storage_units = original_storage.units.duplicate(true)
		original_storage_items = original_storage.items.duplicate(true)
		original_storage_portions = original_storage.food_portions.duplicate(true)
		original_storage_sequence = int(original_storage._unit_sequence)
	original_food_supply = CityStockManager.food_supply
	original_clothing_supply = CityStockManager.clothing_supply
	original_worker = WorkerDatabase.workers_by_id.get(TEST_WORKER_ID, null)
	original_dismissed_worker = WorkerDatabase.dismissed_workers.get(TEST_WORKER_ID, null)
	original_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused
	}
	original_tree_paused = get_tree().paused
	original_transitioning = SceneTransition.is_transitioning


func _prepare_global_fixture() -> void:
	# The fixture is process-local and restored in _finish/_exit_tree. It never uses a disk save slot.
	if is_instance_valid(original_storage):
		original_storage.units.clear()
		original_storage.items.clear()
		original_storage.food_portions.clear()
		original_storage._unit_sequence = 0
	Inventory.items.clear()
	Inventory.add_item("cart", 1)
	Inventory.add_item("basic_glove", 1)
	Inventory.add_item("stone_hammer", 2)
	for item_id: String in FORBIDDEN_PLAYER_IDS:
		Inventory.add_item(item_id, 1)
	# Keep one personal bread in Inventory; City Storage has no return path.
	Inventory.add_item("barley_bread", 3)
	Inventory.add_item("simple_clothes", 1)
	Inventory.add_item("clay_worn_wrap", 1)
	Inventory.add_item("plain_linen_wrap", 1)
	Inventory.add_item("shekel", 2)
	WorkerDatabase.dismissed_workers.erase(TEST_WORKER_ID)
	var worker := WorkerData.new()
	worker.worker_id = TEST_WORKER_ID
	worker.display_name = "City Supply Test Worker"
	worker.profession = WorkerData.Profession.LABORER
	worker.wage_shekel_per_day = 1
	WorkerDatabase.workers_by_id[TEST_WORKER_ID] = worker
	TimeComponentManager.is_paused = true
	get_tree().paused = false


func _load_content() -> void:
	content = CONTENT_SCENE.instantiate()
	add_child(content)
	await _wait_frames(3)
	_bind_content_nodes()


func _bind_content_nodes() -> void:
	worksite = content.get_node_or_null("YSortWorld/Worksites")
	player = content.get_node_or_null("YSortWorld/Player") as Player
	worker_control = worksite.get_node_or_null("WorkerControlUI") as WorkerControlUI if is_instance_valid(worksite) else null
	storage = worksite.city_tools if is_instance_valid(worksite) else null
	area = worksite.get_node_or_null("CityStorageArea") as Area2D if is_instance_valid(worksite) else null


func _test_physical_city_storage() -> void:
	var area_origin: Vector2 = area.global_position
	player.global_position = area_origin + Vector2(100, 0)
	await _physics_frames(3)
	_expect(not _area_has_access() and player.current_interactable != area,
		"Distant player position cannot access City Storage.")
	player._unhandled_input(_action("interact"))
	await _wait_frames(2)
	_expect(not is_instance_valid(_area_menu()), "Distant E input does not open City Storage.")

	player.global_position = area_origin + Vector2(0, 12)
	await _physics_frames(3)
	_expect(_area_has_access(), "Player enters the City Storage Area2D access shape.")
	get_viewport().push_input(_action("interact"))
	await _wait_frames(3)
	var access_ui: CanvasLayer = _area_menu()
	_expect(is_instance_valid(access_ui), "Player E opens the physical City Storage menu.")
	if not is_instance_valid(access_ui):
		return
	var view: Control = access_ui.get("view") as Control
	_expect(view.visible and get_tree().paused and not player.can_move,
		"Physical City Storage pauses the world and locks player movement.")
	_expect(not bool(worksite.call("_can_open_worker_hub")),
		"Worker Hub cannot open while the physical City Storage menu owns pause.")
	_expect(worker_control.get_node_or_null("Root/Center/Window/Margin/MainVBox/Tabs/CityStorageButton") == null
		and worker_control.get_node_or_null("CityStorageMenuUI") == null,
		"Worker Hub has no duplicate City Storage tab or menu.")
	await _check_area_storage_layout(view)
	await _assert_no_withdraw_ui(access_ui)
	await _capture("city-storage-area.png")

	# Inventory changes clear staged transfer quantities while the real Area menu is open.
	var refresh_transfer: ItemTransferUI = await _open_area_transfer(access_ui, "deposit")
	var refresh_slot: ItemSlot = _find_transfer_slot(refresh_transfer, "stone_hammer")
	_expect(refresh_slot != null, "Deposit lists equipment stock.")
	for item_id: String in VISIBLE_ALLOWED_PLAYER_IDS:
		_expect(_find_transfer_slot(refresh_transfer, item_id) != null,
			"Deposit lists accepted player stock: " + item_id)
	for item_id: String in FORBIDDEN_PLAYER_IDS:
		_expect(_find_transfer_slot(refresh_transfer, item_id) == null,
			"Deposit hides forbidden raw or unsupported player stock: " + item_id)
	if refresh_slot != null:
		refresh_slot.pressed.emit()
		var source_quantity: int = int(refresh_transfer.source_items.get("stone_hammer", 0))
		Inventory.add_item("stone_hammer", 1)
		await _wait_frames(3)
		_expect(refresh_transfer.selected_items.is_empty()
			and int(refresh_transfer.source_items.get("stone_hammer", 0)) == source_quantity + 1,
			"Inventory.items_changed clears stale physical-area transfer selection.")
		Inventory.remove_item("stone_hammer", 1)
		await _wait_frames(2)
	var refresh_clear: Button = access_ui.get("clear_button") as Button
	if is_instance_valid(refresh_clear):
		refresh_clear.pressed.emit()
	refresh_transfer.close_button.pressed.emit()
	await _wait_frames(3)
	_expect(view.visible and get_tree().paused and not is_instance_valid(access_ui.get("transfer_ui")),
		"Transfer Close returns to the same physical City Storage view.")

	# Closing a staged transfer cancels it without consuming any player stock.
	var cancel_transfer: ItemTransferUI = await _open_area_transfer(access_ui, "deposit")
	var cancel_inventory: Dictionary = Inventory.items.duplicate(true)
	var cancel_units: Dictionary = storage.units.duplicate(true)
	var cancel_items: Dictionary = storage.items.duplicate(true)
	var cancel_portions: Dictionary = storage.food_portions.duplicate(true)
	_stage_transfer_items(cancel_transfer, {"barley_bread": 1})
	cancel_transfer.close_button.pressed.emit()
	await _wait_frames(3)
	_expect(Inventory.items == cancel_inventory and storage.units == cancel_units
		and storage.items == cancel_items and storage.food_portions == cancel_portions
		and view.visible and get_tree().paused and not is_instance_valid(_area_transfer(access_ui)),
		"Cancelling a staged player deposit preserves all state and returns to City Storage.")

	# A forged direct selection cannot bypass the same accepted-item policy used by the UI.
	_assert_forbidden_mixed_deposit_is_atomic({"cart": 1, "clay_lump": 1}, "Forged mixed player deposit")

	# Deposit equipment, ready food, clothing, and currency in one atomic UI transfer.
	var inventory_before_deposit: Dictionary = Inventory.items.duplicate(true)
	var units_before_deposit: Dictionary = storage.units.duplicate(true)
	var items_before_deposit: Dictionary = storage.items.duplicate(true)
	var deposit_transfer: ItemTransferUI = await _open_area_transfer(access_ui, "deposit")
	var deposit_selection: Dictionary = {
		"stone_hammer": 1, "basic_glove": 1, "barley_bread": 2,
		"simple_clothes": 1, "clay_worn_wrap": 1, "shekel": 1
	}
	_stage_transfer_items(deposit_transfer, deposit_selection)
	_expect(deposit_transfer.selected_items == deposit_selection,
		"Deposit stages exact quantities for mixed accepted stock.")
	await _capture("city-storage-area-deposit.png")
	deposit_transfer.confirm_button.pressed.emit()
	if is_instance_valid(deposit_transfer):
		deposit_transfer.confirm_button.pressed.emit()
	await _wait_frames(4)
	_expect(_inventory_quantity("stone_hammer") == int(inventory_before_deposit.get("stone_hammer", 0)) - 1
		and _inventory_quantity("basic_glove") == int(inventory_before_deposit.get("basic_glove", 0)) - 1
		and _inventory_quantity("barley_bread") == int(inventory_before_deposit.get("barley_bread", 0)) - 2
		and _inventory_quantity("simple_clothes") == int(inventory_before_deposit.get("simple_clothes", 0)) - 1
		and _inventory_quantity("clay_worn_wrap") == int(inventory_before_deposit.get("clay_worn_wrap", 0)) - 1
		and _inventory_quantity("shekel") == int(inventory_before_deposit.get("shekel", 0)) - 1
		and _unit_count("stone_hammer") == _unit_count_from(units_before_deposit, "stone_hammer") + 1
		and _unit_count("basic_glove") == _unit_count_from(units_before_deposit, "basic_glove") + 1
		and storage.items == {"barley_bread": 2, "simple_clothes": 1, "clay_worn_wrap": 1, "shekel": 1}
		and CityStockManager.food_supply == original_food_supply
		and CityStockManager.clothing_supply == original_clothing_supply,
		"Mixed physical deposit transfers exact accepted quantities without CityStock conversion.")
	_expect(view.visible and get_tree().paused and not is_instance_valid(_area_transfer(access_ui)),
		"Repeated stale Deposit confirmation preserves the area menu pause and transfers once.")

	# Legacy city stock remains visible even though new deposits reject it.
	storage.items["clay_lump"] = 2
	storage.changed.emit()
	await _wait_frames(3)
	_expect(storage.get_available_items().get("clay_lump", 0) == 2
		and _find_area_storage_slot(access_ui, "clay_lump") != null,
		"Existing unsupported city stock remains preserved and displayed in the storage view.")

	# City Storage is deposit-only. A stale withdraw mode cannot create a dialog.
	await _assert_no_withdraw_ui(access_ui)

	# Deposit a cart for the existing Worker Hub equip and retention path.
	var cart_transfer: ItemTransferUI = await _open_area_transfer(access_ui, "deposit")
	var cart_slot: ItemSlot = _find_transfer_slot(cart_transfer, "cart")
	_expect(cart_slot != null, "Deposit exposes the cart equipment item.")
	if cart_slot != null:
		cart_slot.pressed.emit()
		cart_transfer.confirm_button.pressed.emit()
	await _wait_frames(4)
	deposited_unit_id = _find_unallocated_unit("cart")
	_expect(not deposited_unit_id.is_empty() and _inventory_quantity("cart") == 0,
		"Cart deposit creates a free physical unit for Worker Hub equip.")

	# Leave-area confirmation must hit the live position guard before any commit.
	var leave_inventory: Dictionary = Inventory.items.duplicate(true)
	var leave_units: Dictionary = storage.units.duplicate(true)
	var leave_items: Dictionary = storage.items.duplicate(true)
	var leave_transfer: ItemTransferUI = await _open_area_transfer(access_ui, "deposit")
	var leave_slot: ItemSlot = _find_transfer_slot(leave_transfer, "barley_bread")
	_expect(leave_slot != null, "Leave-area guard has a valid staged transfer.")
	if leave_slot != null:
		leave_slot.pressed.emit()
	player.global_position = area_origin + Vector2(100, 0)
	leave_transfer.confirm_button.pressed.emit()
	await _wait_frames(3)
	_expect(Inventory.items == leave_inventory and storage.units == leave_units and storage.items == leave_items
		and not is_instance_valid(_area_menu()) and not get_tree().paused and player.can_move,
		"Confirming after leaving the Area2D rejects the transfer without mutation or pause leakage.")

	# Re-enter and use Escape through transfer, menu, and back to the world.
	await _move_to_storage(area_origin)
	player._unhandled_input(_action("interact"))
	await _wait_frames(3)
	access_ui = _area_menu()
	var escape_transfer: ItemTransferUI = await _open_area_transfer(access_ui, "deposit")
	get_viewport().push_input(_action("ui_cancel"))
	await _wait_frames(3)
	_expect(is_instance_valid(_area_menu()) and not is_instance_valid(_area_transfer(access_ui))
		and get_tree().paused and not player.can_move,
		"Escape closes the transfer and returns to the Area menu with pause retained.")
	get_viewport().push_input(_action("ui_cancel"))
	await _wait_frames(3)
	_expect(not is_instance_valid(_area_menu()) and not get_tree().paused and player.can_move,
		"Escape closes the Area menu and restores world control.")
	await _test_inventory_send_removed()


func _test_worker_equip_and_unequip_after_reload() -> void:
	_expect(not deposited_unit_id.is_empty(), "Worker equip flow has a deposited unit fixture.")
	if deposited_unit_id.is_empty():
		return
	worker_control.open()
	worker_control._select_worker_for_tools(TEST_WORKER_ID)
	worker_control.tools_tool_button.pressed.emit()
	await _wait_frames(2)
	_expect(_hub_tabs_are_aligned(), "Status, Tools, and Level remain aligned.")
	_expect(worker_control.city_storage_view.get_node_or_null("Margin/Content/Footer/Deposit") == null
		and worker_control.city_storage_view.get_node_or_null("Margin/Content/Footer/Withdraw") == null,
		"Worker equipment selection has no remote Deposit/Withdraw actions.")
	var unit_slot: ItemSlot = _find_unit_slot(deposited_unit_id)
	var already_equipped: bool = str(storage.units.get(deposited_unit_id, {}).get("worker_id", "")) == TEST_WORKER_ID
	_expect(unit_slot != null and not unit_slot.disabled, "Worker tool storage exposes the deposited cart in its compatible slot.")
	if unit_slot == null or unit_slot.disabled:
		worker_control.close()
		return
	if already_equipped:
		_expect(unit_slot.selected_qty.visible and unit_slot.selected_qty.text == "E",
			"The already equipped cart remains marked E before retention.")
	else:
		unit_slot.pressed.emit()
		await _wait_frames(1)
		var equip_panel: OptionPanel = worker_control.city_action_panel
		_expect(is_instance_valid(equip_panel) and equip_panel.use_button.text == "Equip",
			"Selecting an available physical unit opens Equip.")
		if is_instance_valid(equip_panel):
			equip_panel.use_button.pressed.emit()
		await _wait_frames(3)
	_expect(storage.units[deposited_unit_id].worker_id == TEST_WORKER_ID,
		"Equip allocates the deposited unit to the selected worker.")

	worker_control._input(_action("ui_cancel"))
	await _wait_frames(1)
	worker_control._input(_action("ui_cancel"))
	await _wait_frames(2)
	_expect(not worker_control.visible and not get_tree().paused, "Worker tool storage closes cleanly before scene retention check.")
	await _move_to_storage(area.global_position)
	player._unhandled_input(_action("interact"))
	await _wait_frames(2)
	var access_ui: CanvasLayer = _area_menu()
	await _assert_no_withdraw_ui(access_ui)
	access_ui.call("close")
	await _wait_frames(2)

	var storage_ref: Node = storage
	var retained_items: Dictionary = storage.items.duplicate(true)
	var changed_connections_before: int = storage.changed.get_connections().size()
	var inventory_connections_before: int = Inventory.items_changed.get_connections().size()
	content.free()
	content = null
	await _wait_frames(2)

	# Instantiate the authored home scene between map instances to prove process-lifetime retention.
	home = HOME_SCENE.instantiate()
	add_child(home)
	await _wait_frames(3)
	_expect(home.get_node_or_null("YSortWorld/Player") != null, "The authored player home scene loads during retention coverage.")
	home.free()
	home = null
	await _wait_frames(2)

	content = CONTENT_SCENE.instantiate()
	add_child(content)
	await _wait_frames(3)
	_bind_content_nodes()
	player.debug_disable_player_needs = true
	_expect(storage == storage_ref and worksite.city_tools == storage_ref,
		"Reloaded content reuses the same WorkStateRuntime CityToolStorage node.")
	_expect(storage.items == retained_items and not retained_items.is_empty(),
		"Physical non-equipment stacks survive content -> home -> content.")
	_expect(storage.units.has(deposited_unit_id)
		and storage.units[deposited_unit_id].worker_id == TEST_WORKER_ID,
		"The exact deposited unit id and worker allocation survive content -> home -> content.")
	_expect(storage.changed.get_connections().size() == changed_connections_before
		and Inventory.items_changed.get_connections().size() == inventory_connections_before,
		"Scene retention does not duplicate City Storage or Inventory signal connections.")

	worker_control.open()
	worker_control._select_worker_for_tools(TEST_WORKER_ID)
	worker_control.tools_tool_button.pressed.emit()
	await _wait_frames(2)
	var equipped_slot: ItemSlot = _find_unit_slot(deposited_unit_id)
	_expect(equipped_slot != null and equipped_slot.selected_qty.visible and equipped_slot.selected_qty.text == "E",
		"Reloaded Worker Hub shows the same physical unit as equipped.")
	if equipped_slot != null:
		equipped_slot.pressed.emit()
		await _wait_frames(1)
		var unequip_panel: OptionPanel = worker_control.city_action_panel
		_expect(is_instance_valid(unequip_panel) and unequip_panel.use_button.text == "Unequip",
			"Selecting the allocated unit opens Unequip.")
		if is_instance_valid(unequip_panel):
			unequip_panel.use_button.pressed.emit()
		await _wait_frames(3)
	_expect(storage.units[deposited_unit_id].worker_id.is_empty(),
		"Unequip returns the same deposited physical unit to City Storage.")
	worker_control.close()
	await _wait_frames(1)


func _check_city_storage_shortcut_guard() -> void:
	var before: int = worksite.daily.now()
	worksite._unhandled_input(_key(KEY_F7))
	worksite._unhandled_input(_key(KEY_F))
	_expect(worksite.daily.now() == before, "F and F7 remain blocked while City Storage owns input.")


func _area_has_access() -> bool:
	return is_instance_valid(area) and bool(area.call("has_player_access"))


func _area_menu() -> CanvasLayer:
	return area.get("menu") as CanvasLayer if is_instance_valid(area) else null


func _area_transfer(menu: CanvasLayer) -> ItemTransferUI:
	return menu.get("transfer_ui") as ItemTransferUI if is_instance_valid(menu) else null


func _physics_frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().physics_frame
	await _wait_frames(2)


func _move_to_storage(origin: Vector2) -> void:
	player.global_position = origin + Vector2(100, 0)
	await _physics_frames(3)
	player.global_position = origin + Vector2(0, 12)
	await _physics_frames(3)


func _open_area_transfer(menu: CanvasLayer, mode: String) -> ItemTransferUI:
	var button := menu.get(mode + "_button") as Button
	_expect(is_instance_valid(button) and not button.disabled, "Area offers " + mode + " for available stock.")
	button.pressed.emit()
	await _wait_frames(3)
	var transfer := _area_transfer(menu)
	_expect(is_instance_valid(transfer) and transfer.visible and get_tree().paused,
		"Physical area opens the shared quantity dialog.")
	if is_instance_valid(transfer):
		_check_transfer_layout(transfer)
		_expect(transfer.title_label.text == "Deposit to City (no return)",
			"City Storage transfer dialog visibly states that deposited items have no return path.")
		_check_city_storage_shortcut_guard()
	return transfer


func _assert_no_withdraw_ui(menu: CanvasLayer) -> void:
	_expect(is_instance_valid(menu), "City Storage menu remains available for no-return UI checks.")
	if not is_instance_valid(menu):
		return
	var view: Control = menu.get("view") as Control
	_expect(menu.get("withdraw_button") == null and view.find_child("WithdrawButton", true, false) == null,
		"City Storage exposes no Withdraw button after the no-return rule.")
	menu.call("_open_transfer", "withdraw")
	await _wait_frames(2)
	_expect(not is_instance_valid(_area_transfer(menu)) and str(menu.get("_transfer_mode")) == "",
		"A stale withdraw mode cannot create a City Storage quantity dialog.")


func _stage_transfer_items(transfer: ItemTransferUI, selection: Dictionary) -> void:
	for item_id: String in selection:
		var slot := _find_transfer_slot(transfer, item_id)
		_expect(slot != null, "Transfer exposes " + item_id)
		if slot != null:
			for index: int in range(int(selection[item_id])):
				slot.pressed.emit()


func _assert_forbidden_mixed_deposit_is_atomic(selection: Dictionary, label: String) -> void:
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_units: Dictionary = storage.units.duplicate(true)
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_portions: Dictionary = storage.food_portions.duplicate(true)
	var before_sequence: int = int(storage._unit_sequence)
	var inventory_signal_count: Array[int] = [0]
	var city_signal_count: Array[int] = [0]
	var on_inventory_changed := func():
		inventory_signal_count[0] += 1
	var on_city_changed := func():
		city_signal_count[0] += 1
	Inventory.items_changed.connect(on_inventory_changed)
	storage.changed.connect(on_city_changed)
	var result: Dictionary = storage.deposit_items_from_inventory(selection)
	Inventory.items_changed.disconnect(on_inventory_changed)
	storage.changed.disconnect(on_city_changed)
	_expect(not bool(result.ok) and result.unit_ids.is_empty(), label + " is rejected as a whole transaction.")
	_expect(Inventory.items == before_inventory and storage.units == before_units
		and storage.items == before_items and storage.food_portions == before_portions
		and int(storage._unit_sequence) == before_sequence,
		label + " leaves Inventory, items, units, portions, and sequence unchanged.")
	_expect(inventory_signal_count[0] == 0 and city_signal_count[0] == 0,
		label + " emits no Inventory or City Storage signals.")


func _test_inventory_send_removed() -> void:
	var inventory_ui: InventoryUI = content.get_node("InventoryUI")
	inventory_ui.open_inventory()
	# The full raw-item fixture spans pages; find the retained bread through the food filter.
	for _index: int in range(inventory_ui.category_selector.categories.size()):
		if inventory_ui.category_selector.get_selected_category() == ItemEnums.ItemCategory.CONSUMABLE:
			break
		inventory_ui.category_selector.next_button.pressed.emit()
	await _wait_frames(3)
	var food_slot: ItemSlot
	for child: Node in inventory_ui.grid.get_children():
		if child is ItemSlot and child.get("_item_id") == "barley_bread":
			food_slot = child
			break
	_expect(food_slot != null, "Inventory exposes the reserved personal food item.")
	if food_slot != null:
		food_slot.pressed.emit()
		await _wait_frames(2)
		var options: OptionPanel = inventory_ui.active_option_panel
		_expect(is_instance_valid(options) and not options.send_button.is_visible_in_tree(),
			"Inventory no longer displays Send.")
		_expect(options.use_button.is_visible_in_tree() and options.drop_button.is_visible_in_tree(),
			"Inventory retains Use and Drop.")
		var before: Dictionary = Inventory.items.duplicate(true)
		food_slot.slot_deposit_requested.emit("barley_bread", 1, food_slot)
		inventory_ui._on_item_action_confirmed("send", "barley_bread", 1)
		_expect(Inventory.items == before and CityStockManager.food_supply == original_food_supply,
			"Right-click and stale Send confirmations cannot transfer or convert city supplies.")
	inventory_ui.close_inventory()
	await _wait_frames(2)


func _test_access_lifecycle() -> void:
	await _move_to_storage(area.global_position)
	player._unhandled_input(_action("interact"))
	await _wait_frames(2)
	var menu: CanvasLayer = _area_menu()
	var transfer := await _open_area_transfer(menu, "deposit")
	_stage_transfer_items(transfer, {"barley_bread": 1})
	var before: Dictionary = Inventory.items.duplicate(true)
	SceneTransition.is_transitioning = true
	transfer.confirm_button.pressed.emit()
	await _wait_frames(2)
	_expect(not is_instance_valid(_area_menu()) and not get_tree().paused and not player.can_move,
		"Revoked access closes the modal without overriding the scene-transition movement lock.")
	_expect(Inventory.items == before, "Transition interruption does not commit the staged transfer.")
	SceneTransition.is_transitioning = false
	player.can_move = true
	await _move_to_storage(area.global_position)
	var connections_before: int = storage.changed.get_connections().size()
	player._unhandled_input(_action("interact"))
	await _wait_frames(2)
	menu = _area_menu()
	await _assert_no_withdraw_ui(menu)
	transfer = await _open_area_transfer(menu, "deposit")
	area.free()
	area = null
	await _wait_frames(2)
	_expect(not is_instance_valid(menu) and not is_instance_valid(transfer) and not get_tree().paused and player.can_move,
		"Deleting the physical area removes its dialogs and restores world control.")
	_expect(storage.changed.get_connections().size() == connections_before,
		"Area removal disconnects temporary storage observers.")


func _hub_tabs_are_aligned() -> bool:
	var tabs: Array[Button] = [worker_control.status_tab_button, worker_control.tools_tab_button,
		worker_control.level_tab_button]
	var baseline: Rect2 = tabs[0].get_global_rect()
	for tab: Button in tabs:
		var rect: Rect2 = tab.get_global_rect()
		if not is_equal_approx(rect.position.y, baseline.position.y) or not is_equal_approx(rect.size.y, baseline.size.y):
			return false
	return true


func _check_area_storage_layout(view: Control) -> void:
	await _wait_frames(2)
	var viewport_bounds := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect(_rect_inside(view.get_global_rect(), viewport_bounds),
		"Unified City Storage fits inside the live viewport.")
	var context: Control = view.get_node("Margin/Content/ContextLabel")
	var categories: Control = view.get_node("Margin/Content/Header/Categories") as Control
	var grid: Control = view.get_node("Margin/Content/BagGrid") as Control
	var footer: Control = view.get_node("Margin/Content/Footer") as Control
	_expect(_rect_inside(context.get_global_rect(), viewport_bounds)
		and _rect_inside(categories.get_global_rect(), viewport_bounds)
		and _rect_inside(grid.get_global_rect(), viewport_bounds)
		and _rect_inside(footer.get_global_rect(), viewport_bounds),
		"Context, category, grid, and transfer controls fit inside the viewport.")
	_expect(not context.get_global_rect().intersects(categories.get_global_rect()),
		"Worker context does not overlap the category selector.")
	for node: Node in view.find_children("*", "Control", true, false):
		var control := node as Control
		if control != null and control.visible and control.size.x > 0.0 and control.size.y > 0.0:
			_expect(_rect_inside(control.get_global_rect(), viewport_bounds),
				"Visible City Storage control fits inside the live viewport: " + str(control.get_path()))


func _check_transfer_layout(transfer: ItemTransferUI) -> void:
	var viewport_bounds := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var window_control: Control = transfer.get_node("Root/Center/Window")
	_expect(_rect_inside(window_control.get_global_rect(), viewport_bounds),
		"Shared ItemTransferUI fits inside the live viewport.")


func _rect_inside(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x and rect.position.y >= bounds.position.y \
		and rect.end.x <= bounds.end.x and rect.end.y <= bounds.end.y


func _find_transfer_slot(transfer: ItemTransferUI, item_id: String) -> ItemSlot:
	if not is_instance_valid(transfer):
		return null
	for child: Node in transfer.grid_container.get_children():
		var slot := child as ItemSlot
		if slot != null and str(slot.get("_item_id")) == item_id:
			return slot
	return null


func _find_area_storage_slot(menu: CanvasLayer, item_id: String) -> ItemSlot:
	if not is_instance_valid(menu):
		return null
	var grid := menu.get("grid") as GridContainer
	if not is_instance_valid(grid):
		return null
	for child: Node in grid.get_children():
		var slot := child as ItemSlot
		if slot != null and str(slot.get("_item_id")) == item_id:
			return slot
	return null


func _find_unit_slot(unit_id: String) -> ItemSlot:
	for node: Node in worker_control.city_storage_list.find_children("*", "Button", true, false):
		var slot := node as ItemSlot
		if slot != null and str(slot.get_meta("unit_id", "")) == unit_id:
			return slot
	return null


func _find_unit_slot_by_item(item_id: String) -> ItemSlot:
	for node: Node in worker_control.city_storage_list.find_children("*", "Button", true, false):
		var slot := node as ItemSlot
		if slot != null and str(slot.get("_item_id")) == item_id:
			return slot
	return null


func _find_unallocated_unit(tool_id: String) -> String:
	for unit_id: String in storage.units:
		var unit: Dictionary = storage.units[unit_id]
		if str(unit.get("tool_id", "")) == tool_id and str(unit.get("worker_id", "")).is_empty():
			return unit_id
	return ""


func _unit_count(tool_id: String) -> int:
	return _unit_count_from(storage.units, tool_id)


func _unit_count_from(units: Dictionary, tool_id: String) -> int:
	var count: int = 0
	for unit: Dictionary in units.values():
		if str(unit.get("tool_id", "")) == tool_id:
			count += 1
	return count


func _inventory_quantity(item_id: String) -> int:
	return int(Inventory.items.get(item_id, 0))


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var capture_dir: String = OS.get_environment("TIP_CITY_SUPPLY_CAPTURE_DIR")
	if capture_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join(filename))


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _finish() -> void:
	if is_instance_valid(worker_control):
		worker_control.close()
	if is_instance_valid(content):
		content.free()
		content = null
	if is_instance_valid(home):
		home.free()
		home = null
	_restore_global_state()
	print("CityStorageSupplyFlowTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)


func _restore_global_state() -> void:
	if restored:
		return
	restored = true
	Inventory.items.clear()
	for item_id: String in original_inventory:
		Inventory.items[item_id] = original_inventory[item_id]
	Inventory.max_load = original_max_load
	CityStockManager.food_supply = original_food_supply
	CityStockManager.clothing_supply = original_clothing_supply
	SceneTransition.is_transitioning = original_transitioning
	Inventory.items_changed.emit()
	if is_instance_valid(original_storage):
		original_storage.units = original_storage_units.duplicate(true)
		original_storage.items = original_storage_items.duplicate(true)
		original_storage.food_portions = original_storage_portions.duplicate(true)
		original_storage._unit_sequence = original_storage_sequence
	else:
		var created_storage := WorkStateRuntime.get_node_or_null("CityToolStorage")
		if is_instance_valid(created_storage):
			created_storage.queue_free()
	if original_worker != null:
		WorkerDatabase.workers_by_id[TEST_WORKER_ID] = original_worker
	else:
		WorkerDatabase.workers_by_id.erase(TEST_WORKER_ID)
	if original_dismissed_worker != null:
		WorkerDatabase.dismissed_workers[TEST_WORKER_ID] = original_dismissed_worker
	else:
		WorkerDatabase.dismissed_workers.erase(TEST_WORKER_ID)
	if original_clock.has("day"):
		TimeComponentManager.current_day = int(original_clock.day)
		TimeComponentManager.current_hour = int(original_clock.hour)
		TimeComponentManager.current_minute = int(original_clock.minute)
		TimeComponentManager.current_weather = str(original_clock.weather)
		TimeComponentManager.is_paused = bool(original_clock.paused)
	get_tree().paused = original_tree_paused


func _exit_tree() -> void:
	_restore_global_state()
