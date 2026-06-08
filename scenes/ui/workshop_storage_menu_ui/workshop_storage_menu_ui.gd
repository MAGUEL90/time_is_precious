class_name WorkshopStorageMenuUI extends CanvasLayer

signal action_selected(action_id: int)
signal closed()

@onready var deposit_button: Button = $Root/Center/Window/Margin/MainVBox/DepositButton
@onready var withdraw_button: Button = $Root/Center/Window/Margin/MainVBox/WithdrawButton
@onready var back_button: Button = $Root/Center/Window/Margin/MainVBox/BackButton

enum Action {DEPOSIT_ITEMS, WITHDRAW_ITEMS, BACK}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false
	deposit_button.pressed.connect(_on_deposit_button_pressed)
	withdraw_button.pressed.connect(_on_withdraw_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

func open_menu() -> void:
	get_tree().paused = true
	visible = true

func _selected_action(action_id: int) -> void:
	get_tree().paused = false
	hide()
	action_selected.emit(action_id)

func _on_deposit_button_pressed() -> void:
	_selected_action(Action.DEPOSIT_ITEMS)

func _on_withdraw_button_pressed() -> void:
	_selected_action(Action.WITHDRAW_ITEMS)

func _on_back_button_pressed() -> void:
	get_tree().paused = false
	hide()
	closed.emit()
