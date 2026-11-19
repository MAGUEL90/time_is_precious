extends Node

## Read the paused-work checkpoint from workshop_resignation_continue_test's
## write phase through the actual Start Menu Continue button in a fresh process.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const CHECKPOINT_PATH: String = "user://workshop_resignation_continue/checkpoint.json"
const FIRST_ID: String = "resignation_save_first"

var failures: int = 0
var launched: bool = false
var did_continue: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var original: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
	_expect(not original.is_empty(), "The isolated paused-work checkpoint already exists.")
	if failures > 0:
		_finish()
		return
	get_tree().current_scene = null
	get_tree().paused = false
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = CHECKPOINT_PATH
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	menu.continue_button.pressed.emit()
	for _frame: int in range(600):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched and did_continue, "The real Start Menu completes Continue.")
	if launched and did_continue:
		var citizen: CitizenData = CitizenManager.get_citizen(FIRST_ID)
		var archived: WorkerData = WorkerDatabase.dismissed_workers.get(FIRST_ID)
		_expect(citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
			and archived != null and not WorkerDatabase.has_worker_data(FIRST_ID),
			"Continue retains the original unemployed citizen and archived worker.")
		var paused: int = 0
		for order: WorkOrder in WorkManager.active_orders.values():
			if order.job_id == "mudbrick_make" and order.current_status == WorkOrder.Status.QUEUED and order.worker_id.is_empty():
				paused += 1
		_expect(paused == 2, "Both located and legacy unlocated paused batches survive the menu route.")
		_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == original,
			"Continue does not rewrite the source checkpoint.")
	_finish()


func _on_session_started(continued: bool) -> void:
	did_continue = continued
	launched = true


func _finish() -> void:
	print("ResignationMenuContinueTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
