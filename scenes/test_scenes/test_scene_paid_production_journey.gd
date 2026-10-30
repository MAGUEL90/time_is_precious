extends "res://scenes/test_scenes/test_scene_payroll_first_playthrough.gd"
## Extends the normal earned-money onboarding route; no grants or clock overrides.
## Stops before first-period expiry: renewal is deliberately outside this gate.
var production_started: bool = false
const RESULT_DIR: String = "user://paid_production_journey/"

func finish() -> void:
	if phase == "write" and not production_started and not stopped and first_payment_observed:
		production_started = true
		await leave_home()
		await _production_route()
		if not stopped:
			while not player.can_sleep() and _within_period():
				await upkeep()
				await wait_minutes(30)
			if player.can_sleep():
				await sleep_home()
				var expected := FileAccess.open(EXPECTED_PATH, FileAccess.WRITE)
				expected.store_string(FileAccess.get_file_as_string(checkpoint_path))
				expected.close()
	release_input()
	var complete: bool = phase == "read" or (dried >= 1 and paid >= 7 and _within_period())
	var status: String = "FAIL" if failures else ("PASS" if complete else "PARTIAL")
	DirAccess.make_dir_recursive_absolute(RESULT_DIR)
	var result := {"status": status, "phase": phase, "failures": failures,
		"first_period_only": true, "shaped": shaped, "dried": dried, "fees_paid": paid,
		"sold_bricks": sold_bricks, "settlements": settlements, "measurements": measurements,
		"visits": visits}
	var file := FileAccess.open(RESULT_DIR + phase + "-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PaidProductionJourney ", phase, ": ", status)
	get_tree().paused = false
	var scene: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await _frames()
	get_tree().quit(1 if failures else (0 if complete else 2))

func _within_period() -> bool:
	return worker != null and TimeComponentManager.current_day <= worker.payroll_paid_until_day

func _has_route_time() -> bool:
	# Reserve the final paid day for sleep/Continue; do not rely on missing renewal.
	return worker != null and TimeComponentManager.current_day < worker.payroll_paid_until_day

func _production_route() -> void:
	var needs := {"wood_log": 6, "clay_lump": 12, "reed_bundle": 8}
	var sites := {"wood_log": "WoodSite", "clay_lump": "ClaySiteA", "reed_bundle": "ReedSite", "straw_bundle": "StrawSite", "water_jar": "WaterSite"}
	while not stopped and plot.construction.phase != "built" and _has_route_time():
		await upkeep()
		if not _has_route_time():
			break
		if plot.construction.phase == "empty":
			var missing := ""
			for id: String in needs:
				if Inventory.items.get(id, 0) < needs[id]:
					missing = id
					break
			if missing.is_empty():
				await construct()
			else:
				await gather(sites[missing])
		else:
			await trade()
			if Inventory.items.get("wood_log", 0) < 10 and player.fatigue < 0.5:
				await gather("WoodSite")
			else:
				await wait_minutes(60)
	if stopped or plot.construction.phase != "built":
		return
	measure("built_paid")
	await deposit()
	while not stopped and dried < 1 and _has_route_time():
		await upkeep()
		if not _has_route_time():
			break
		await trade()
		if Inventory.items.get("shekel", 0) < 7:
			if Inventory.items.get("wood_log", 0) < 6:
				await gather("WoodSite")
			else:
				await wait_minutes(60)
			continue
		var required: Dictionary = JOB.inputs.duplicate()
		if WorkshopFacilityManager.get_facility_level("drying_yard") == 0:
			for id: String in WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 1):
				required[id] = required.get(id, 0) + WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 1)[id]
		var missing := ""
		for id: String in required:
			if WorkShopStorage.get_free_item_quantity(id) + Inventory.items.get(id, 0) < required[id]:
				missing = id
				break
		if not missing.is_empty():
			await gather(sites[missing])
			await deposit()
			continue
		await deposit()
		if WorkshopFacilityManager.get_facility_level("drying_yard") == 0:
			await yard(1)
		await shape()
		await pay_output("wet_mudbrick")
		if WorkShopStorage.get_free_item_quantity("wet_mudbrick") >= 20:
			await dry()
			await pay_output("sun_dried_mudbrick")
			await withdraw_bricks()
			await trade()
	measure("production_end")

func pay_output(id: String) -> void:
	var treasury_before: int = CityStockManager.treasury_shekel
	await super.pay_output(id)
	_expect(CityStockManager.treasury_shekel == treasury_before, "Facility fee never debits city payroll funds")

func trade() -> void:
	var treasury_before: int = CityStockManager.treasury_shekel
	await super.trade()
	_expect(CityStockManager.treasury_shekel == treasury_before, "Merchant proceeds stay in player wallet")
