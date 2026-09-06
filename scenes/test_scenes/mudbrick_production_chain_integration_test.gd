extends Node

const DRYING_PROCESS: ProcessData = preload(
	"res://resources/process_data/drying_mudbrick.tres"
)

var failures: int = 0

func _ready() -> void:
	_reset_runtime_state()
	_run_facility_level_test()
	_reset_runtime_state()
	_run_chain_test()
	_reset_runtime_state()
	_run_overdue_fee_test()

	if failures == 0:
		print("MudbrickProductionChainIntegrationTest PASSED")
	else:
		push_error(
			"MudbrickProductionChainIntegrationTest FAILED: %d checks"
			% failures
		)

	get_tree().quit(1 if failures > 0 else 0)

func _reset_runtime_state() -> void:
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 0
	TimeComponentManager.current_minute = 0
	Inventory.items.clear()
	WorkShopStorage.items.clear()
	WorkShopStorage.output_lots.clear()
	WorkShopStorage.claimable_outputs.clear()
	WorkShopStorage.unpaid_claims_ledger.clear()
	WorkShopStorage.max_load = 200.0
	WorkShopStorage.unpaid_fee_due_days = 3
	WorkShopStorage.overdue_penalty_percent_per_day = 10
	WorkShopStorage.overdue_fee_max_multiplier = 2.0
	ProcessManager.stations.clear()
	WorkshopFacilityManager.reset_facilities()
	ProcessManager.processes.clear()
	ProcessManager._auto_pull_batch_size.clear()
	ProcessManager._last_total_minutes = 0
	ProcessManager.set_source_item_store(WorkShopStorage)
	ProcessManager.set_output_item_store(WorkShopStorage)
	ProcessManager.register_process(DRYING_PROCESS)

func _run_facility_level_test() -> void:
	var unbuilt_state: Dictionary = (
		WorkshopFacilityManager.get_facility_state("drying_yard")
	)
	var unbuilt_availability: Dictionary = (
		ProcessManager.get_process_availability("drying_mudbrick")
	)
	_expect(
		int(unbuilt_state.get("level", -1)) == 0
		and not bool(unbuilt_state.get("is_built", true))
		and int(unbuilt_state.get("station_slots", -1)) == 0,
		"Drying Yard should begin unbuilt at level 0."
	)
	_expect(
		not bool(unbuilt_availability.get("station_ready", true))
		and int(unbuilt_availability.get("total_slots", -1)) == 0
		and not bool(unbuilt_availability.get("can_start", true)),
		"Drying must stay unavailable before its yard is built."
	)
	WorkShopStorage.add_item("wet_mudbrick", 20)
	_expect(
		not ProcessManager.start_registered_process(
			"drying_mudbrick",
			20
		),
		"Direct process start must reject an unbuilt Drying Yard."
	)
	_expect(
		WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 20,
		"Rejected Drying must not consume its input."
	)
	WorkShopStorage.remove_item("wet_mudbrick", 20)

	var missing_preview: Dictionary = (
		WorkshopFacilityManager.get_facility_upgrade_preview(
			"drying_yard",
			WorkShopStorage
		)
	)
	_expect(
		not bool(missing_preview.get("can_upgrade", true))
		and not missing_preview.get("missing_items", {}).is_empty(),
		"Drying Yard construction should require Workshop Free Stock materials."
	)

	for level: int in range(1, 4):
		var requirements: Dictionary = (
			WorkshopFacilityManager.get_facility_upgrade_requirements(
				"drying_yard",
				level
			)
		)
		WorkShopStorage.add_bulk_item(requirements)
		var upgrade_result: Dictionary = (
			WorkshopFacilityManager.upgrade_facility(
				"drying_yard",
				WorkShopStorage
			)
		)
		_expect(
			bool(upgrade_result.get("success", false)),
			"Drying Yard level %d should consume its materials and build."
			% level
		)
		for item_id_value in requirements.keys():
			var item_id: String = str(item_id_value)
			_expect(
				WorkShopStorage.get_free_item_quantity(item_id) == 0,
				"Level %d should consume required %s Free Stock." % [
					level,
					item_id
				]
			)
		var availability: Dictionary = (
			ProcessManager.get_process_availability("drying_mudbrick")
		)
		_expect(
			bool(availability.get("station_ready", false))
			and int(availability.get("total_slots", 0)) == level,
			"Drying Yard level %d should provide %d slot(s)." % [
				level,
				level
			]
		)

	_expect(
		not WorkshopFacilityManager.set_facility_level(
			"drying_yard",
			4
		),
		"Drying Yard must reject levels above its maximum."
	)
	_expect(
		WorkshopFacilityManager.get_facility_level("drying_yard") == 3,
		"A rejected facility upgrade must preserve its previous level."
	)

