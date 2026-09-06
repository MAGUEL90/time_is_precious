class_name ProductionInfoPanel
extends Control

const PANEL_WIDTH: float = 184.0
const PANEL_MIN_HEIGHT: float = 64.0
const PANEL_VERTICAL_PADDING: float = 10.0
const SMALL_SHEKEL_ICON: Texture2D = preload(
	"res://assets/ui/ui_icon/small_shekel_8x8.png"
)

@onready var fee_row: HBoxContainer = ($MarginContainer/DetailVBox/FeeRow)
@onready var process_name_label: Label = ($MarginContainer/DetailVBox/Header/ProcessNameLabel)
@onready var output_row: HBoxContainer = ($MarginContainer/DetailVBox/OutputRow)
@onready var capacity_row: HBoxContainer = ($MarginContainer/DetailVBox/CapacityRow)
@onready var usage_label: Label = ($MarginContainer/DetailVBox/CapacityRow/UsageLabel)
@onready var capacity_label: Label = ($MarginContainer/DetailVBox/CapacityRow/CapacityLabel)
@onready var fee_title_label: Label = ($MarginContainer/DetailVBox/FeeRow/FeeTitleLabel)
@onready var currency_icon: TextureRect = ($MarginContainer/DetailVBox/FeeRow/CurrencyIcon)
@onready var fee_amount_label: Label = ($MarginContainer/DetailVBox/FeeRow/FeeAmountLabel)
@onready var detail_vbox: VBoxContainer = ($MarginContainer/DetailVBox)
@onready var requirement_row: HBoxContainer = ($MarginContainer/DetailVBox/RequirementRow)
@onready var input_label: Label = ($MarginContainer/DetailVBox/InputLabel)
@onready var output_label: Label = ($MarginContainer/DetailVBox/OutputRow/OutputLabel)
@onready var requirement_label: Label = ($MarginContainer/DetailVBox/RequirementRow/RequirementLabel)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	$MarginContainer/DetailVBox/Header/CloseButton.pressed.connect(clear_details)
	hide()
	_refresh_size()

func display_process(availability: Dictionary) -> void:
	if not bool(availability.get("registered", false)):
		clear_details()
		return

	input_label.show()
	output_row.show()
	requirement_row.show()
	capacity_row.show()
	fee_row.show()

	var input_id: String = str(availability.get("input_item_id", ""))
	var output_id: String = str(availability.get("output_item_id", ""))
	var quantity: int = int(availability.get("startable_quantity", 0))
	var required_batches: int = int(availability.get("required_batches", 0))
	var free_slots: int = int(availability.get("free_slots", 0))
	var total_slots: int = int(availability.get("total_slots", 0))

	process_name_label.text = "%s" % str(availability.get("process_display_name", "Process"))

	if quantity > 0:
		input_label.text = "Input: %s x%d" % [_get_item_name(input_id), quantity]
		output_label.text = "Output: %s x%d" % [_get_item_name(output_id), quantity]
	else:
		input_label.text = "Input: %s unavailable" % (_get_item_name(input_id))
		output_label.text = "Output: %s" % (_get_item_name(output_id))

	var station_id: String = str(availability.get("required_station_id", ""))
	if (
		WorkshopFacilityManager.has_facility(station_id)
		and WorkshopFacilityManager.is_facility_built(station_id)
	):
		requirement_row.hide()
	else:
		requirement_row.show()
		var station_name: String = station_id.replace(
			"_",
			" "
		).capitalize()
		requirement_label.text = "Requires: %s" % station_name
	usage_label.text = "Uses %d slot" % required_batches
	capacity_label.text = "Free %d/%d" % [free_slots, total_slots]
	_update_fee(availability)
	_refresh_size()
	show()

func _refresh_size() -> void:
	detail_vbox.update_minimum_size()

	var content_height: float = (detail_vbox.get_combined_minimum_size().y + PANEL_VERTICAL_PADDING)
	custom_minimum_size = Vector2(PANEL_WIDTH, maxf(PANEL_MIN_HEIGHT, content_height))

	reset_size()

func clear_details() -> void:
	hide()

func _get_item_name(item_id: String) -> String:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)

	if item_data == null:
		return item_id.replace("_", " ").capitalize()

	return item_data.display_name

func _update_fee(availability: Dictionary) -> void:
	var fee_amount: int = int(availability.get("station_fee_amount", 0))
	var currency_id: String = str(availability.get("station_fee_currency_item_id", ""))

	fee_title_label.text = "Workshop Rent"
	if fee_amount <= 0:
		currency_icon.texture = null
		fee_amount_label.text = "-"
		return

	var currency_data: ItemData = (ItemDatabase.get_item_data(currency_id))
	if currency_data == null:
		currency_icon.texture = null
		fee_amount_label.text = "%d %s" % [fee_amount, currency_id.capitalize()]
		return

	currency_icon.texture = (
		SMALL_SHEKEL_ICON if currency_id == "shekel" else currency_data.icon
	)
	fee_amount_label.text = str(fee_amount)

func display_job(job_title: String) -> void:
	process_name_label.text = "%s" % job_title
	input_label.text = ("Next: choose a worker for this job.")

	output_row.hide()
	requirement_row.hide()
	capacity_row.hide()
	fee_row.hide()

	_refresh_size()
	show()
