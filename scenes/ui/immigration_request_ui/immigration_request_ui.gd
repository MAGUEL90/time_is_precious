extends CanvasLayer

@onready var label: Label = $Root/Panel/VBoxContainer/MarginContainer/VBoxContainer/Label

func _ready() -> void:
	hide()
	ImmigrationManager.immigration_requested.connect(_on_immigration_requested)

func _on_immigration_requested(candidates: Array[CitizenData]) -> void:
	label.text = "%d immigrants request entry." % candidates.size()
	show()

func _on_accept_button_pressed() -> void:
	ImmigrationManager.accept_pending_immigrants()
	hide()

func _on_reject_button_pressed() -> void:
	ImmigrationManager.reject_pending_immigrants()
	hide()
