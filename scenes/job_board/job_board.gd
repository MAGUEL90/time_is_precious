class_name JobBoard extends Node2D

const DEFAULT_PROMPT_TEXT: String = "press E\nto manage workers"

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent

@export var job_data: JobData
@export var service_fee_shekel: int = 5

var player_reff: Player

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	player_reff = get_tree().get_first_node_in_group("player") as Player
	
	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))

	interactable_component.interactable_activated.connect(_on_interact_range_entered)
	interactable_component.interactable_deactivated.connect(_on_interact_range_exited)

func _on_interact_range_entered() -> void:
	interactable_label_component.set_text(DEFAULT_PROMPT_TEXT)
	interactable_label_component.show()

func _on_interact_range_exited() -> void:
	interactable_label_component.set_text(DEFAULT_PROMPT_TEXT)
	interactable_label_component.hide()

func on_player_interact(_player: Player) -> void:
	if job_data == null:
		interactable_label_component.set_text("Failed:\nJob data missing")
		interactable_label_component.show()
		return

	var order_id: String = ""
	if WorkManager.has_method("start_job"):
		order_id = str(WorkManager.call("start_job",
		job_data,
		WorkOrder.Worker_Type.NPC,
		"", null, Inventory, null, service_fee_shekel))

	if order_id.is_empty():
		interactable_label_component.set_text("Failed:\n%s" % WorkManager.get_last_start_job_error())
		interactable_label_component.show()
		return

	interactable_label_component.set_text("Started:\n%s" % job_data.display_name)
	interactable_label_component.show()
