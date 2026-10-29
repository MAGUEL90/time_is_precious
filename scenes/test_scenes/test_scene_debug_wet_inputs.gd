extends Node

## The debug supply may fill a built workshop, but normal assignment owns work.
const MAP = preload("res://scenes/content_scene/content_scene.tscn")
const JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	var content: Node = MAP.instantiate()
	add_child(content)
	var plot: Node = content.get_node("YSortWorld/WorkshopPlot")
	var debug: Node = content.get_node("TimeDebugOverlay")
	debug.set_process(false)
	_check(not debug.give_wet_mudbrick_inputs() and WorkShopStorage.items.is_empty(), "Unbuilt workshop gets no debug inputs.")
	plot.construction.phase = "built" # Completed-workshop fixture; supply only, no free job.
	plot._sync_construction()
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_orders: int = WorkManager.active_orders.size()
	_check(debug.give_wet_mudbrick_inputs(), "Debug button fills the real Workshop Storage.")
	for item_id_value: Variant in JOB.inputs:
		var item_id: String = str(item_id_value)
		_check(WorkShopStorage.get_free_item_quantity(item_id) == int(JOB.inputs[item_id_value]), "Recipe quantity in free stock: " + item_id)
	_check(Inventory.items == before_inventory and WorkManager.active_orders.size() == before_orders and not WorkShopStorage.items.has("wet_mudbrick"), "Supply changes no wallet, personal bag, order or output.")
	var supplied: Dictionary = WorkShopStorage.items.duplicate(true)
	_check(not debug.give_wet_mudbrick_inputs() and WorkShopStorage.items == supplied, "Repeated supply is idempotent.")
	for item_id_value: Variant in JOB.inputs:
		WorkShopStorage.remove_item(str(item_id_value), int(JOB.inputs[item_id_value]))
	var capacity: float = WorkShopStorage.max_load
	WorkShopStorage.max_load = 0.0
	_check(not debug.give_wet_mudbrick_inputs() and WorkShopStorage.items.is_empty(), "Full storage rejects the whole recipe atomically.")
	WorkShopStorage.max_load = capacity
	_check(debug.give_wet_mudbrick_inputs(), "Supply works after capacity returns.")
	var worker := WorkerData.new()
	worker.worker_id = "wet_inputs_fixture"
	worker.profession = JOB.requirement_profession
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	var workshop: WorkShop = plot.get_node("BuiltWorkshop")
	_check(workshop.start_job_from_storage(JOB, [worker.worker_id] as Array[String]), "Normal workshop API starts a job from supplied free inputs.")
	_check(WorkManager.active_orders.size() == before_orders + 1 and not worker.physical_approach.arrived, "Starting the job still requires worker arrival and normal order creation.")
	print("DebugWetInputsTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
