class_name JobBoard extends Node2D

const DEFAULT_PROMPT_TEXT: String = "press E\nto access Job Board"
const JOB_BOARD_UI_SCENE: PackedScene = preload(
	"res://scenes/ui/job_board_ui/job_board_ui.tscn"
)

@onready var interactable_component: InteractableComponent = \
	$InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = \
	$InteractableLabelComponent

@export var job_data: JobData
@export var service_fee_shekel: int = 5
@export var default_daily_wage: int = 1

var player_reff: Player
var job_board_ui: JobBoardUI

# Lifecycle

func _ready() -> void:
	player_reff = get_tree().get_first_node_in_group("player") as Player

	if player_reff:
		interactable_component.interactable_activated.connect(
			player_reff._on_interactable_activated.bind(self)
		)
		interactable_component.interactable_deactivated.connect(
			player_reff._on_interactable_deactivated.bind(self)
		)

	interactable_component.interactable_activated.connect(_on_interact_range_entered)
	interactable_component.interactable_deactivated.connect(_on_interact_range_exited)

# Player interaction

func _on_interact_range_entered() -> void:
	interactable_label_component.set_text(DEFAULT_PROMPT_TEXT)
	interactable_label_component.show()

func _on_interact_range_exited() -> void:
	interactable_label_component.set_text(DEFAULT_PROMPT_TEXT)
	interactable_label_component.hide()

func on_player_interact(_player: Player) -> void:
	if is_instance_valid(job_board_ui):
		return

	job_board_ui = JOB_BOARD_UI_SCENE.instantiate() as JobBoardUI

	if job_board_ui == null:
		return

	get_tree().current_scene.add_child(job_board_ui)
	job_board_ui.closed.connect(_on_job_board_ui_closed)
	job_board_ui.open(default_daily_wage)

# UI lifecycle

func _on_job_board_ui_closed() -> void:
	if is_instance_valid(job_board_ui):
		job_board_ui.queue_free()

	job_board_ui = null
