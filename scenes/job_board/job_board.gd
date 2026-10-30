class_name JobBoard extends Node2D

const CLOSED_FEEDBACK_TEXT: String = "akses job board jam 08.00 -17.00"
const CLOSED_FEEDBACK_HOME_POSITION: Vector2 = Vector2(-80.0, -42.0)
const CLOSED_FEEDBACK_RISE: float = 14.0
const CLOSED_FEEDBACK_SHAKE_DISTANCE: float = 2.0
const CLOSED_FEEDBACK_SHAKE_STEP_DURATION: float = 0.05
const JOB_BOARD_UI_SCENE: PackedScene = preload(
	"res://scenes/ui/job_board_ui/job_board_ui.tscn"
)

@onready var interactable_component: InteractableComponent = \
	$InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = \
	$InteractableLabelComponent
@onready var closed_feedback_label: Label = $ClosedFeedbackLabel

@export var job_data: JobData
@export var service_fee_shekel: int = 5
@export var default_daily_wage: int = 1

var player_reff: Player
var job_board_ui: JobBoardUI
var _closed_feedback_tween: Tween

# Lifecycle

func _ready() -> void:
	closed_feedback_label.text = CLOSED_FEEDBACK_TEXT
	closed_feedback_label.position = CLOSED_FEEDBACK_HOME_POSITION
	closed_feedback_label.hide()

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

func _exit_tree() -> void:
	_cancel_closed_feedback_tween()

# Player interaction

func _on_interact_range_entered() -> void:
	interactable_label_component.show()

func _on_interact_range_exited() -> void:
	interactable_label_component.hide()

func on_player_interact(_player: Player) -> void:
	if not WorkerDatabase.is_job_board_open():
		_show_closed_feedback()
		return
	if is_instance_valid(job_board_ui):
		return

	job_board_ui = JOB_BOARD_UI_SCENE.instantiate() as JobBoardUI

	if job_board_ui == null:
		return

	get_tree().current_scene.add_child(job_board_ui)
	job_board_ui.closed.connect(_on_job_board_ui_closed)
	job_board_ui.open(default_daily_wage)

func _show_closed_feedback() -> void:
	_cancel_closed_feedback_tween()
	closed_feedback_label.position = CLOSED_FEEDBACK_HOME_POSITION
	closed_feedback_label.modulate.a = 1.0
	closed_feedback_label.show()

	var peak_position: Vector2 = CLOSED_FEEDBACK_HOME_POSITION + Vector2.UP * CLOSED_FEEDBACK_RISE
	_closed_feedback_tween = create_tween()
	_closed_feedback_tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_closed_feedback_tween.tween_property(
		closed_feedback_label,
		"position",
		peak_position,
		2.0
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_closed_feedback_tween.tween_property(
		closed_feedback_label,
		"position",
		peak_position + Vector2(CLOSED_FEEDBACK_SHAKE_DISTANCE, 0.0),
		CLOSED_FEEDBACK_SHAKE_STEP_DURATION
	).set_trans(Tween.TRANS_SINE)
	_closed_feedback_tween.tween_property(
		closed_feedback_label,
		"position",
		peak_position + Vector2(-CLOSED_FEEDBACK_SHAKE_DISTANCE, 0.0),
		CLOSED_FEEDBACK_SHAKE_STEP_DURATION
	).set_trans(Tween.TRANS_SINE)
	_closed_feedback_tween.tween_property(
		closed_feedback_label,
		"position",
		peak_position + Vector2(CLOSED_FEEDBACK_SHAKE_DISTANCE, 0.0),
		CLOSED_FEEDBACK_SHAKE_STEP_DURATION
	).set_trans(Tween.TRANS_SINE)
	_closed_feedback_tween.tween_property(
		closed_feedback_label,
		"position",
		peak_position,
		CLOSED_FEEDBACK_SHAKE_STEP_DURATION
	).set_trans(Tween.TRANS_SINE)
	_closed_feedback_tween.chain()
	_closed_feedback_tween.set_parallel(true)
	_closed_feedback_tween.tween_property(
		closed_feedback_label,
		"position",
		CLOSED_FEEDBACK_HOME_POSITION,
		0.45
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_closed_feedback_tween.tween_property(
		closed_feedback_label,
		"modulate:a",
		0.0,
		0.45
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_closed_feedback_tween.set_parallel(false)
	_closed_feedback_tween.tween_callback(_on_closed_feedback_tween_finished)

func _cancel_closed_feedback_tween() -> void:
	if _closed_feedback_tween != null and _closed_feedback_tween.is_valid():
		_closed_feedback_tween.kill()
	_closed_feedback_tween = null

func _on_closed_feedback_tween_finished() -> void:
	_closed_feedback_tween = null
	if not is_instance_valid(closed_feedback_label):
		return
	closed_feedback_label.hide()
	closed_feedback_label.position = CLOSED_FEEDBACK_HOME_POSITION
	closed_feedback_label.modulate.a = 1.0

# UI lifecycle

func _on_job_board_ui_closed() -> void:
	if is_instance_valid(job_board_ui):
		job_board_ui.queue_free()

	job_board_ui = null
