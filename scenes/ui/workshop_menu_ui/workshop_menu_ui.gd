class_name WorkshopMenuUI extends CanvasLayer

signal action_selected(action_id: int)
signal closed()

enum Action {
	CLAIM_TO_PLAYER,
	MANAGE_STORAGE,
	ASSIGN_WORKER,
	PAY_ALL_FEES,
	PAY_OVERDUE_FEES,
}

@onready var status_label: Label = $Root/Center/Window/Margin/MainVBox/StatusLabel
@onready var claim_button: Button = $Root/Center/Window/Margin/MainVBox/ActionGrid/ClaimButton
@onready var manage_button: Button = $Root/Center/Window/Margin/MainVBox/ActionGrid/ManageButton
@onready var assign_button: Button = $Root/Center/Window/Margin/MainVBox/ActionGrid/AssignButton
@onready var pay_all_button: Button = $Root/Center/Window/Margin/MainVBox/ActionGrid/PayAllButton
@onready var pay_overdue_button: Button = $Root/Center/Window/Margin/MainVBox/ActionGrid/PayOverdueButton
@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/Footer/CloseButton

func _ready() -> void:
	visible = false
	claim_button.pressed.connect(_on_claim_button_pressed)
	manage_button.pressed.connect(_on_manage_button_pressed)
	assign_button.pressed.connect(_on_assign_button_pressed)
	pay_all_button.pressed.connect(_on_pay_all_button_pressed)
	pay_overdue_button.pressed.connect(_on_pay_overdue_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)

func open_menu(fee_summary: Dictionary, has_claimable_output: bool) -> void:
	get_tree().paused = true
	visible = true
	claim_button.disabled = not has_claimable_output
	# continue_button.disabled = not has_claimable_output
	_update_status(fee_summary, has_claimable_output)

func _update_status(fee_summary: Dictionary, has_claimable_output: bool) -> void:
	var unpaid_count: int = int(fee_summary.get("unpaid_count", 0))
	var total_unpaid: int = int(fee_summary.get("total_unpaid_shekel", 0))
	var total_overdue: int = int(fee_summary.get("total_overdue_shekel", 0))
	var claimable_text: String = "Ready output: Yes" if has_claimable_output else "Ready output: None"
	status_label.text = "%s\nUnpaid: %d | Fee: %d | Overdue: %d" % [
		claimable_text,
		unpaid_count,
		total_unpaid,
		total_overdue
	]

func _select_action(action_id: int) -> void:
	get_tree().paused = false
	hide()
	action_selected.emit(action_id)

func _on_claim_button_pressed() -> void:
	_select_action(Action.CLAIM_TO_PLAYER)

func _on_manage_button_pressed() -> void:
	_select_action(Action.MANAGE_STORAGE)

func _on_assign_button_pressed() -> void:
	_select_action(Action.ASSIGN_WORKER)

func _on_pay_all_button_pressed() -> void:
	_select_action(Action.PAY_ALL_FEES)

func _on_pay_overdue_button_pressed() -> void:
	_select_action(Action.PAY_OVERDUE_FEES)

func _on_close_button_pressed() -> void:
	get_tree().paused = false
	hide()
	closed.emit()