func _run_chain_test() -> void:
	_expect(
		WorkshopFacilityManager.set_facility_level(
			"drying_yard",
			1
		),
		"Drying Yard level 1 should unlock the Mudbrick chain."
	)
	Inventory.add_item("shekel", 20)

	var wet_output: Dictionary[String, int] = {"wet_mudbrick": 20}
	var shape_stored: bool = WorkShopStorage.receive_completed_output(
		wet_output,
		5,
		"worker_laborer_01",
		0,
		"mudbrick_make"
	)
	_expect(shape_stored, "Shape output should fit Workshop storage.")
	_expect(
		WorkShopStorage.get_held_item_quantity("wet_mudbrick") == 20,
		"Shape output should become Held Output."
	)
	_expect(
		WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 0,
		"Unpaid Wet Mudbrick must not become Free Stock."
	)
	_expect(
		not bool(
			ProcessManager.get_process_availability(
				"drying_mudbrick"
			).get("can_start", false)
		),
		"Held Wet Mudbrick must not start Drying."
	)

	var wet_lot_id: String = _find_held_lot_id("wet_mudbrick")
	var wet_payment: Dictionary = WorkShopStorage.pay_output_lot(
		wet_lot_id,
		Inventory
	)
	_expect(
		bool(wet_payment.get("success", false)),
		"Shape fee should unlock Wet Mudbrick."
	)
	_expect(
		WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 20,
		"Paid Wet Mudbrick should become Free Stock."
	)

	var process_started: bool = ProcessManager.start_registered_process(
		"drying_mudbrick",
		20
	)
	_expect(process_started, "A full Drying batch should start.")
	_expect(
		WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 0,
		"Drying should consume its Wet Mudbrick input."
	)
	var active_processes: Array[Dictionary] = (
		ProcessManager.get_active_progress_entries()
	)
	_expect(
		not active_processes.is_empty()
		and int(active_processes[0].get("total_quantity", 0)) == 20
		and int(
			active_processes[0].get("inputs", {}).get(
				"wet_mudbrick",
				0
			)
		) == 20,
		"Consumed Wet Mudbrick should remain visible as active process input."
	)
	_expect(
		not active_processes.is_empty()
		and active_processes[0].get("job_icon") == DRYING_PROCESS.icon,
		"Drying progress should use its dedicated work icon."
	)
	_expect(
		int(WorkShopStorage.get_unpaid_fee_summary().get("unpaid_count", 0)) == 0,
		"Drying fee should stay inactive while its output is unavailable."
	)

	ProcessManager.on_time_changed(0, 0, 10)
	_expect(
		WorkShopStorage.get_held_item_quantity("sun_dried_mudbrick") == 20,
		"Drying output should become Held Output."
	)
	_expect(
		WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 0,
		"Unpaid Drying output must remain locked."
	)
	_expect(
		int(WorkShopStorage.get_unpaid_fee_summary().get("unpaid_count", 0)) == 1,
		"Drying fee should activate when its Held Output becomes available."
	)

	var dry_lot_id: String = _find_held_lot_id("sun_dried_mudbrick")
	var dry_payment: Dictionary = WorkShopStorage.pay_output_lot(
		dry_lot_id,
		Inventory
	)
	_expect(
		bool(dry_payment.get("success", false)),
		"Drying fee should unlock Sun-Dried Mudbrick."
	)
	_expect(
		WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 20,
		"Paid Sun-Dried Mudbrick should become Free Stock."
	)

	WorkShopStorage.max_load = 100.0
	var pending_stored: bool = WorkShopStorage.receive_completed_output(
		wet_output,
		5,
		"worker_laborer_01",
		10,
		"mudbrick_make"
	)
	_expect(
		not pending_stored and WorkShopStorage.has_blocking_pending_output(),
		"Full storage should create a blocking Pending Delivery."
	)
	_expect(
		int(WorkShopStorage.get_unpaid_fee_summary().get("unpaid_count", 0)) == 0,
		"Pending Delivery must not start an inaccessible fee deadline."
	)
	var shekel_before_pending_payment: int = int(
		Inventory.items.get("shekel", 0)
	)
	_expect(
		not WorkShopStorage.settle_held_output_fees(Inventory),
		"Pay All must not pay a Pending Delivery before it enters storage."
	)
	_expect(
		int(Inventory.items.get("shekel", 0)) == shekel_before_pending_payment,
		"A hidden Pending Delivery must not consume player currency."
	)

	var removed_free_stock: bool = WorkShopStorage.remove_free_items(
		{"sun_dried_mudbrick": 20}
	)
	_expect(removed_free_stock, "Free Stock should be removable.")
	_expect(
		not WorkShopStorage.has_blocking_pending_output(),
		"Pending Delivery should enter storage after space is freed."
	)
	_expect(
		WorkShopStorage.get_held_item_quantity("wet_mudbrick") == 20,
		"Delivered pending output should retain its fee lock."
	)
	_expect(
		int(WorkShopStorage.get_unpaid_fee_summary().get("unpaid_count", 0)) == 1,
		"Pending Delivery fee should activate after entering Held Output."
	)
	_expect(
		WorkShopStorage.settle_held_output_fees(Inventory),
		"Pay All should unlock visible Held Output."
	)
	_expect(
		WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 20,
		"Paid Pending Delivery should become Free Stock after delivery."
	)

