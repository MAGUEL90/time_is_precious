class_name WorkshopProductionUI
extends CanvasLayer

signal work_order_selected(
	work_order_id: String,
	work_order_type: int
)
signal back_requested()
signal cancelled()

const WORK_ORDER_CARD_SCENE: PackedScene = preload("res://scenes/ui/work_order_card/work_order_card.tscn")

@onready var work_order_grid: GridContainer = $Root/Center/TextureWindow/Margin/MainVBox/Body/WorkOrderGrid
@onready var requirement_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/RequirementLabel
@onready var back_button: Button = $Root/Center/TextureWindow/Margin/MainVBox/Footer/BackButton
@onready var next_button: Button = $Root/Center/TextureWindow/Margin/MainVBox/Footer/NextButton
@onready var close_button: BaseButton = $Root/Center/TextureWindow/Margin/MainVBox/Header/CloseButton
@onready var production_info_panel: ProductionInfoPanel = ($Root/ProductionInfoPanel)
@onready var production_window: NinePatchRect = $Root/Center/TextureWindow
@onready var process_confirm_overlay: Control = $Root/ProcessConfirmOverlay
@onready var process_confirm_panel: ActionChoicePanel = (
	$Root/ProcessConfirmOverlay/Center/ProcessConfirmPanel
)

var selected_card: WorkOrderCard = null
var selected_process_availability: Dictionary = {}
var current_workshop: WorkShop = null
var awaiting_process_confirmation: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	process_confirm_panel.primary_selected.connect(
		_on_process_confirmation_started
	)
	process_confirm_panel.secondary_selected.connect(
		_on_process_confirmation_canceled
	)
	process_confirm_panel.cancelled.connect(
		_on_process_confirmation_canceled
	)

	_clear_selection()

func open_menu(workshop: WorkShop) -> void:
	current_workshop = workshop
	_rebuild_work_order_cards()
	visible = true
	get_tree().paused = true
	_clear_selection()

func _on_card_pressed(card: WorkOrderCard) -> void:
	if card.progression_locked:
		return

	selected_card = card

	for child in work_order_grid.get_children():
		if child is WorkOrderCard:
			var other_card := child as WorkOrderCard
			other_card.set_selected(other_card == card)

	selected_process_availability.clear()
	production_info_panel.clear_details()

	if card.work_order_type == WorkOrderCard.WorkOrderType.JOB:
		requirement_label.text = ""
		next_button.disabled = false
		return

	var availability: Dictionary = (ProcessManager.get_process_availability(card.work_order_id))
	selected_process_availability = availability.duplicate(true)
	requirement_label.text = _get_process_status(availability)
	next_button.disabled = not bool(availability.get("can_start", false))


func _on_card_details_requested(card: WorkOrderCard) -> void:
	if card.work_order_type == WorkOrderCard.WorkOrderType.JOB:
		production_info_panel.display_job(card.card_title)
	else:
		production_info_panel.display_process(
			ProcessManager.get_process_availability(card.work_order_id)
		)
	call_deferred("_position_production_info_panel")

func _get_process_status(availability: Dictionary) -> String:
	if not bool(availability.get("registered", false)):
		return "Process unavailable."

	if not bool(availability.get("station_ready", false)):
		var station_id: String = str(
			availability.get("required_station_id", "")
		)
		var station_name: String = station_id.replace("_", " ").capitalize()
		return "Build %s first." % station_name

	if bool(availability.get("blocked_by_pending_output", false)):
		return "Pending Delivery blocks new work. Free storage space."

	var item_id: String = str(availability.get("input_item_id", ""))
	var item_name: String = _get_item_display_name(item_id)
	var available: int = int(availability.get("available_quantity", 0))
	var free_slots: int = int(availability.get("free_slots", 0))
	var batch_size: int = int(availability.get("batch_size", 1))
	var startable_quantity: int = int(
		availability.get("startable_quantity", 0)
	)

	if available <= 0:
		return "Needs %s in Workshop storage." % item_name

	if free_slots <= 0:
		return "No free station slots."

	if startable_quantity <= 0:
		return "Needs %s x%d per full batch. Free: %d." % [
			item_name,
			batch_size,
			available
		]

	return ""

func _get_item_display_name(item_id) -> String:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)

	if item_data == null:
		return item_id.capitalize()

	return item_data.display_name

func _on_next_pressed() -> void:
	if selected_card == null:
		return

	if selected_card.work_order_type == WorkOrderCard.WorkOrderType.PROCESS:
		var availability: Dictionary = (
			ProcessManager.get_process_availability(
				selected_card.work_order_id
			)
		)
		selected_process_availability = availability.duplicate(true)
		requirement_label.text = _get_process_status(availability)
		if not bool(availability.get("can_start", false)):
			next_button.disabled = true
			return
		_open_process_confirmation(availability)
		return

	_emit_selected_work_order()

func _emit_selected_work_order() -> void:
	if selected_card == null:
		return

	visible = false
	get_tree().paused = false
	work_order_selected.emit(
		selected_card.work_order_id,
		int(selected_card.work_order_type)
	)
	queue_free()

func _open_process_confirmation(availability: Dictionary) -> void:
	awaiting_process_confirmation = true
	production_info_panel.clear_details()
	process_confirm_panel.setup(
		_get_process_confirmation_message(availability),
		"Start",
		"Back",
		true
	)
	process_confirm_overlay.show()
	process_confirm_panel.primary_button.grab_focus()

