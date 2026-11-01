extends Node

## Real WorkManager orders and workshop storage, with an isolated legacy worker
## (no payroll or commute) so this fixture measures output scaling only.
const JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const STORAGE_SCRIPT: Script = preload("res://scripts/autoload/workshop_storage/workshop_storage.gd")
const REPEATS: int = 16
const CASES: Array[Dictionary] = [
	{"name": "low", "worker": 0.30, "citizen": -1.0, "expected": 17},
	{"name": "normal", "worker": 0.50, "citizen": -1.0, "expected": 20},
	{"name": "high", "worker": 0.80, "citizen": -1.0, "expected": 21},
	{"name": "linked high overrides low worker", "worker": 0.30, "citizen": 0.80, "expected": 21},
	{"name": "linked low overrides high worker", "worker": 0.80, "citizen": 0.30, "expected": 17},
]

var failures: int = 0
var completions: int = 0
var now_total: int = 100 * 1440 + 8 * 60
var storage: Node


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	TimeComponentManager.set_process(false)
	storage = STORAGE_SCRIPT.new()
	storage.max_load = 100000.0
	add_child(storage)
	WorkManager._last_total_minutes = now_total
	_expect(int(JOB.outputs.get("wet_mudbrick", 0)) == 20 and JOB.base_duration_minutes > 0,
		"The real Shape recipe supplies the twenty-unit baseline for these cases.")

	for case_index: int in range(CASES.size()):
		_run_case(CASES[case_index], case_index)

	_expect(completions == CASES.size() * REPEATS, "Every scheduled production order completed.")
	storage.queue_free()
	print("SatisfactionProductionTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures,
		"; completions=", completions)
	get_tree().quit(0 if failures == 0 else 1)


func _run_case(test_case: Dictionary, case_index: int) -> void:
	var worker_id: String = "satisfaction_production_fixture_%d" % case_index
	var worker := WorkerData.new()
	worker.worker_id = worker_id
	worker.profession = JOB.requirement_profession
	worker.satisfaction = float(test_case.worker)
	WorkerDatabase.workers_by_id[worker_id] = worker
	if float(test_case.citizen) >= 0.0:
		var citizen := CitizenData.new()
		citizen.citizen_id = worker_id
		citizen.satisfaction = float(test_case.citizen)
		CitizenManager.citizens_by_id[worker_id] = citizen

	for repetition: int in range(REPEATS):
		for item_id: String in JOB.inputs:
			storage.add_item(item_id, int(JOB.inputs[item_id]))
		var lots_before: int = storage.output_lots.size()
		var fees_before: int = storage.unpaid_claims_ledger.size()
		var held_before: int = storage.get_held_item_quantity("wet_mudbrick")
		var order_id: String = WorkManager.start_job(JOB, WorkOrder.Worker_Type.NPC,
			worker_id, null, storage, storage, JOB.workshop_fee_amount)
		_expect(not order_id.is_empty(), "%s repetition %d starts a real order: %s" %
			[test_case.name, repetition, WorkManager.get_last_start_job_error()])
		if order_id.is_empty():
			break
		for item_id: String in JOB.inputs:
			_expect(storage.get_free_item_quantity(item_id) == 0,
				"The real order consumes its %s input once." % item_id)

		# Re-seed around finalization to detect any consumed global random draw,
		# even if a random penalty happened to leave a sampled quantity unchanged.
		var rng_seed: int = 123400 + case_index * REPEATS + repetition
		seed(rng_seed)
		var next_random: int = randi()
		seed(rng_seed)
		now_total += JOB.base_duration_minutes
		WorkManager.on_time_changed(floori(float(now_total) / 1440.0),
			floori(float(now_total % 1440) / 60.0), now_total % 60)
		_expect(randi() == next_random, "%s completion does not consume an RNG draw." % test_case.name)
		_expect(not WorkManager.active_orders.has(order_id) and not worker.is_reserved(),
			"%s completion releases the order and worker." % test_case.name)
		_expect(storage.output_lots.size() == lots_before + 1
			and storage.unpaid_claims_ledger.size() == fees_before + 1,
			"%s completion creates exactly one held lot and one fee." % test_case.name)
		if storage.output_lots.size() == lots_before + 1:
			var lot: Dictionary = storage.output_lots.back()
			_expect(int(lot.items.get("wet_mudbrick", 0)) == int(test_case.expected)
				and lot.source_id == JOB.job_id and lot.fee_ids.size() == 1,
				"%s repetition %d produces exactly %d units in the job's held lot." %
				[test_case.name, repetition, test_case.expected])
		_expect(storage.get_held_item_quantity("wet_mudbrick") - held_before == int(test_case.expected),
			"%s completion changes held stock by its exact expected output." % test_case.name)
		completions += 1

	WorkerDatabase.workers_by_id.erase(worker_id)
	CitizenManager.citizens_by_id.erase(worker_id)
