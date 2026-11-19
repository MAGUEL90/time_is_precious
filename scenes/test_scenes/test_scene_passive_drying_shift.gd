extends Node

## Real drying process across shift end and midnight, with no hired workers.
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_day = 5
	TimeComponentManager.current_hour = 14
	TimeComponentManager.current_minute = 58
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager.emit_time_signal()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	WorkShopStorage.items.clear()
	WorkShopStorage.claimable_outputs.clear()
	WorkShopStorage.output_lots.clear()
	WorkShopStorage.unpaid_claims_ledger.clear()
	WorkShopStorage.max_load = 100000.0
	ProcessManager._auto_pull_batch_size.clear()
	_expect(WorkshopFacilityManager.set_facility_level("drying_yard", 1),
		"The real drying yard is available.")
	_expect(WorkerDatabase.get_all_workers().is_empty(), "No worker is hired for passive drying.")
	WorkShopStorage.add_item("wet_mudbrick", 20)
	_expect(ProcessManager.start_registered_process("drying_mudbrick", 20),
		"A real drying batch starts before the end of the shift.")
	var station: StationState = ProcessManager.stations.get("drying_yard")
	var first: ProcessBatch = station.slots[0] if station != null else null
	if first == null:
		_finish()
		return
	var first_duration: int = first.duration_minutes
	_expect(first_duration > 2, "The real batch spans the 15:00 boundary.")
	_expect(TimeComponentManager.advance_minutes(2) and first.progress_minutes == 2,
		"The passive batch progresses through 15:00.")
	_expect(TimeComponentManager.advance_minutes(first_duration - 2),
		"Time advances after the work shift.")
	_expect(station.slots[0] == null and int(WorkShopStorage.items.get("sun_dried_mudbrick", 0)) == 20,
		"Drying completes once after the shift without a worker.")
	var current_minute: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(current_minute < 23 * 60 + 55 and TimeComponentManager.advance_minutes(23 * 60 + 55 - current_minute),
		"The fixture reaches 23:55 on the same day.")
	WorkShopStorage.add_item("wet_mudbrick", 20)
	_expect(ProcessManager.start_registered_process("drying_mudbrick", 20),
		"A second real drying batch starts at night.")
	var second: ProcessBatch = station.slots[0] as ProcessBatch
	if second == null:
		_finish()
		return
	var second_duration: int = second.duration_minutes
	_expect(second_duration > 5 and TimeComponentManager.advance_minutes(5) and second.progress_minutes == 5,
		"The unstaffed batch progresses through midnight.")
	_expect(TimeComponentManager.advance_minutes(second_duration - 5),
		"Time advances to the second batch completion.")
	_expect(station.slots[0] == null and int(WorkShopStorage.items.get("sun_dried_mudbrick", 0)) == 40
		and WorkerDatabase.get_all_workers().is_empty(),
		"Both passive batches complete exactly once without a worker.")
	_finish()


func _finish() -> void:
	print("PassiveDryingShiftTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
