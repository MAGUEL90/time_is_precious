extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

## Actual city checkpoint for an idle resignation. Own user:// test path only.
const RESIGN_CHECKPOINT: String = "user://idle_resignation_save_test/checkpoint.json"
const RESIGNEE_ID: String = "saved_idle_resignee"

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await load_content()
	for _frame: int in range(2):
		await get_tree().process_frame
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	city_storage = WorkStateRuntime.get_node("CityToolStorage")
	wood_storage = runtime.get_node("CityStorageArea/DeliveryPoint")
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = RESIGN_CHECKPOINT
	_remove_test_checkpoints()
	_prepare_city_state()
	var citizen := CitizenData.new()
	citizen.citizen_id = RESIGNEE_ID
	citizen.display_name = "Saved resignee"
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.profession = WorkerData.Profession.LABORER
	citizen.satisfaction = 0.5
	citizen.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(citizen)
	_expect(CitizenManager.register_applicant(RESIGNEE_ID, WorkerData.Profession.LABORER), "The save fixture registers a real applicant.")
	var worker: WorkerData = WorkerDatabase.hire_applicant(RESIGNEE_ID)
	_expect(worker != null, "The save fixture buys the original contract.")
	if worker == null:
		await _finish_resignation_save()
		return
	worker.profession_xp = 17
	_expect(city_storage.allocate(GLOVE_UNIT_ID, RESIGNEE_ID), "The hired worker receives an owned tool.")
	var wallet_after_hire: int = int(Inventory.items.get("shekel", 0))
	citizen.satisfaction = 0.05
	city_storage.items.erase("barley_bread")
	city_storage.food_portions.clear()
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	TimeComponentManager.advance_minutes(16 * 60)
	_expect(citizen.satisfaction == 0.0 and not WorkerDatabase.has_worker_data(RESIGNEE_ID)
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"The real day transition resigns the idle worker after a shortage.")
	_expect(WorkerDatabase.dismissed_workers.get(RESIGNEE_ID) == worker
		and not city_storage.has_equipped(RESIGNEE_ID, "basic_glove")
		and int(Inventory.items.get("shekel", 0)) == wallet_after_hire,
		"Resignation returns equipment and keeps progression without a contract refund.")
	_expect(store.save_checkpoint(), "The post-resignation city checkpoint saves: " + store.last_error)
	var saved_bytes: String = FileAccess.get_file_as_string(RESIGN_CHECKPOINT)
	citizen.satisfaction = 0.9
	worker.profession_xp = 99
	Inventory.add_item("shekel", 7)
	_expect(store.load_checkpoint(), "The idle-resignation checkpoint loads: " + store.last_error)
	var restored: CitizenData = CitizenManager.get_citizen(RESIGNEE_ID)
	var archived: WorkerData = WorkerDatabase.dismissed_workers.get(RESIGNEE_ID)
	_expect(restored != null and restored.satisfaction == 0.0
		and restored.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and not WorkerDatabase.has_worker_data(RESIGNEE_ID), "Continue retains zero Satisfaction and unemployment.")
	_expect(archived != null and archived.profession_xp == 17 and archived.payroll_start_day == -1
		and archived.payroll_paid_until_day == -1 and not city_storage.has_equipped(RESIGNEE_ID, "basic_glove")
		and int(Inventory.items.get("shekel", 0)) == wallet_after_hire,
		"Continue retains XP, forfeited contract, returned equipment and wallet.")
	_expect(FileAccess.get_file_as_string(RESIGN_CHECKPOINT) == saved_bytes and store.load_checkpoint(),
		"Repeated Continue neither rewrites the save nor reapplies a resignation.")
	# An existing application can outlive a drop in Satisfaction.  Persist it
	# below the threshold and verify Continue does not make it hireable again.
	restored = CitizenManager.get_citizen(RESIGNEE_ID)
	restored.satisfaction = 0.5
	_expect(CitizenManager.evaluate_daily_applications() >= 1,
		"The restored resident can apply at exactly 50%.")
	restored.satisfaction = 0.499999
	_expect(store.save_checkpoint(), "A below-threshold stale applicant checkpoint saves.")
	var applicant_bytes: String = FileAccess.get_file_as_string(RESIGN_CHECKPOINT)
	_expect(store.load_checkpoint(), "A stale applicant checkpoint loads: " + store.last_error)
	restored = CitizenManager.get_citizen(RESIGNEE_ID)
	var wallet_before_rejected_hire: int = int(Inventory.items.get("shekel", 0))
	_expect(restored.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and not CitizenManager.get_all_applicants().has(restored)
		and WorkerDatabase.hire_applicant(RESIGNEE_ID) == null
		and int(Inventory.items.get("shekel", 0)) == wallet_before_rejected_hire,
		"Continue keeps the stale application but prevents visibility, hire, and payment.")
	_expect(FileAccess.get_file_as_string(RESIGN_CHECKPOINT) == applicant_bytes and store.load_checkpoint(),
		"Repeated Continue keeps the stale applicant file unchanged.")
	# Simulate a valid older checkpoint whose worker was already idle at zero.
	# It must be reconciled after all owners restore, without rewriting the file.
	TimeComponentManager.advance_minutes(8 * 60)
	restored = CitizenManager.get_citizen(RESIGNEE_ID)
	restored.satisfaction = 0.5
	CitizenManager.evaluate_daily_applications()
	_expect(CitizenManager.get_all_applicants().has(restored),
		"The restored applicant reappears after recovering to 50%.")
	var rehired: WorkerData = WorkerDatabase.hire_applicant(RESIGNEE_ID)
	_expect(rehired != null, "The recovered resident buys a new contract before the legacy probe.")
	if rehired != null:
		restored.satisfaction = 0.0
		_expect(store.save_checkpoint(), "A legacy-shaped zero-Satisfaction worker checkpoint saves.")
		var legacy_bytes: String = FileAccess.get_file_as_string(RESIGN_CHECKPOINT)
		var wallet_before_load: int = int(Inventory.items.get("shekel", 0))
		_expect(store.load_checkpoint(), "A checkpoint with an idle zero-Satisfaction worker loads: " + store.last_error)
		restored = CitizenManager.get_citizen(RESIGNEE_ID)
		archived = WorkerDatabase.dismissed_workers.get(RESIGNEE_ID)
		_expect(restored.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
			and not WorkerDatabase.has_worker_data(RESIGNEE_ID) and archived != null
			and archived.payroll_paid_until_day == -1 and int(Inventory.items.get("shekel", 0)) == wallet_before_load,
			"Continue resigns the idle zero-Satisfaction worker without refund or loss of identity.")
		_expect(FileAccess.get_file_as_string(RESIGN_CHECKPOINT) == legacy_bytes,
			"Reconciling an older zero-Satisfaction checkpoint leaves its file unchanged.")
	await _finish_resignation_save()

func _remove_test_checkpoints() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(RESIGN_CHECKPOINT + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RESIGN_CHECKPOINT + suffix))

func _finish_resignation_save() -> void:
	_remove_test_checkpoints()
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	print("IdleResignationSaveTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
