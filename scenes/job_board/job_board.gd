class_name JobBoard extends Node2D

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent

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
	interactable_label_component.show()

func _on_interact_range_exited() -> void:
	interactable_label_component.hide()

func on_player_interact(_player: Player) -> void:
	var job_data: JobData = JobData.new()
	
	job_data.job_id = "mudbrick_make"
	job_data.display_name = "Mudbrick Making"
	job_data.base_duration_minutes = 30 # durasi job 10 menit untuk test
	job_data.inputs = {"clay_lump": 3, "straw_bundle": 3, "water_jar": 3}
	job_data.outputs = {"wet_mudbrick": 60}  # output intermediate 60 bata basah
	job_data.requirement_profession = WorkerData.Profession.LABORER
	
	var order_id: String = ""
	if WorkManager.has_method("start_job"):
		order_id = str(WorkManager.call("start_job",
		job_data,
		WorkOrder.Worker_Type.NPC,
		"", null, Inventory, null, 5))
	
	if order_id.is_empty():
		print("Start job failed: ", WorkManager.get_last_start_job_error())
		
	print("Start_order_id: ", order_id)
	
	
	
	
	
	
	
