class_name WorkshopBuildUI extends CanvasLayer

signal back_requested()
signal cancelled()

const READY_COLOR: Color = Color(0.78, 1.0, 0.72, 1.0)
const MISSING_COLOR: Color = Color(1.0, 0.82, 0.78, 1.0)

@onready var close_button: BaseButton = (
	$Root/Center/TextureWindow/CloseButton
)
@onready var selection_page: VBoxContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/SelectionPage
)
@onready var facility_list: VBoxContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/SelectionPage/FacilityList
)
@onready var selection_back_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/SelectionPage/Footer/BackButton
)
@onready var details_page: VBoxContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage
)
@onready var facility_name_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/FacilityRow/FacilityNameLabel
)
@onready var level_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/FacilityRow/LevelLabel
)
@onready var current_slots_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/SlotRow/CurrentSlotsLabel
)
@onready var slot_arrow: TextureRect = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/SlotRow/SlotArrow
)
@onready var target_slots_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/SlotRow/TargetSlotsLabel
)
@onready var requirements_list: VBoxContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/RequirementsList
)
@onready var feedback_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/FeedbackLabel
)
@onready var contribute_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/ContributionActions/ContributeButton
)
@onready var refund_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/ContributionActions/RefundButton
)
@onready var details_back_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/Footer/BackButton
)
@onready var build_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/DetailsPage/Footer/BuildButton
)
@onready var confirm_overlay: Control = $Root/ConfirmOverlay
@onready var confirm_panel: ActionChoicePanel = (
	$Root/ConfirmOverlay/Center/ConfirmPanel
)

var current_facility_id: String = ""
var current_preview: Dictionary = {}
var pending_action: String = ""
var pending_quote: Dictionary = {}
var _inventory_refresh_pending: bool = false


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	selection_back_button.pressed.connect(_exit_to_workshop_menu)
	details_back_button.pressed.connect(_show_facility_selection)
	build_button.pressed.connect(_on_build_pressed)
	contribute_button.pressed.connect(_on_contribute_pressed)
	refund_button.pressed.connect(_on_refund_pressed)
	confirm_panel.primary_selected.connect(_on_build_confirmed)
	confirm_panel.secondary_selected.connect(
		_on_build_confirmation_cancelled
	)
	confirm_panel.cancelled.connect(_on_build_confirmation_cancelled)
	if not Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.connect(_on_inventory_items_changed)
	if not WorkshopFacilityManager.facility_level_changed.is_connected(_on_facility_level_changed):
		WorkshopFacilityManager.facility_level_changed.connect(_on_facility_level_changed)
	if not WorkshopFacilityManager.transaction_finished.is_connected(_on_facility_transaction_finished):
		WorkshopFacilityManager.transaction_finished.connect(_on_facility_transaction_finished)
	confirm_panel.message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	confirm_overlay.hide()

func _exit_tree() -> void:
	if Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.disconnect(_on_inventory_items_changed)
	if WorkshopFacilityManager.facility_level_changed.is_connected(_on_facility_level_changed):
		WorkshopFacilityManager.facility_level_changed.disconnect(_on_facility_level_changed)
	if WorkshopFacilityManager.transaction_finished.is_connected(_on_facility_transaction_finished):
		WorkshopFacilityManager.transaction_finished.disconnect(_on_facility_transaction_finished)

func open_menu(facility_id: String = "") -> void:
	get_tree().paused = true
	visible = true
	if facility_id.is_empty():
		_show_facility_selection()
	else:
		_show_facility_details(facility_id)

func _show_facility_selection() -> void:
	current_facility_id = ""
	current_preview.clear()
	pending_action = ""
	pending_quote.clear()
	confirm_overlay.hide()
	details_page.hide()
	selection_page.show()
	_rebuild_facility_list()

func _rebuild_facility_list() -> void:
	for child in facility_list.get_children():
		facility_list.remove_child(child)
		child.queue_free()

	var facility_ids: Array[String] = (
		WorkshopFacilityManager.get_facility_ids()
	)
	if facility_ids.is_empty():
		var empty_label := Label.new()
		empty_label.theme_type_variation = &"HudLabelShortcut"
		empty_label.add_theme_font_size_override("font_size", 6)
		empty_label.text = "No facilities available."
		facility_list.add_child(empty_label)
		return

	for facility_id in facility_ids:
		_add_facility_button(
			facility_id,
			WorkshopFacilityManager.get_facility_state(facility_id)
		)

