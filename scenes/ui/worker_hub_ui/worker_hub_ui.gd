class_name WorkerHubUI extends CanvasLayer 

const MUDBRICK_JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const MAX_ACTIVE_TEAM_SLOTS: int = 3

@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/Header/CloseButton
@onready var worker_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/Body/WorkerPanel/WorkerScroll/WorkerList
@onready var feedback_label: Label = $Root/Center/Window/Margin/MainVBox/Body/ActionPanel/FeedbackLabel
@onready var team_slot_grid: GridContainer = $Root/Center/Window/Margin/MainVBox/Body/TeamPanel/TeamSlotGrid
@onready var job_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/Body/JobPanel/JobList
@onready var team_preview_label: Label = $Root/Center/Window/Margin/MainVBox/Body/TeamPanel/TeamPreviewLabel

var selected_job: JobData
var selected_workers: Array[WorkerData] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_refresh_team_slots()
	_refresh_job_list()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_worker_hub"):
		if visible:
			close()
		else:
			open()

func open() -> void:
	get_tree().paused = true
	visible = true
	_refresh_worker_lists()
	feedback_label.text = "Select a workshop job."

func close() -> void:
	get_tree().paused = false
	visible = false

func _refresh_team_slots() -> void:
	for child in team_slot_grid.get_children():
		child.queue_free()
	
	for slot_index in range(12):
		var slot_button: Button = Button.new()
		
		if slot_index < MAX_ACTIVE_TEAM_SLOTS:
			if slot_index < selected_workers.size():
				var worker_data: WorkerData = selected_workers[slot_index]
				slot_button.text = "%s\n%s" % [
					worker_data.display_name,
					_get_worker_profession_name(worker_data.profession)]
			else:
				slot_button.text = "Empty Slot"
				
			slot_button.disabled = false
		else:
			slot_button.text = "Locked"
			slot_button.disabled = true
	
		team_slot_grid.add_child(slot_button)

func _refresh_worker_lists() -> void:
	for child in worker_list.get_children():
		child.queue_free()
	
	for worker in WorkerDatabase.get_all_hired_workers():
		if not (worker is WorkerData):
			continue
		var worker_data: WorkerData = worker as WorkerData
		var button_list: Button = Button.new()
		button_list.text = "Name: %s\nProfession: %s\nStatus: %s\nSAT: %d%%, REL: %d%% " % [
			worker_data.display_name,
			_get_worker_profession_name(worker_data.profession),
			_get_worker_status_text(worker_data),
			roundi(worker_data.satisfaction * 100.0), roundi(worker_data.reliability * 100.0)
		]
		button_list.pressed.connect(_on_worker_selected.bind(worker_data))

		worker_list.add_child(button_list)
		

func _refresh_job_list() -> void:
	for child in job_list.get_children():
		child.queue_free()
	
	var job_button: Button = Button.new()
	job_button.text = MUDBRICK_JOB.display_name
	job_button.pressed.connect(_on_job_selected.bind(MUDBRICK_JOB))
	job_list.add_child(job_button)

func _on_job_selected(job_data: JobData) -> void:
	selected_job = job_data
	team_preview_label.text = "Selected Job: %s" % job_data.display_name
	feedback_label.text = "Choose workers for this job."

func _on_worker_selected(worker_data: WorkerData) -> void:
	if worker_data.is_working():
		feedback_label.text = "Worker is busy."
		return
	
	if worker_data in selected_workers:
		feedback_label.text = "Worker already selected."
		return
	
	if selected_workers.size() == MAX_ACTIVE_TEAM_SLOTS:
		feedback_label.text = "Team slots are full."
		return
	
	selected_workers.append(worker_data)
	
	_refresh_team_slots()
	feedback_label.text = ""

func _on_clear_team() -> void:
	selected_workers.clear()
	_refresh_team_slots()
	feedback_label.text = "Team cleared."

func _on_start_job() -> void:
	if selected_job == null:
		feedback_label.text = "Select a workshop job first."
		return
		
	if selected_workers.is_empty():
		feedback_label.text = "Select at least one worker."
		return
	
	var first_worker: WorkerData = selected_workers[0]
	
	
	var order_id: String = WorkManager.start_job(
	selected_job,
	WorkOrder.Worker_Type.NPC,
	first_worker.worker_id,
	null,
	Inventory,
	null,
	5)
	
	if order_id.is_empty():
		feedback_label.text = WorkManager.get_last_start_job_error()
		return
	
	feedback_label.text = "Started: %s" % selected_job.display_name
	selected_workers.clear()
	_refresh_team_slots()
	_refresh_worker_lists()

func _on_close_button_pressed() -> void:
	close()
	
func _on_clear_team_button_pressed() -> void:
	_on_clear_team()

func _on_start_job_button_pressed() -> void:
	_on_start_job()

func _get_worker_status_text(worker_data: WorkerData) -> String:
	if worker_data.is_working():
		return "Working"
	
	return "Idle"

func _get_worker_profession_name(profession: WorkerData.Profession) -> String:
	match profession:
		WorkerData.Profession.LABORER:
			return "Laborer"
		WorkerData.Profession.CRAFTER:
			return "Crafter"
		WorkerData.Profession.HAULER:
			return "Hauler"
		WorkerData.Profession.FARMER:
			return "Farmer"
		WorkerData.Profession.SCAVENGER:
			return "Scavenger"
		_:
			return "Unknown"
