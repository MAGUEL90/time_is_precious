extends Control

signal closed

@onready var source_option: OptionButton = $Center/Panel/Margin/Content/SourceRow/Source
@onready var destination_label: Label = $Center/Panel/Margin/Content/SourceRow/Destination
@onready var worker_option: OptionButton = $Center/Panel/Margin/Content/WorkerRow/Worker
@onready var item_option: OptionButton = $Center/Panel/Margin/Content/ItemRow/Item
@onready var quantity_spin: SpinBox = $Center/Panel/Margin/Content/QuantityRow/Quantity
@onready var route_label: Label = $Center/Panel/Margin/Content/Route
@onready var feedback_label: Label = $Center/Panel/Margin/Content/Feedback
@onready var start_button: Button = $Center/Panel/Margin/Content/Footer/Start
@onready var cancel_button: Button = $Center/Panel/Margin/Content/Footer/CancelRoute

var manager: Node
var initial_source_id: String = "city"
var workers: Array = []
var available_items: Dictionary = {}
var _feedback_override: String = ""
var _closing: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	source_option.add_item("Central City Storage")
	source_option.set_item_metadata(0, "city")
	source_option.add_item("City-Owned Annex")
	source_option.set_item_metadata(1, "annex")
	source_option.item_selected.connect(_on_source_selected)
	worker_option.item_selected.connect(_on_worker_selected)
	item_option.item_selected.connect(_on_item_selected)
	quantity_spin.value_changed.connect(_on_quantity_changed)
	start_button.pressed.connect(_start_route)
	cancel_button.pressed.connect(_cancel_route)
	$Center/Panel/Margin/Content/Footer/Back.pressed.connect(close)
	source_option.select(0)
	quantity_spin.min_value = 1
	quantity_spin.max_value = 3
	quantity_spin.step = 1

func open(transport_manager: Node, source_id: String) -> void:
	manager = transport_manager
	initial_source_id = "annex" if source_id == "annex" else "city"
	_feedback_override = ""
	visible = true
	if is_instance_valid(manager) and manager.has_signal("changed") and not manager.is_connected("changed", _on_manager_changed):
		manager.connect("changed", _on_manager_changed, CONNECT_DEFERRED)
	var initial_index: int = 1 if initial_source_id == "annex" else 0
	source_option.select(initial_index)
	_refresh_all()

func close() -> void:
	if _closing:
		return
	_closing = true
	visible = false
	_disconnect_manager()
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	_disconnect_manager()

func _disconnect_manager() -> void:
	if is_instance_valid(manager) and manager.has_signal("changed") and manager.is_connected("changed", _on_manager_changed):
		manager.disconnect("changed", _on_manager_changed)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()

func _source_id() -> String:
	if source_option.selected < 0:
		return initial_source_id
	return str(source_option.get_item_metadata(source_option.selected))

func _destination_id() -> String:
	return "annex" if _source_id() == "city" else "city"

func _on_source_selected(_index: int) -> void:
	_feedback_override = ""
	_refresh_all()

func _on_manager_changed() -> void:
	_refresh_all()

func _refresh_all() -> void:
	if not is_instance_valid(manager):
		workers.clear()
		available_items.clear()
		_refresh_worker_options()
		_refresh_item_options()
		_refresh_state("Transport service is unavailable.")
		return
	destination_label.text = "To: Annex" if _destination_id() == "annex" else "To: Central"
	_refresh_worker_options()
	_refresh_item_options()
	_refresh_route()
	_refresh_state()

func _refresh_worker_options() -> void:
	var selected_worker_id: String = _selected_worker_id()
	workers.clear()
	worker_option.clear()
	if is_instance_valid(manager) and manager.has_method("eligible_workers"):
		var result: Variant = manager.call("eligible_workers")
		if result is Array:
			workers = result
	for worker_value: Variant in workers:
		var worker_id: String = _worker_id(worker_value)
		if worker_id.is_empty():
			continue
		var worker_name: String = _worker_name(worker_value, worker_id)
		worker_option.add_item(worker_name)
		worker_option.set_item_metadata(worker_option.item_count - 1, worker_id)
	var selected_index: int = _find_option_metadata(worker_option, selected_worker_id)
	if selected_index < 0 and worker_option.item_count > 0:
		selected_index = 0
	worker_option.select(selected_index)

