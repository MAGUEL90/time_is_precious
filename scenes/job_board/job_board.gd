class_name JobBoard extends Node2D

const DEFAULT_PROMPT_TEXT: String = "press E\nto access Job Board"

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
	var offers_text: String = _get_applicant_offers_text()

	interactable_label_component.set_text(offers_text)
	interactable_label_component.show()

func _get_applicant_offers_text() -> String:
	var offer_lines: Array[String] = []

	for offer in ApplicantOfferDatabase.get_all_offers():
		if not (offer is ApplicantOfferData):
			continue

		var offer_data: ApplicantOfferData = offer as ApplicantOfferData
		if offer_data.worker_data == null:
			continue

		offer_lines.append("%s - %d/day" % [
			offer_data.worker_data.display_name,
			offer_data.daily_wage
		])

	if offer_lines.is_empty():
		return "No applicant offers."

	return "Applicants:\n" + "\n".join(offer_lines)
