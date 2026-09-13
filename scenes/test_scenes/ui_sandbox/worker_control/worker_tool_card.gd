class_name WorkerToolCard
extends Button

## Reusable compact worker card for the Worker Hub Tools roster.
## The parent owns selection and worker rules; this card only emits its info action.

signal details_requested(worker_id: String)

@onready var details_button: BaseButton = $InfoButton

var worker_id: String = ""
var select_button: Button


func _ready() -> void:
	select_button = self
	details_button.pressed.connect(_on_details_pressed)
	tooltip_text = ""
	details_button.tooltip_text = ""


func set_worker(row: Dictionary) -> void:
	worker_id = str(row.get("id", ""))
	name = "WorkerCard_%s" % worker_id
	tooltip_text = ""


func _on_details_pressed() -> void:
	if not worker_id.is_empty():
		details_requested.emit(worker_id)