func _refresh_item_options() -> void:
	var selected_item_id: String = _selected_item_id()
	item_option.clear()
	available_items.clear()
	if is_instance_valid(manager) and manager.has_method("available_items"):
		var result: Variant = manager.call("available_items", _source_id())
		if result is Dictionary:
			available_items = result
	var item_ids: Array[String] = []
	for item_id_value: Variant in available_items.keys():
		var item_id: String = str(item_id_value)
		if int(available_items.get(item_id_value, 0)) > 0:
			item_ids.append(item_id)
	item_ids.sort()
	for item_id: String in item_ids:
		var amount: int = int(available_items.get(item_id, 0))
		item_option.add_item("%s  x%d" % [_item_name(item_id), amount])
		item_option.set_item_metadata(item_option.item_count - 1, item_id)
	var selected_index: int = _find_option_metadata(item_option, selected_item_id)
	if selected_index < 0 and item_option.item_count > 0:
		selected_index = 0
	item_option.select(selected_index)
	_update_quantity_bounds()

func _refresh_route() -> void:
	var route: Dictionary = _current_route()
	if route.is_empty():
		route_label.text = "No active route"
		cancel_button.disabled = true
		return
	var worker_id: String = str(route.get("worker_id", ""))
	var source: String = _location_name(str(route.get("source", route.get("source_id", ""))))
	var destination: String = _location_name(str(route.get("destination", route.get("destination_id", ""))))
	var item_id: String = str(route.get("item_id", route.get("cargo_item_id", "")))
	var quantity: int = int(route.get("quantity", route.get("cargo_quantity", route.get("remaining_quantity", 0))))
	var status: String = _phase_label(str(route.get("phase", route.get("status", route.get("state", "In transit")))))
	var first_line: String = "Active: %s" % status
	if not source.is_empty() or not destination.is_empty():
		first_line += " | %s→%s" % [source, destination]
	var second_line: String = "%s x%d" % [_item_name(item_id), quantity] if not item_id.is_empty() else "Cargo in transit"
	if not worker_id.is_empty():
		second_line += " | %s" % _worker_name_by_id(worker_id)
	route_label.text = first_line + "\n" + second_line
	cancel_button.disabled = false

func _refresh_state(custom_message: String = "") -> void:
	var route_active: bool = not _current_route().is_empty()
	var stock: int = _selected_stock()
	var has_worker: bool = not _selected_worker_id().is_empty()
	var has_item: bool = not _selected_item_id().is_empty()
	start_button.disabled = route_active or not has_worker or not has_item or stock <= 0
	worker_option.disabled = route_active or workers.is_empty()
	item_option.disabled = route_active or item_option.item_count == 0
	source_option.disabled = route_active
	quantity_spin.editable = not route_active and stock > 0
	cancel_button.disabled = not route_active
	if not custom_message.is_empty():
		feedback_label.text = custom_message
	elif not _feedback_override.is_empty():
		feedback_label.text = _feedback_override
	elif route_active:
		feedback_label.text = "Cancel Route returns the load to its source."
	elif workers.is_empty():
		feedback_label.text = "No worker is ready. Check shift and cart."
	elif stock <= 0:
		feedback_label.text = "No counted stock is available here."
	else:
		feedback_label.text = "Choose a worker, item and quantity (up to 3)."

func _update_quantity_bounds() -> void:
	var stock: int = _selected_stock()
	var maximum: int = mini(3, stock)
	quantity_spin.max_value = maxi(maximum, 1)
	quantity_spin.value = clampi(int(quantity_spin.value), 1, maxi(maximum, 1))
	quantity_spin.editable = stock > 0 and _current_route().is_empty()

