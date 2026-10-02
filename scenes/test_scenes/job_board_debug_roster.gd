extends Node

const CONTENT_SCENE: PackedScene = preload(
	"res://scenes/content_scene/content_scene.tscn"
)
const DEBUG_APPLICANTS: Array[Dictionary] = [
	{
		"name": "Debug Laborer",
		"profession": WorkerData.Profession.LABORER,
		"satisfaction": 1.0,
	},
	{
		"name": "Debug Crafter",
		"profession": WorkerData.Profession.CRAFTER,
		"satisfaction": 0.9,
	},
	{
		"name": "Debug Hauler",
		"profession": WorkerData.Profession.HAULER,
		"satisfaction": 0.8,
	},
	{
		"name": "Debug Farmer",
		"profession": WorkerData.Profession.FARMER,
		"satisfaction": 0.7,
	},
	{
		"name": "Debug Scavenger",
		"profession": WorkerData.Profession.SCAVENGER,
		"satisfaction": 0.6,
	},
]


func _ready() -> void:
	_setup_debug_roster.call_deferred()


func _setup_debug_roster() -> void:
	var content: Node = CONTENT_SCENE.instantiate()
	var initial_worksites: Node = content.get_node("YSortWorld/InitialWorksites")
	initial_worksites.set("enable_initial_applicant", false)
	add_child(content)
	await get_tree().process_frame

	var run_id: String = str(Time.get_ticks_usec())
	for index in range(DEBUG_APPLICANTS.size()):
		var applicant_data: Dictionary = DEBUG_APPLICANTS[index]
		var applicant := CitizenData.new()
		applicant.citizen_id = "debug_job_board_%s_%02d" % [run_id, index + 1]
		applicant.display_name = str(applicant_data["name"])
		applicant.population_status = CitizenData.PopulationStatus.RESIDENT
		applicant.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
		applicant.satisfaction = float(applicant_data["satisfaction"])
		CitizenManager.add_citizen(applicant)
		var registered: bool = CitizenManager.register_applicant(
			applicant.citizen_id,
			applicant_data["profession"]
		)
		if not registered:
			push_error("Could not register debug applicant: " + applicant.display_name)

	var job_board: JobBoard = content.get_node(
		"YSortWorld/InitialWorksites/JobBoard"
	) as JobBoard
	var player: Player = content.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.global_position = job_board.global_position + Vector2(0, 12)
	job_board.on_player_interact(player)
	print("JobBoardDebugRoster: seeded %d hireable applicants." % DEBUG_APPLICANTS.size())
