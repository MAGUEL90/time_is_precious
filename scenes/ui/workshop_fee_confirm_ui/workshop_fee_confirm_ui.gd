class_name WorkshopFeeConfirmUI extends CanvasLayer

signal payment_selected(will_pay_fee: bool)
signal cancelled()

@onready var fee_panel: ActionChoicePanel = $Root/Center/FeePanel

func _ready() -> void:
	fee_panel.primary_selected.connect(_on_pay_selected)
	fee_panel.secondary_selected.connect(_on_back_selected)
	fee_panel.cancelled.connect(_on_close_selected)

func open_output_fee(item_summary: String, fee_summary: String) -> void:
	_open_payment_prompt(
		"Unlock %s?\nFee: %s" % [item_summary, fee_summary]
	)

func open_all_output_fees(fee_summary: String) -> void:
	_open_payment_prompt(
		"Unlock all Held Output?\nFee: %s" % fee_summary
	)

func _open_payment_prompt(message: String) -> void:
	fee_panel.setup(
		message,
		"Pay",
		"Back",
		true
	)
	get_tree().paused = true
	visible = true
	fee_panel.primary_button.grab_focus()

func _on_pay_selected() -> void:
	payment_selected.emit(true)
	queue_free()

func _on_back_selected() -> void:
	payment_selected.emit(false)
	queue_free()

func _on_close_selected() -> void:
	cancelled.emit()
	queue_free()