func _run_overdue_fee_test() -> void:
	Inventory.add_item("shekel", 100)
	var wet_output: Dictionary[String, int] = {"wet_mudbrick": 20}
	var shape_stored: bool = WorkShopStorage.receive_completed_output(
		wet_output,
		5,
		"worker_laborer_01",
		0,
		"mudbrick_make"
	)
	_expect(shape_stored, "Overdue test output should fit Workshop storage.")

	_set_test_day(3)
	var due_day_summary: Dictionary = WorkShopStorage.get_unpaid_fee_summary()
	_expect(
		int(due_day_summary.get("total_unpaid_shekel", 0)) == 5,
		"Fee must stay unchanged through its due day."
	)

	_set_test_day(4)
	var first_overdue_summary: Dictionary = (
		WorkShopStorage.get_unpaid_fee_summary()
	)
	_expect(
		int(first_overdue_summary.get("total_unpaid_shekel", 0)) == 6,
		"Fee should gain a 10 percent rounded-up penalty after one overdue day."
	)
	_expect(
		int(first_overdue_summary.get("total_overdue_shekel", 0)) == 6,
		"Overdue fee should be reported in the overdue total."
	)

	_set_test_day(5)
	var second_overdue_summary: Dictionary = (
		WorkShopStorage.get_unpaid_fee_summary()
	)
	_expect(
		int(second_overdue_summary.get("total_unpaid_shekel", 0)) == 7,
		"Overdue penalty should grow linearly on each later day."
	)

	_set_test_day(20)
	var capped_overdue_summary: Dictionary = (
		WorkShopStorage.get_unpaid_fee_summary()
	)
	_expect(
		int(capped_overdue_summary.get("total_unpaid_shekel", 0)) == 10,
		"Overdue fee must stop at twice its base fee."
	)
	var held_lots: Array[Dictionary] = (
		WorkShopStorage.get_held_output_lot_summaries()
	)
	_expect(
		not held_lots.is_empty()
		and int(held_lots[0].get("fee_totals", {}).get("shekel", 0)) == 10,
		"Held Output UI data should expose the capped fee."
	)

	var held_lot_id: String = _find_held_lot_id("wet_mudbrick")
	var shekel_before_payment: int = int(Inventory.items.get("shekel", 0))
	var payment_result: Dictionary = WorkShopStorage.pay_output_lot(
		held_lot_id,
		Inventory
	)
	_expect(
		bool(payment_result.get("success", false)),
		"Overdue Held Output should unlock after its increased fee is paid."
	)
	_expect(
		int(Inventory.items.get("shekel", 0)) == shekel_before_payment - 10,
		"Paying overdue output should charge the capped fee."
	)

	var paid_fee_amount: int = int(
		WorkShopStorage.unpaid_claims_ledger[0].get("final_fee_shekel", 0)
	)
	_set_test_day(21)
	_expect(
		int(
			WorkShopStorage.unpaid_claims_ledger[0].get(
				"final_fee_shekel",
				0
			)
		) == paid_fee_amount,
		"Paid fees must stop receiving overdue penalties."
	)
	_expect(
		int(WorkShopStorage.get_unpaid_fee_summary().get("unpaid_count", 0)) == 0,
		"Paid output must no longer appear as an unpaid fee."
	)

func _set_test_day(day: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.day_changed.emit(day)

func _find_held_lot_id(item_id: String) -> String:
	for lot in WorkShopStorage.output_lots:
		var lot_items: Dictionary = lot.get("items", {})
		if int(lot_items.get(item_id, 0)) > 0:
			return str(lot.get("lot_id", ""))

	return ""

func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failures += 1
	push_error(message)