func _add_facility_button(
	facility_id: String,
	state: Dictionary
) -> void:
	var facility_button := Button.new()
	facility_button.custom_minimum_size = Vector2(0, 28)
	facility_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facility_button.focus_mode = Control.FOCUS_NONE
	facility_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	facility_button.theme_type_variation = &"HudShortcutButton"
	facility_button.add_theme_font_size_override("font_size", 6)
	facility_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	facility_button.icon = state.get("icon") as Texture2D
	facility_button.expand_icon = false
	facility_button.text = "%s     Level %d/%d" % [
		str(state.get("display_name", facility_id)),
		int(state.get("level", 0)),
		int(state.get("max_level", 0))
	]
	facility_button.pressed.connect(
		_show_facility_details.bind(facility_id)
	)
	facility_list.add_child(facility_button)

func _show_facility_details(facility_id: String) -> void:
	current_facility_id = facility_id
	selection_page.hide()
	details_page.show()
	_refresh_facility()

func _refresh_facility(update_feedback: bool = true) -> void:
	current_preview = WorkshopFacilityManager.get_facility_upgrade_preview(
		current_facility_id
	)
	if not bool(current_preview.get("valid", false)):
		facility_name_label.text = "Unknown Facility"
		level_label.text = ""
		current_slots_label.text = "Slots: -"
		slot_arrow.hide()
		target_slots_label.hide()
		build_button.disabled = true
		contribute_button.hide()
		refund_button.hide()
		_rebuild_requirements({})
		_set_feedback("Facility unavailable.", true)
		return

	var current_level: int = int(current_preview.get("current_level", 0))
	var maximum_level: int = int(current_preview.get("max_level", 0))
	var at_max_level: bool = bool(current_preview.get("at_max_level", false))
	var transaction_busy: bool = bool(current_preview.get("transaction_busy", false))
	var contributed_items: Dictionary = current_preview.get(
		"contributed_items",
		{}
	)
	facility_name_label.text = str(
		current_preview.get("display_name", current_facility_id)
	)
	level_label.text = "Level %d/%d" % [current_level, maximum_level]
	current_slots_label.text = "Slots: %d" % int(
		current_preview.get("current_slots", 0)
	)
	slot_arrow.visible = not at_max_level
	target_slots_label.visible = not at_max_level
	target_slots_label.text = str(
		current_preview.get("target_slots", 0)
	)

	_rebuild_requirements(current_preview.get("requirements", {}))
	build_button.text = (
		"Max Level"
		if at_max_level
		else "Build" if current_level == 0 else "Upgrade"
	)
	build_button.disabled = not bool(
		current_preview.get("can_upgrade", false)
	)
	contribute_button.visible = bool(current_preview.get("can_contribute", false))
	contribute_button.disabled = transaction_busy
	refund_button.visible = not contributed_items.is_empty()
	refund_button.disabled = (
		transaction_busy
		or not bool(current_preview.get("can_refund", false))
	)

	if not update_feedback:
		return
	if at_max_level:
		_set_feedback("Max level reached.", false)
	elif transaction_busy:
		_set_feedback("A transaction is in progress.", true)
	elif bool(current_preview.get("can_contribute", false)):
		_set_feedback("Contribute available Inventory materials to continue.", false)
	elif not contributed_items.is_empty() and not bool(current_preview.get("can_refund", false)):
		_set_feedback("No safe refund batch fits. Free Inventory capacity and retry.", true)
	elif build_button.disabled and not contributed_items.is_empty():
		_set_feedback("Committed materials are saved. Gather more or refund them.", false)
	elif build_button.disabled:
		_set_feedback("Missing materials in Inventory.", true)
	else:
		_set_feedback("Materials ready from Inventory and contributions.", false)

func _on_inventory_items_changed() -> void:
	if not visible or current_facility_id.is_empty():
		return
	if not Inventory._bulk_transaction_in_progress:
		_inventory_refresh_pending = false
		_refresh_facility()
		return
	if not _inventory_refresh_pending:
		_inventory_refresh_pending = true
		call_deferred("_refresh_after_inventory_transaction")

func _refresh_after_inventory_transaction() -> void:
	_inventory_refresh_pending = false
	if visible and not current_facility_id.is_empty():
		_refresh_facility()

func _on_facility_level_changed(
	facility_id: String,
	_level: int,
	_station_slots: int
) -> void:
	if visible and facility_id == current_facility_id:
		_refresh_facility()