func _get_process_confirmation_message(availability: Dictionary) -> String:
	var quantity: int = maxi(
		int(availability.get("startable_quantity", 0)),
		0
	)
	var input_name: String = _get_item_display_name(
		str(availability.get("input_item_id", ""))
	)
	var output_name: String = _get_item_display_name(
		str(availability.get("output_item_id", ""))
	)
	var fee_amount: int = maxi(
		int(availability.get("station_fee_amount", 0)),
		0
	)
	var fee_text: String = "-"
	if fee_amount > 0:
		var currency_id: String = str(
			availability.get(
				"station_fee_currency_item_id",
				""
			)
		)
		fee_text = "%d %s" % [
			fee_amount,
			_get_item_display_name(currency_id)
		]

	return "Start %s?\nInput: %s x%d\nOutput: %s x%d\nWorkshop Rent: %s" % [
		str(availability.get("process_display_name", "Process")),
		input_name,
		quantity,
		output_name,
		quantity,
		fee_text
	]

func _on_process_confirmation_started() -> void:
	if not awaiting_process_confirmation:
		return
	awaiting_process_confirmation = false
	process_confirm_overlay.hide()
	_emit_selected_work_order()

func _on_process_confirmation_canceled() -> void:
	awaiting_process_confirmation = false
	process_confirm_overlay.hide()

func _on_back_pressed() -> void:
	visible = false
	get_tree().paused = false
	back_requested.emit()
	queue_free()

func _on_close_pressed() -> void:
	visible = false
	get_tree().paused = false
	cancelled.emit()
	queue_free()

func _clear_selection() -> void:
	selected_process_availability.clear()
	production_info_panel.clear_details()
	selected_card = null
	next_button.disabled = true
	requirement_label.text = ""
	awaiting_process_confirmation = false
	process_confirm_overlay.hide()

	for child in work_order_grid.get_children():
		if child is WorkOrderCard:
			(child as WorkOrderCard).set_selected(false)

func _refresh_details_preview() -> void:
	var should_show: bool = selected_card != null and not awaiting_process_confirmation

	if not should_show:
		production_info_panel.clear_details()
		return

	if (selected_card.work_order_type == WorkOrderCard.WorkOrderType.JOB):
		production_info_panel.display_job(selected_card.card_title)
	else:
		if selected_process_availability.is_empty():
			production_info_panel.clear_details()
			return

		production_info_panel.display_process(selected_process_availability)

	call_deferred("_position_production_info_panel")

func _position_production_info_panel() -> void:
	if not production_info_panel.visible:
		return

	var window_rect: Rect2 = (production_window.get_global_rect())
	var panel_size: Vector2 = production_info_panel.size
	var panel_position: Vector2 = Vector2(window_rect.position + (window_rect.size - panel_size) * 0.5)
	production_info_panel.global_position = (panel_position.round())

func _rebuild_work_order_cards() -> void:
	for child in work_order_grid.get_children():
		if child.name == "LockedCard":
			continue
		work_order_grid.remove_child(child)
		child.queue_free()

	if current_workshop == null:
		return

	for job_data in current_workshop.available_jobs:
		if job_data == null:
			continue
		var title: String = job_data.short_name.strip_edges()
		if title.is_empty():
			title = job_data.display_name

		_add_work_order_card(
			job_data.job_id,
			WorkOrderCard.WorkOrderType.JOB,
			title,
			_get_job_card_icon(job_data)
		)

	for process_data in current_workshop.available_processes:
		if process_data == null:
			continue

		var title: String = process_data.short_name.strip_edges()
		if title.is_empty():
			title = process_data.display_name

		_add_work_order_card(
			process_data.process_id,
			WorkOrderCard.WorkOrderType.PROCESS,
			title,
			_get_process_card_icon(process_data),
			_is_process_progression_locked(process_data),
			_get_process_lock_reason(process_data)
		)

func _add_work_order_card(
	work_order_id: String,
	work_order_type: int,
	card_title: String,
	card_icon: Texture2D,
	progression_locked: bool = false,
	_locked_reason: String = ""
) -> void:
	var card: WorkOrderCard = (
		WORK_ORDER_CARD_SCENE.instantiate() as WorkOrderCard
	)
	if card == null:
		return

	card.work_order_id = work_order_id
	card.work_order_type = work_order_type
	card.card_title = (
		card_title
		if not card_title.is_empty()
		else work_order_id.replace("_", " ").capitalize()
	)
	card.card_icon = card_icon
	card.progression_locked = progression_locked
	work_order_grid.add_child(card)

	var locked_card: Node = work_order_grid.get_node_or_null("LockedCard")
	if locked_card != null:
		work_order_grid.move_child(card, locked_card.get_index())
	card.pressed.connect(_on_card_pressed.bind(card))
	card.details_requested.connect(_on_card_details_requested.bind(card))

func _is_process_progression_locked(process_data: ProcessData) -> bool:
	var station_id: String = process_data.required_station_id
	return (
		WorkshopFacilityManager.has_facility(station_id)
		and not WorkshopFacilityManager.is_facility_built(station_id)
	)

func _get_process_lock_reason(process_data: ProcessData) -> String:
	if not _is_process_progression_locked(process_data):
		return ""
	var station_name: String = process_data.required_station_id.replace(
		"_",
		" "
	).capitalize()
	return "Build %s first." % station_name

func _get_job_card_icon(job_data: JobData) -> Texture2D:
	if job_data.icon != null:
		return job_data.icon

	for output_id_value in job_data.outputs.keys():
		var item_data: ItemData = ItemDatabase.get_item_data(str(output_id_value))
		if item_data != null and item_data.icon != null:
			return item_data.icon
	return null

func _get_process_card_icon(process_data: ProcessData) -> Texture2D:
	if process_data.icon != null:
		return process_data.icon

	return _get_item_icon(process_data.output_item_id)

func _get_item_icon(item_id: String) -> Texture2D:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return null

	return item_data.icon
