extends Node

const DRYING_PROCESS: ProcessData = preload(
	"res://resources/process_data/drying_mudbrick.tres"
)

var failures: int = 0
var _watch_facility_transaction: bool = false
var _facility_busy_observed: bool = false
var _time_advance_rejected: bool = false
var _reentrant_upgrade_result: Dictionary = {}
var _facility_level_signal_saw_paid_inventory: bool = false
var _reentrant_level_change_rejected: bool = false
var _new_slot_process_started: bool = false
var _expected_inventory_at_level_signal: Dictionary = {}

func _ready() -> void:
	WorkerDatabase.reload_workers()
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
	Inventory.max_load = 100.0
	WorkShopStorage.items.clear()
	WorkShopStorage.output_lots.clear()
	WorkShopStorage.claimable_outputs.clear()
	WorkShopStorage.unpaid_claims_ledger.clear()
	WorkShopStorage.max_load = 200.0
	WorkShopStorage.unpaid_fee_due_days = 3
	WorkShopStorage.overdue_penalty_percent_per_day = 10
	WorkShopStorage.overdue_fee_max_multiplier = 2.0
	ProcessManager.stations.clear()
	WorkshopFacilityManager.facility_contributions.clear()
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

	var first_level_requirements: Dictionary = (
		WorkshopFacilityManager.get_facility_upgrade_requirements(
			"drying_yard",
			1
		)
	)
	WorkShopStorage.add_bulk_item(first_level_requirements)
	WorkShopStorage.add_item("wet_mudbrick", 20)
	var missing_preview: Dictionary = (
		WorkshopFacilityManager.get_facility_upgrade_preview("drying_yard")
	)
	_expect(
		not bool(missing_preview.get("can_upgrade", true))
		and not missing_preview.get("missing_items", {}).is_empty(),
		"Drying Yard construction must not count materials in Workshop Free Stock."
	)

	_facility_busy_observed = false
	_time_advance_rejected = false
	_reentrant_upgrade_result.clear()
	_facility_level_signal_saw_paid_inventory = false
	_reentrant_level_change_rejected = false
	_new_slot_process_started = false
	_watch_facility_transaction = true
	Inventory.items_changed.connect(_observe_facility_upgrade_transaction)
	WorkshopFacilityManager.facility_level_changed.connect(
		_observe_facility_level_commit
	)
	var workshop_stock_after_first_upgrade: Dictionary = {}
	for level: int in range(1, 3):
		var requirements: Dictionary = (
			WorkshopFacilityManager.get_facility_upgrade_requirements(
				"drying_yard",
				level
			)
		)
		_expect(
			Inventory.try_add_bulk_items(requirements),
			"Level %d materials fit in a normal Inventory trip." % level
		)
		var inventory_before_upgrades: Dictionary = Inventory.items.duplicate(true)

		if level == 1:
			_expected_inventory_at_level_signal = inventory_before_upgrades.duplicate(true)
			for item_id_value: Variant in requirements.keys():
				var item_id: String = str(item_id_value)
				var remaining: int = int(_expected_inventory_at_level_signal.get(item_id, 0)) - int(requirements[item_id_value])
				if remaining > 0:
					_expected_inventory_at_level_signal[item_id] = remaining
				else:
					_expected_inventory_at_level_signal.erase(item_id)
		var upgrade_result: Dictionary = (
			WorkshopFacilityManager.upgrade_facility(
				"drying_yard"
			)
		)
		_expect(
			bool(upgrade_result.get("success", false)),
			"Drying Yard level %d should consume player Inventory materials and build."
			% level
		)
		var expected_inventory: Dictionary = inventory_before_upgrades.duplicate(true)
		for item_id_value in requirements.keys():
			var item_id: String = str(item_id_value)
			var expected_quantity: int = int(expected_inventory.get(item_id, 0)) - int(requirements[item_id_value])
			if expected_quantity > 0:
				expected_inventory[item_id] = expected_quantity
			else:
				expected_inventory.erase(item_id)
			_expect(
				int(Inventory.items.get(item_id, 0)) == expected_quantity,
				"Level %d should charge required %s to player Inventory." % [
					level,
					item_id
				]
			)
		_expect(
			Inventory.items == expected_inventory,
			"Level %d should consume the complete material batch atomically." % level
		)
		if level == 1:
			for item_id_value: Variant in first_level_requirements.keys():
				var item_id: String = str(item_id_value)
				_expect(
					WorkShopStorage.get_free_item_quantity(item_id) == int(first_level_requirements[item_id_value]),
					"Building the Yard must not charge %s from Workshop Free Stock." % item_id
				)
			_expect(
				_facility_busy_observed
				and _time_advance_rejected
				and not bool(_reentrant_upgrade_result.get("success", true)),
				"Inventory callbacks must see the facility transaction lock, reject clock advancement, and reject a nested upgrade."
			)
			_expect(
				WorkshopFacilityManager.get_facility_level("drying_yard") == 1,
				"A nested upgrade must not advance the Yard twice."
			)
			_expect(
				_facility_level_signal_saw_paid_inventory
				and _reentrant_level_change_rejected
				and _new_slot_process_started
				and WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 0,
				"Level observers must run after the Inventory payment commits; a process may then occupy the paid-for slot and consume workshop input."
			)
			workshop_stock_after_first_upgrade = WorkShopStorage.items.duplicate(true)
		else:
			_expect(
				WorkShopStorage.items == workshop_stock_after_first_upgrade,
				"Level %d should leave Workshop Free Stock unchanged." % level
			)
		_watch_facility_transaction = false
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

	var third_level_requirements: Dictionary = (
		WorkshopFacilityManager.get_facility_upgrade_requirements(
			"drying_yard",
			3
		)
	)
	var first_trip: Dictionary = {
		"wood_log": 6,
		"reed_bundle": 10,
		"sun_dried_mudbrick": 18
	}
	_expect(
		is_equal_approx(
			Inventory.get_bulk_item_total_weight(first_trip),
			Inventory.max_load
		)
		and Inventory.try_add_bulk_items(first_trip),
		"The first level-3 material trip exactly fits the normal 100-weight Inventory."
	)
	var first_contribution: Dictionary = WorkshopFacilityManager.contribute_facility_materials(
		"drying_yard"
	)
	_expect(
		bool(first_contribution.get("success", false))
		and Inventory.items.is_empty()
		and WorkshopFacilityManager.facility_contributions.get("drying_yard", {}).get("items", {}) == first_trip,
		"A full first trip is atomically stored as a partial level-3 contribution."
	)
	var partial_preview: Dictionary = WorkshopFacilityManager.get_facility_upgrade_preview(
		"drying_yard"
	)
	_expect(
		not bool(partial_preview.get("can_upgrade", true))
		and partial_preview.get("missing_items", {}).get("sun_dried_mudbrick", 0) == 2,
		"The Yard still needs two bricks after the first contribution trip."
	)
	var full_inventory_quantity: int = floori(
		Inventory.max_load / Inventory.get_item_data("clay_lump").weight
	)
	_expect(
		Inventory.try_add_item("clay_lump", full_inventory_quantity),
		"The test can fill the player's bag with other carried materials."
	)
	var full_inventory_before_refund: Dictionary = Inventory.items.duplicate(true)
	var blocked_refund: Dictionary = WorkshopFacilityManager.refund_facility_contributions(
		"drying_yard"
	)
	_expect(
		not bool(blocked_refund.get("success", true))
		and Inventory.items == full_inventory_before_refund
		and WorkshopFacilityManager.facility_contributions.has("drying_yard"),
		"A full-bag refund must preserve both Inventory and committed materials."
	)
	Inventory.remove_item("clay_lump", full_inventory_quantity)
	var successful_refund: Dictionary = WorkshopFacilityManager.refund_facility_contributions(
		"drying_yard"
	)
	_expect(
		bool(successful_refund.get("success", false))
		and Inventory.items == first_trip
		and not WorkshopFacilityManager.facility_contributions.has("drying_yard"),
		"After freeing capacity, refund returns every contributed item exactly once."
	)
	_expect(
		bool(WorkshopFacilityManager.contribute_facility_materials("drying_yard").get("success", false)),
		"The refunded first trip can be explicitly contributed again."
	)
	_expect(
		Inventory.try_add_item(
			"sun_dried_mudbrick",
			int(third_level_requirements.get("sun_dried_mudbrick", 0)) - 18
		),
		"The remaining level-3 bricks fit on a second Inventory trip."
	)
	_expect(
		bool(WorkshopFacilityManager.contribute_facility_materials("drying_yard").get("success", false)),
		"The second trip completes the level-3 contribution escrow."
	)
	var complete_contribution_preview: Dictionary = WorkshopFacilityManager.get_facility_upgrade_preview(
		"drying_yard"
	)
	_expect(
		bool(complete_contribution_preview.get("can_upgrade", false))
		and complete_contribution_preview.get("missing_items", {}).is_empty()
		and Inventory.items.is_empty(),
		"Two trips fully fund level 3 while respecting the normal Inventory capacity."
	)
	var complete_escrow: Dictionary = WorkshopFacilityManager.facility_contributions.get(
		"drying_yard",
		{}
	).get("items", {}).duplicate(true)
	var complete_refund_plan: Dictionary = complete_contribution_preview.get(
		"refund_plan",
		{}
	)
	_expect(
		is_equal_approx(
			Inventory.get_bulk_item_total_weight(complete_escrow),
			108.0
		)
		and Inventory.get_bulk_item_total_weight(complete_escrow) > Inventory.max_load
		and not complete_refund_plan.is_empty()
		and complete_refund_plan != complete_escrow
		and Inventory.get_bulk_item_total_weight(complete_refund_plan) <= Inventory.max_load,
		"A complete 108-weight level-3 escrow previews a bounded partial refund trip."
	)
	var first_refund_trip: Dictionary = WorkshopFacilityManager.refund_facility_contributions(
		"drying_yard"
	)
	var escrow_after_first_refund: Dictionary = WorkshopFacilityManager.facility_contributions.get(
		"drying_yard",
	{}
	).get("items", {})
	var expected_escrow_after_first_refund: Dictionary = complete_escrow.duplicate(true)
	for item_id_value: Variant in complete_refund_plan.keys():
		var item_id: String = str(item_id_value)
		var remaining_quantity: int = int(expected_escrow_after_first_refund[item_id]) - int(
			complete_refund_plan[item_id_value]
		)
		if remaining_quantity > 0:
			expected_escrow_after_first_refund[item_id] = remaining_quantity
		else:
			expected_escrow_after_first_refund.erase(item_id)
	_expect(
		bool(first_refund_trip.get("success", false))
		and first_refund_trip.get("refunded_this_batch", {}) == complete_refund_plan
		and Inventory.items == complete_refund_plan
		and escrow_after_first_refund == expected_escrow_after_first_refund,
		"The first refund trip returns only the quoted batch and keeps the exact remainder committed."
	)
	for item_id_value: Variant in complete_refund_plan.keys():
		Inventory.remove_item(
			str(item_id_value),
			int(complete_refund_plan[item_id_value])
		)
	var second_refund_preview: Dictionary = WorkshopFacilityManager.get_facility_upgrade_preview(
		"drying_yard"
	)
	var second_refund_plan: Dictionary = second_refund_preview.get("refund_plan", {})
	var second_refund_trip: Dictionary = WorkshopFacilityManager.refund_facility_contributions(
		"drying_yard"
	)
	_expect(
		second_refund_plan == escrow_after_first_refund
		and bool(second_refund_trip.get("success", false))
		and second_refund_trip.get("refunded_this_batch", {}) == escrow_after_first_refund
		and Inventory.items == escrow_after_first_refund
		and not WorkshopFacilityManager.facility_contributions.has("drying_yard"),
		"After unloading Inventory, the second refund trip returns the remaining escrow exactly once."
	)
	var recontribute_remainder: Dictionary = WorkshopFacilityManager.contribute_facility_materials(
		"drying_yard"
	)
	_expect(
		bool(recontribute_remainder.get("success", false))
		and Inventory.items.is_empty(),
		"The refunded remainder can be committed again before returning for the first batch."
	)
	_expect(
		Inventory.try_add_bulk_items(complete_refund_plan),
		"The first refund batch fits on a separate trip after the remainder was committed."
	)
	var recontribute_first_batch: Dictionary = WorkshopFacilityManager.contribute_facility_materials(
		"drying_yard"
	)
	_expect(
		bool(recontribute_first_batch.get("success", false))
		and Inventory.items.is_empty()
		and WorkshopFacilityManager.facility_contributions.get("drying_yard", {}).get("items", {}) == complete_escrow,
		"Both explicit trips restore the complete level-3 escrow without losing or duplicating items."
	)
	var level_three_result: Dictionary = WorkshopFacilityManager.upgrade_facility(
		"drying_yard"
	)
	_expect(
		bool(level_three_result.get("success", false))
		and WorkshopFacilityManager.get_facility_level("drying_yard") == 3
		and Inventory.items.is_empty()
		and not WorkshopFacilityManager.facility_contributions.has("drying_yard"),
		"Level 3 consumes committed materials exactly once and completes without exceeding Inventory capacity."
	)

	if Inventory.items_changed.is_connected(_observe_facility_upgrade_transaction):
		Inventory.items_changed.disconnect(_observe_facility_upgrade_transaction)
	if WorkshopFacilityManager.facility_level_changed.is_connected(_observe_facility_level_commit):
		WorkshopFacilityManager.facility_level_changed.disconnect(_observe_facility_level_commit)
	_watch_facility_transaction = false
	_expect(
		not WorkshopFacilityManager.is_transaction_busy(),
		"Facility transaction lock must be released after payment."
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
	var rejected_payment: Dictionary = WorkShopStorage.pay_output_lot(
		wet_lot_id,
		Inventory
	)
	_expect(
		not bool(rejected_payment.get("success", false)),
		"An empty wallet must not pay the Shape fee."
	)
	_expect(
		int(Inventory.items.get("shekel", 0)) == 0
		and WorkShopStorage.get_held_item_quantity("wet_mudbrick") == 20
		and WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 0,
		"Rejected payment must preserve the wallet and all Held Output."
	)
	Inventory.add_item("shekel", 20)
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

func _observe_facility_upgrade_transaction() -> void:
	if not _watch_facility_transaction:
		return
	_facility_busy_observed = WorkshopFacilityManager.is_transaction_busy()
	_time_advance_rejected = not TimeComponentManager.can_advance_time()
	_reentrant_upgrade_result = WorkshopFacilityManager.upgrade_facility(
		"drying_yard"
	)

func _observe_facility_level_commit(
	facility_id: String,
	level: int,
	_station_slots: int
) -> void:
	if not _watch_facility_transaction or facility_id != "drying_yard" or level != 1:
		return
	_facility_level_signal_saw_paid_inventory = (
		Inventory.items == _expected_inventory_at_level_signal
	)
	_reentrant_level_change_rejected = not WorkshopFacilityManager.set_facility_level(
		"drying_yard",
		2
	)
	_new_slot_process_started = ProcessManager.start_registered_process(
		"drying_mudbrick",
		20
	)