func _on_facility_transaction_finished() -> void:
	if visible and not current_facility_id.is_empty():
		_refresh_facility()

func _rebuild_requirements(requirements: Dictionary) -> void:
	for child in requirements_list.get_children():
		requirements_list.remove_child(child)
		child.queue_free()

	if requirements.is_empty():
		var empty_label := Label.new()
		empty_label.theme_type_variation = &"HudLabelShortcut"
		empty_label.add_theme_font_size_override("font_size", 6)
		empty_label.text = "No further materials required."
		requirements_list.add_child(empty_label)
		return

	var available_items: Dictionary = current_preview.get(
		"available_items",
		{}
	)
	var contributed_items: Dictionary = current_preview.get(
		"contributed_items",
		{}
	)
	for item_id_value in requirements.keys():
		var item_id: String = str(item_id_value)
		var required_quantity: int = int(requirements[item_id_value])
		var available_quantity: int = int(
			available_items.get(item_id, 0)
		)
		_add_requirement_row(
			item_id,
			available_quantity,
			int(contributed_items.get(item_id, 0)),
			required_quantity
		)

func _add_requirement_row(
	item_id: String,
	available_quantity: int,
	contributed_quantity: int,
	required_quantity: int
) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 20)
	row.add_theme_constant_override("separation", 3)
	requirements_list.add_child(row)

	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	var icon_frame := Button.new()
	icon_frame.custom_minimum_size = Vector2(20, 20)
	icon_frame.focus_mode = Control.FOCUS_NONE
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_frame.theme_type_variation = &"WorkshopSquareButton16"
	icon_frame.expand_icon = false
	if item_data != null:
		icon_frame.icon = item_data.icon
	row.add_child(icon_frame)

	var item_label := Label.new()
	item_label.custom_minimum_size = Vector2(0, 20)
	item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_label.theme_type_variation = &"HudLabelShortcut"
	item_label.add_theme_font_size_override("font_size", 6)
	item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var display_name: String = item_id.replace("_", " ").capitalize()
	if item_data != null:
		display_name = item_data.display_name
	item_label.text = "%s  %d+%d/%d" % [
		display_name,
		available_quantity,
		contributed_quantity,
		required_quantity
	]
	item_label.tooltip_text = "Inventory + committed materials / total required"
	item_label.add_theme_color_override(
		"font_color",
		READY_COLOR
		if available_quantity + contributed_quantity >= required_quantity
		else MISSING_COLOR
	)
	row.add_child(item_label)

func _set_feedback(message: String, is_error: bool) -> void:
	feedback_label.text = message
	feedback_label.add_theme_color_override(
		"font_color",
		MISSING_COLOR if is_error else READY_COLOR
	)

func _on_build_pressed() -> void:
	if not bool(current_preview.get("can_upgrade", false)):
		return

	var action_name: String = (
		"Build"
		if int(current_preview.get("current_level", 0)) == 0
		else "Upgrade"
	)
	_capture_pending_quote("build")
	confirm_panel.setup(
		"%s %s to Lv.%d?" % [
			action_name,
			str(current_preview.get("display_name", current_facility_id)),
			int(current_preview.get("target_level", 0))
		],
		action_name,
		"Cancel"
	)
	confirm_overlay.show()

func _on_contribute_pressed() -> void:
	if not bool(current_preview.get("can_contribute", false)):
		return
	var contribution_plan: Dictionary = current_preview.get(
		"contribution_plan",
		{}
	)
	_capture_pending_quote("contribute")
	confirm_panel.setup(
		"Move %s from Inventory into saved contributions for level %d? Refunds need enough bag space." % [
			_format_materials(contribution_plan),
			int(current_preview.get("target_level", 0))
		],
		"Contribute",
		"Cancel"
	)
	confirm_overlay.show()

func _format_materials(items: Dictionary) -> String:
	var material_names: Array[String] = []
	for item_id_value: Variant in items.keys():
		var item_id: String = str(item_id_value)
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		var display_name: String = item_id.replace("_", " ").capitalize()
		if item_data != null:
			display_name = item_data.display_name
		material_names.append("%s x%d" % [
			display_name,
			int(items[item_id_value])
		])
	material_names.sort()
	return ", ".join(PackedStringArray(material_names))