func _on_item_selected(_index: int) -> void:
	_feedback_override = ""
	_update_quantity_bounds()
	_refresh_state()

func _on_worker_selected(_index: int) -> void:
	_feedback_override = ""
	_refresh_state()

func _on_quantity_changed(_value: float) -> void:
	_feedback_override = ""
	_refresh_state()

func _start_route() -> void:
	if not is_instance_valid(manager) or not manager.has_method("start"):
		_refresh_state("Transport service is unavailable.")
		return
	var worker_id: String = _selected_worker_id()
	if worker_id.is_empty():
		_refresh_state("No eligible worker. Check shift and cart.")
		return
	var item_id: String = _selected_item_id()
	var quantity: int = int(quantity_spin.value)
	var stock: int = _selected_stock()
	if item_id.is_empty() or stock <= 0:
		_refresh_state("No counted stock is available at this source.")
		return
	if quantity < 1 or quantity > 3 or quantity > stock:
		_refresh_state("Choose a quantity from 1 to 3 within available stock.")
		return
	var source: String = _source_id()
	if bool(manager.call("start", worker_id, source, item_id, quantity)):
		_feedback_override = "Route started."
		_refresh_all()
	else:
		_refresh_all()
		if _find_option_metadata(worker_option, worker_id) < 0:
			_feedback_override = "Worker is unavailable. Check shift and cart."
		else:
			_feedback_override = "Could not start. Check stock, destination space and route."
		_refresh_state()

func _cancel_route() -> void:
	if not is_instance_valid(manager) or not manager.has_method("cancel"):
		_refresh_state("No active route can be cancelled.")
		return
	if bool(manager.call("cancel")):
		_feedback_override = "Route cancelled safely; cargo is returning to its source."
		_refresh_all()
	else:
		_refresh_all()
		_feedback_override = "The active route could not be cancelled."
		_refresh_state()

func _current_route() -> Dictionary:
	if not is_instance_valid(manager):
		return {}
	var route_value: Variant = manager.get("route")
	return route_value if route_value is Dictionary else {}

func _selected_worker_id() -> String:
	if worker_option.selected < 0:
		return ""
	return str(worker_option.get_item_metadata(worker_option.selected))

func _selected_item_id() -> String:
	if item_option.selected < 0:
		return ""
	return str(item_option.get_item_metadata(item_option.selected))

func _selected_stock() -> int:
	var item_id: String = _selected_item_id()
	return int(available_items.get(item_id, 0)) if not item_id.is_empty() else 0

func _worker_id(worker_value: Variant) -> String:
	if worker_value is Dictionary:
		return str(worker_value.get("worker_id", worker_value.get("id", "")))
	if worker_value is Object:
		return str(worker_value.get("worker_id"))
	return ""

func _worker_name(worker_value: Variant, fallback: String) -> String:
	var value: String = ""
	if worker_value is Dictionary:
		value = str(worker_value.get("display_name", worker_value.get("name", "")))
	elif worker_value is Object:
		value = str(worker_value.get("display_name"))
	return value if not value.is_empty() else fallback

func _worker_name_by_id(worker_id: String) -> String:
	for worker_value: Variant in workers:
		if _worker_id(worker_value) == worker_id:
			return _worker_name(worker_value, worker_id)
	return worker_id

func _item_name(item_id: String) -> String:
	var item: ItemData = ItemDatabase.get_item_data(item_id)
	return item.display_name if item != null else item_id.replace("_", " ").capitalize()

func _location_name(location_id: String) -> String:
	if location_id == "city":
		return "Central"
	if location_id == "annex":
		return "Annex"
	return location_id

func _phase_label(phase: String) -> String:
	var normalized: String = phase.replace("_", " ").strip_edges()
	return normalized.capitalize() if not normalized.is_empty() else "In transit"

func _find_option_metadata(option: OptionButton, value: String) -> int:
	if value.is_empty():
		return -1
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			return index
	return -1
