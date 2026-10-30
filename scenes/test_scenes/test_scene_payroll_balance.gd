extends "res://scenes/test_scenes/test_scene_paid_production_journey.gd"
## First-period cash-flow sample. Natural RNG and needs; no balance overrides.
## Policy: sell available bricks instead of reserving ten for a yard upgrade.
## The parent records all cash, fees, sales, visits, payroll and Continue checks.

func _production_route() -> void:
	await super._production_route()
	if stopped or dried < 1:
		return
	measure("balance_first_batch")
	# Observe the remaining first-period sale window; keep the final day for bed.
	while not stopped and _has_route_time():
		await upkeep()
		if not _has_route_time():
			break
		if WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") > 0:
			await withdraw_bricks()
		await trade()
		await wait_minutes(60)
	measure("balance_sale_window_end")

func withdraw_bricks() -> void:
	if stopped or WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 0:
		return
	var fits: int = maxi(floori((Inventory.get_remaining_capacity() - 8.0) / ItemDatabase.get_item_data("sun_dried_mudbrick").weight), 0)
	if fits == 0:
		return
	await open_workshop()
	await press(ui(WorkshopMenuUI).manage_button)
	var storage_ui = ui(WorkshopStorageMenuUI)
	var slot = storage_ui.free_slots_by_item_id.get("sun_dried_mudbrick")
	if slot != null:
		var amount: int = mini(WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick"), fits)
		for index: int in range(amount):
			await press(slot)
		if amount > 0:
			await press(storage_ui.withdraw_button)
	await press(storage_ui.back_button)
	await press(ui(WorkshopMenuUI).close_button)

func finish() -> void:
	if phase == "write" and not production_started and not stopped and first_payment_observed:
		production_started = true
		await leave_home()
		await _production_route()
		if not stopped:
			# Upkeep may already have slept into the final paid day. Reuse that real
			# checkpoint: requiring another sleep would add an unobserved extra day.
			var saved_on_final_day: bool = TimeComponentManager.current_day == worker.payroll_paid_until_day and player.last_sleep_day == TimeComponentManager.current_day
			if not saved_on_final_day:
				while not player.can_sleep() and _within_period():
					await upkeep()
					if TimeComponentManager.current_day == worker.payroll_paid_until_day and player.last_sleep_day == TimeComponentManager.current_day:
						break
					await wait_minutes(30)
				if player.can_sleep():
					await sleep_home()
			if FileAccess.file_exists(checkpoint_path):
				var expected := FileAccess.open(EXPECTED_PATH, FileAccess.WRITE)
				expected.store_string(FileAccess.get_file_as_string(checkpoint_path))
				expected.close()
	release_input()
	var complete: bool = phase == "read" or (dried >= 1 and paid >= 7 and _within_period())
	var status: String = "FAIL" if failures else ("PASS" if complete else "PARTIAL")
	DirAccess.make_dir_recursive_absolute(RESULT_DIR)
	var result := {"status": status, "phase": phase, "failures": failures,
		"policy": "sell available bricks; observe first paid period; gather inputs",
		"first_period_only": true, "shaped": shaped, "dried": dried, "fees_paid": paid,
		"sold_bricks": sold_bricks, "settlements": settlements, "measurements": measurements,
		"visits": visits}
	var file := FileAccess.open(RESULT_DIR + phase + "-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PayrollBalanceSample ", phase, ": ", status)
	get_tree().paused = false
	var scene: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await _frames()
	get_tree().quit(1 if failures else (0 if complete else 2))