func _capture_pending_quote(action: String) -> void:
	var requirements: Dictionary = current_preview.get("requirements", {})
	var contributed_items: Dictionary = current_preview.get("contributed_items", {})
	var remaining_requirements: Dictionary = current_preview.get("remaining_requirements", {})
	var contribution_plan: Dictionary = current_preview.get("contribution_plan", {})
	var refund_plan: Dictionary = current_preview.get("refund_plan", {})
	pending_action = action
	pending_quote = {
		"facility_id": current_facility_id,
		"target_level": int(current_preview.get("target_level", 0)),
		"requirements": requirements.duplicate(true),
		"contributed_items": contributed_items.duplicate(true),
		"remaining_requirements": remaining_requirements.duplicate(true),
		"contribution_plan": contribution_plan.duplicate(true),
		"refund_plan": refund_plan.duplicate(true),
		"refund_capacity": float(current_preview.get("refund_capacity", 0.0)),
		"inventory_items": Inventory.items.duplicate(true)
	}

func _pending_quote_matches(action: String, quote: Dictionary) -> bool:
	var quoted_facility_id: String = str(quote.get("facility_id", ""))
	if quoted_facility_id.is_empty() or quoted_facility_id != current_facility_id:
		return false
	var latest_preview: Dictionary = WorkshopFacilityManager.get_facility_upgrade_preview(
		quoted_facility_id
	)
	if (
		not bool(latest_preview.get("valid", false))
		or bool(latest_preview.get("transaction_busy", false))
		or int(latest_preview.get("target_level", 0)) != int(quote.get("target_level", 0))
	):
		return false
	match action:
		"build":
			return (
				bool(latest_preview.get("can_upgrade", false))
				and latest_preview.get("requirements", {}) == quote.get("requirements", {})
				and latest_preview.get("contributed_items", {}) == quote.get("contributed_items", {})
				and latest_preview.get("remaining_requirements", {}) == quote.get("remaining_requirements", {})
			)
		"contribute":
			return (
				bool(latest_preview.get("can_contribute", false))
				and latest_preview.get("contribution_plan", {}) == quote.get("contribution_plan", {})
			)
		"refund":
			return (
				bool(latest_preview.get("can_refund", false))
				and latest_preview.get("contributed_items", {}) == quote.get("contributed_items", {})
				and latest_preview.get("refund_plan", {}) == quote.get("refund_plan", {})
				and (
					float(latest_preview.get("refund_capacity", 0.0))
					== float(quote.get("refund_capacity", 0.0))
				)
				and Inventory.items == quote.get("inventory_items", {})
			)
	return false

func _on_refund_pressed() -> void:
	if not bool(current_preview.get("can_refund", false)):
		return
	var refund_plan: Dictionary = current_preview.get("refund_plan", {})
	var refund_remaining: Dictionary = current_preview.get("refund_remaining", {})
	var message: String = "Return %s to Inventory this trip?" % _format_materials(refund_plan)
	if not refund_remaining.is_empty():
		message += " Remaining committed for this level: %s. Those materials stay saved." % _format_materials(refund_remaining)
	_capture_pending_quote("refund")
	confirm_panel.setup(
		message,
		"Refund",
		"Cancel"
	)
	confirm_overlay.show()

func _on_build_confirmed() -> void:
	confirm_overlay.hide()
	var action: String = pending_action
	var quote: Dictionary = pending_quote.duplicate(true)
	pending_action = ""
	pending_quote.clear()
	if not _pending_quote_matches(action, quote):
		_refresh_facility(false)
		_set_feedback("Materials or upgrade target changed. Review the current quote.", true)
		return
	var result: Dictionary = {}
	match action:
		"build":
			result = WorkshopFacilityManager.upgrade_facility(
				current_facility_id
			)
		"contribute":
			result = WorkshopFacilityManager.contribute_facility_materials(
				current_facility_id
			)
		"refund":
			result = WorkshopFacilityManager.refund_facility_contributions(
				current_facility_id
			)
	_refresh_facility(false)
	_set_feedback(
		str(result.get("message", "Upgrade failed.")),
		not bool(result.get("success", false))
	)

func _on_build_confirmation_cancelled() -> void:
	confirm_overlay.hide()
	pending_action = ""
	pending_quote.clear()

func _exit_to_workshop_menu() -> void:
	visible = false
	get_tree().paused = false
	back_requested.emit()
	queue_free()

func _on_close_pressed() -> void:
	visible = false
	get_tree().paused = false
	cancelled.emit()
	queue_free()
