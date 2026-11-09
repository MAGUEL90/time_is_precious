extends "res://scenes/test_scenes/test_scene_city_save.gd"

const WORKSITE_SCHEMA = preload("res://scenes/new_scenes/save_game/city_save_worksites.gd")
const LEGACY_CHECKPOINT_PATH: String = "user://worksite_legacy_adapter/legacy_v5.json"
const CURRENT_OUTPUT_PATH: String = "user://worksite_legacy_adapter/current_output.json"
const REJECTED_CHECKPOINT_PATH: String = "user://worksite_legacy_adapter/rejected.json"


func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	var config_root: String = OS.get_environment("XDG_CONFIG_HOME")
	var cache_root: String = OS.get_environment("XDG_CACHE_HOME")
	_expect(data_root.is_absolute_path() and config_root.is_absolute_path() and cache_root.is_absolute_path(),
		"Use fresh absolute XDG data, config and cache roots.")
	var user_root: String = ProjectSettings.globalize_path("user://")
	_expect(user_root.begins_with(data_root.trim_suffix("/") + "/"), "user:// stays inside the isolated XDG data root.")
	if failures > 0:
		_finish()
		return
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	await get_tree().process_frame
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = LEGACY_CHECKPOINT_PATH
	_clear_checkpoint_sidecars(LEGACY_CHECKPOINT_PATH)
	Inventory.items.assign({"date_cluster": 2})
	storage.items = {"wood_log": 7}
	_expect(Inventory.items == {"date_cluster": 2} and storage.items == {"wood_log": 7},
		"The preservation fixture starts with nonempty player and city inventory.")
	var current_document: Dictionary = store.snapshot.capture(content)
	_expect(not current_document.is_empty(), "The current city checkpoint fixture captures.")
	if current_document.is_empty():
		_finish()
		return

	var values = VALUES.new()
	var decoded_current: Variant = values.decode(current_document.state)
	_expect(values.error.is_empty() and decoded_current is Dictionary, "The current checkpoint state decodes: " + values.error)
	if not decoded_current is Dictionary:
		_finish()
		return
	var current_raw: Dictionary = decoded_current
	var worksite: Node = content.get_node("YSortWorld/WorkerRuntime")
	var current_valid: bool = store.snapshot.prepare(current_document, content)
	_expect(current_valid, "The current control checkpoint validates: " + store.snapshot.error)
	if not current_valid:
		_finish()
		return
	var current_control: Dictionary = store.snapshot.prepared.duplicate(true)
	var legacy_raw: Dictionary = current_raw.duplicate(true)
	legacy_raw.worksites.schema_version = 5
	for site_id: String in WORKSITE_SCHEMA.NEW_SITE_IDS:
		legacy_raw.worksites.sites.erase(site_id)
	var legacy_stocks: Dictionary = {
		"ClaySiteA": 50,
		"WoodSite": 0,
		"ReedSite": 13,
		"StrawSite": 17,
		"WaterSite": 19,
	}
	for site_id: String in WORKSITE_SCHEMA.LEGACY_SITE_IDS:
		_expect(legacy_raw.worksites.sites.has(site_id), "The v5 fixture starts with legacy site " + site_id + ".")
		var site_record: Dictionary = legacy_raw.worksites.sites[site_id]
		site_record.stock = int(legacy_stocks[site_id])
		site_record.erase("respawn_started_at")
		site_record.erase("respawn_due_at")
	var legacy_document: Dictionary = current_document.duplicate(true)
	var encoded_legacy: Variant = values.encode(legacy_raw)
	_expect(values.error.is_empty() and encoded_legacy is Dictionary, "The v5 fixture encodes: " + values.error)
	if not encoded_legacy is Dictionary:
		_finish()
		return
	legacy_document.state = encoded_legacy
	var legacy_bytes: String = JSON.stringify(legacy_document, "", true, true)
	var live_sentinel: Dictionary = store.snapshot.capture(content)
	var prepared: bool = store.snapshot.prepare(legacy_document, content)
	_expect(prepared, "A current city checkpoint with a valid nested v5 worksite registry migrates: " + store.snapshot.error)
	_expect(live_sentinel == store.snapshot.capture(content), "Preparing v5 data does not mutate live state.")
	_expect(JSON.stringify(legacy_document, "", true, true) == legacy_bytes, "Preparing v5 data leaves the input document unchanged.")
	if not prepared:
		_finish()
		return

	var staged: Dictionary = store.snapshot.prepared.duplicate(true)
	_expect(int(staged.worksites.schema_version) == WORKSITE_SCHEMA.SCHEMA_VERSION,
		"The staged worksite snapshot uses the current schema.")
	for site_id: String in WORKSITE_SCHEMA.LEGACY_SITE_IDS:
		_expect(int(staged.worksites.sites[site_id].stock) == int(legacy_stocks[site_id]),
			"Existing legacy stock is preserved for " + site_id + ".")
	_expect(int(staged.worksites.sites.ClaySiteA.stock) == 50
		and int(staged.worksites.sites.ClaySiteA.stock) > int(worksite.sites[&"ClaySiteA"].get("deposit_capacity")),
		"Legacy stock above the current configured capacity is not truncated.")
	var checkpoint_minute: int = int(legacy_raw.clock.current_day) * 1440 \
		+ int(legacy_raw.clock.current_hour) * 60 + int(legacy_raw.clock.current_minute)
	_expect(int(staged.worksites.sites.WoodSite.respawn_started_at) == checkpoint_minute
		and int(staged.worksites.sites.WoodSite.respawn_due_at) == checkpoint_minute + WORKSITE_SCHEMA.MAX_RESPAWN_DELAY_MINUTES,
		"A legacy zero stock keeps the existing conservative respawn initialization.")
	var staged_sites: Dictionary = staged.worksites.sites
	for site_id: String in WORKSITE_SCHEMA.NEW_SITE_IDS:
		if worksite.sites.has(StringName(site_id)):
			var capacity: Variant = worksite.sites[StringName(site_id)].get("deposit_capacity")
			var initialized: Dictionary = staged_sites[site_id]
			_expect(typeof(capacity) == TYPE_INT and int(capacity) > 0 and int(initialized.stock) == int(capacity),
				"New site " + site_id + " initializes from its runtime capacity.")
			_expect(initialized.size() == 1 and not initialized.has("offset")
				and not initialized.has("deposit_capacity") and not initialized.has("respawn_started_at"),
				"New site " + site_id + " receives only its initialized stock record.")
		else:
			_expect(not staged_sites.has(site_id), "An absent authored site is not invented: " + site_id + ".")
	_expect(staged_sites.size() == worksite.sites.size(), "Migration produces exactly the live authored worksite registry.")
	var staged_other: Dictionary = staged.duplicate(true)
	var expected_other: Dictionary = current_control.duplicate(true)
	staged_other.erase("worksites")
	expected_other.erase("worksites")
	var compare_codec = VALUES.new()
	_expect(compare_codec.encode(staged_other) == compare_codec.encode(expected_other),
		"Nested worksite migration preserves every unrelated owner under the current codec.")
	var staged_worksites: Dictionary = staged.worksites.duplicate(true)
	var expected_worksites: Dictionary = current_control.worksites.duplicate(true)
	for worksite_field: String in ["schema_version", "sites"]:
		staged_worksites.erase(worksite_field)
		expected_worksites.erase(worksite_field)
	_expect(compare_codec.encode(staged_worksites) == compare_codec.encode(expected_worksites),
		"Nested v5 migration preserves all worksite fields other than schema and site records.")

	_test_strict_rejections(legacy_document, legacy_raw, current_document, current_raw, live_sentinel)

	_clear_checkpoint_sidecars(LEGACY_CHECKPOINT_PATH)
	_write_text(LEGACY_CHECKPOINT_PATH, legacy_bytes)
	_expect(store.load_checkpoint(), "Disk Load accepts the staged v5 worksite checkpoint: " + store.last_error)
	_expect(FileAccess.get_file_as_string(LEGACY_CHECKPOINT_PATH) == legacy_bytes,
		"Loading a migrated checkpoint preserves the original file bytes.")
	var after_legacy_document: Dictionary = store.snapshot.capture(content)
	_expect(not after_legacy_document.is_empty(), "The migrated city remains capturable after disk Load.")
	if after_legacy_document.is_empty():
		_finish()
		return
	var after_legacy_load: Dictionary = VALUES.new().decode(after_legacy_document.state)
	var loaded_other: Dictionary = after_legacy_load.duplicate(true)
	var expected_loaded_other: Dictionary = staged.duplicate(true)
	loaded_other.erase("worksites")
	expected_loaded_other.erase("worksites")
	_expect(compare_codec.encode(loaded_other) == compare_codec.encode(expected_loaded_other),
		"Disk Load preserves every unrelated owner under the current codec.")
	for site_id: String in WORKSITE_SCHEMA.LEGACY_SITE_IDS:
		_expect(int(after_legacy_load.worksites.sites[site_id].stock) == int(legacy_stocks[site_id]),
			"Disk Load preserves legacy stock for " + site_id + ".")
	for site_id: String in ["WoodSiteD", "WoodSiteE"]:
		var capacity: int = int(worksite.sites[StringName(site_id)].get("deposit_capacity"))
		_expect(int(after_legacy_load.worksites.sites[site_id].stock) == capacity,
			"Disk Load initializes " + site_id + " from configured capacity.")

	_test_current_depletion_roundtrip(worksite, current_raw)
	_test_rejected_disk_preservation(legacy_document, legacy_raw, legacy_bytes)
	_finish()


func _test_strict_rejections(legacy_document: Dictionary, legacy_raw: Dictionary, current_document: Dictionary,
		current_raw: Dictionary, sentinel: Dictionary) -> void:
	var missing_legacy: Dictionary = legacy_raw.duplicate(true)
	missing_legacy.worksites.sites.erase("WaterSite")
	_assert_rejected_raw(legacy_document, missing_legacy, sentinel, "Legacy registry missing WaterSite")
	var extra_legacy: Dictionary = legacy_raw.duplicate(true)
	extra_legacy.worksites.sites["UnknownSite"] = {"stock": 1}
	_assert_rejected_raw(legacy_document, extra_legacy, sentinel, "Legacy registry with an unknown site")
	for site_id: String in ["WoodSiteD", "WoodSiteE"]:
		var injected: Dictionary = legacy_raw.duplicate(true)
		injected.worksites.sites[site_id] = {"stock": 1}
		_assert_rejected_raw(legacy_document, injected, sentinel, "Legacy registry injected with " + site_id)
	for stock_value: Variant in [true, -1, 1.5, WORKSITE_SCHEMA.MAX_COUNT + 1]:
		var malformed_stock: Dictionary = legacy_raw.duplicate(true)
		malformed_stock.worksites.sites.WoodSite.stock = stock_value
		_assert_rejected_raw(legacy_document, malformed_stock, sentinel, "Legacy malformed stock " + str(stock_value))
	var legacy_timer: Dictionary = legacy_raw.duplicate(true)
	legacy_timer.worksites.sites.WoodSite.respawn_started_at = 0
	legacy_timer.worksites.sites.WoodSite.respawn_due_at = 2880
	_assert_rejected_raw(legacy_document, legacy_timer, sentinel, "v5 site with unsupported timer fields")
	var legacy_config: Dictionary = legacy_raw.duplicate(true)
	legacy_config.worksites.sites.WoodSite.deposit_capacity = 99
	_assert_rejected_raw(legacy_document, legacy_config, sentinel, "v5 site with injected configuration")

	for site_id: String in ["WoodSiteD", "WoodSiteE"]:
		var missing_current: Dictionary = current_raw.duplicate(true)
		missing_current.worksites.sites.erase(site_id)
		_assert_rejected_raw(current_document, missing_current, sentinel, "Current schema missing " + site_id)
	var extra_current: Dictionary = current_raw.duplicate(true)
	extra_current.worksites.sites["UnknownSite"] = {"stock": 1}
	_assert_rejected_raw(current_document, extra_current, sentinel, "Current schema with an unknown site")
	var current_config: Dictionary = current_raw.duplicate(true)
	current_config.worksites.sites.WoodSiteD.deposit_capacity = 99
	_assert_rejected_raw(current_document, current_config, sentinel, "Current site with injected configuration")
	var current_timer: Dictionary = current_raw.duplicate(true)
	var now: int = int(current_timer.clock.current_day) * 1440 \
		+ int(current_timer.clock.current_hour) * 60 + int(current_timer.clock.current_minute)
	current_timer.worksites.sites.WoodSiteD.stock = 0
	current_timer.worksites.sites.WoodSiteD.respawn_started_at = now
	current_timer.worksites.sites.WoodSiteD.respawn_due_at = now + 1
	_assert_rejected_raw(current_document, current_timer, sentinel, "Current site with an invalid respawn interval")
	var bad_unrelated_state: Dictionary = current_raw.duplicate(true)
	bad_unrelated_state.inventory.items["unknown_item"] = 1
	_assert_rejected_raw(current_document, bad_unrelated_state, sentinel, "Malformed unrelated Inventory state")


func _assert_rejected_raw(base_document: Dictionary, candidate_raw: Dictionary, sentinel: Dictionary, label: String) -> void:
	var codec = VALUES.new()
	var candidate: Dictionary = base_document.duplicate(true)
	candidate.state = codec.encode(candidate_raw)
	_expect(codec.error.is_empty(), label + " fixture encodes: " + codec.error)
	_expect(not store.snapshot.prepare(candidate, content), label + " is rejected: " + store.snapshot.error)
	_expect(sentinel == store.snapshot.capture(content), label + " leaves all live state unchanged.")


func _test_current_depletion_roundtrip(worksite: Node, current_raw: Dictionary) -> void:
	var now: int = int(current_raw.clock.current_day) * 1440 \
		+ int(current_raw.clock.current_hour) * 60 + int(current_raw.clock.current_minute)
	for site_id: String in ["WoodSiteD", "WoodSiteE"]:
		var session = worksite.sites[StringName(site_id)]
		session.stock = 0
		session.respawn_started_at = now
		session.respawn_due_at = now + WORKSITE_SCHEMA.MAX_RESPAWN_DELAY_MINUTES
	var depleted_document: Dictionary = store.snapshot.capture(content)
	_expect(not depleted_document.is_empty(), "The depleted current checkpoint captures.")
	if depleted_document.is_empty():
		return
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var storage_before: Dictionary = storage.items.duplicate(true)
	for attempt: int in range(2):
		var current_valid: bool = store.snapshot.prepare(depleted_document, content)
		_expect(current_valid, "Current depleted-site snapshot validates repeatedly: " + store.snapshot.error)
		if not current_valid:
			return
		_expect(int(store.snapshot.prepared.worksites.sites.WoodSiteD.stock) == 0
			and int(store.snapshot.prepared.worksites.sites.WoodSiteE.stock) == 0,
			"Repeated current validation never fills saved depletion.")
		var live_document: Dictionary = store.snapshot.capture(content)
		_expect(not live_document.is_empty(), "Depleted live state remains capturable after validation.")
		if live_document.is_empty():
			return
		var recaptured_value: Variant = VALUES.new().decode(live_document.state)
		_expect(recaptured_value is Dictionary, "Depleted live state remains decodable after validation.")
		if not recaptured_value is Dictionary:
			return
		var recaptured: Dictionary = recaptured_value
		_expect(recaptured.worksites.sites.WoodSiteD.stock == 0
			and recaptured.worksites.sites.WoodSiteE.stock == 0,
			"Current validation does not mutate depleted live deposits.")
	store.disk.path = CURRENT_OUTPUT_PATH
	_clear_checkpoint_sidecars(CURRENT_OUTPUT_PATH)
	_expect(not FileAccess.file_exists(CURRENT_OUTPUT_PATH), "The current output slot starts empty and is newly observed.")
	_expect(store.save_checkpoint(), "The current depleted deposits save through the real disk writer: " + store.last_error)
	var bytes: String = FileAccess.get_file_as_string(CURRENT_OUTPUT_PATH)
	var written_document: Variant = JSON.parse_string(bytes)
	_expect(written_document is Dictionary and written_document.get("state") is Dictionary,
		"The real writer produces a current checkpoint document.")
	if not written_document is Dictionary or not written_document.get("state") is Dictionary:
		return
	var written_raw_value: Variant = VALUES.new().decode(written_document.state)
	_expect(written_raw_value is Dictionary, "The real writer produces a decodable current checkpoint state.")
	if not written_raw_value is Dictionary:
		return
	var written_raw: Dictionary = written_raw_value
	for site_id: String in ["WoodSiteD", "WoodSiteE"]:
		_expect(int(written_raw.worksites.sites[site_id].stock) == 0
			and int(written_raw.worksites.sites[site_id].respawn_started_at) == now
			and int(written_raw.worksites.sites[site_id].respawn_due_at) == now + WORKSITE_SCHEMA.MAX_RESPAWN_DELAY_MINUTES,
			"The saved current checkpoint contains exact depletion and respawn timestamps for " + site_id + ".")
	for attempt: int in range(2):
		var loaded: bool = store.load_checkpoint()
		_expect(loaded, "Current depleted-site checkpoint loads repeatedly: " + store.last_error)
		if not loaded:
			return
		_expect(worksite.sites[&"WoodSiteD"].stock == 0 and worksite.sites[&"WoodSiteE"].stock == 0,
			"Repeated current load preserves both saved zero stocks.")
		_expect(worksite.sites[&"WoodSiteD"].respawn_started_at == now
			and worksite.sites[&"WoodSiteE"].respawn_started_at == now
			and worksite.sites[&"WoodSiteD"].respawn_due_at == now + WORKSITE_SCHEMA.MAX_RESPAWN_DELAY_MINUTES
			and worksite.sites[&"WoodSiteE"].respawn_due_at == now + WORKSITE_SCHEMA.MAX_RESPAWN_DELAY_MINUTES,
			"Repeated current load preserves exact D/E respawn timestamps.")
		_expect(Inventory.items == inventory_before and storage.items == storage_before,
			"Repeated current load does not invent player or city inventory.")
		_expect(FileAccess.get_file_as_string(CURRENT_OUTPUT_PATH) == bytes,
			"Loading a current checkpoint leaves its exact bytes untouched.")


func _test_rejected_disk_preservation(legacy_document: Dictionary, legacy_raw: Dictionary, legacy_bytes: String) -> void:
	var malformed_raw: Dictionary = legacy_raw.duplicate(true)
	malformed_raw.worksites.sites.erase("WoodSite")
	var codec = VALUES.new()
	var malformed_document: Dictionary = legacy_document.duplicate(true)
	malformed_document.state = codec.encode(malformed_raw)
	_expect(codec.error.is_empty(), "The rejected legacy fixture encodes: " + codec.error)
	var malformed_bytes: String = JSON.stringify(malformed_document, "", true, true)
	store.disk.path = REJECTED_CHECKPOINT_PATH
	_clear_checkpoint_sidecars(REJECTED_CHECKPOINT_PATH)
	_write_text(REJECTED_CHECKPOINT_PATH, malformed_bytes)
	var sentinel: Dictionary = store.snapshot.capture(content)
	_expect(not store.load_checkpoint(), "Disk Load rejects an incomplete legacy worksite registry.")
	_expect(FileAccess.get_file_as_string(REJECTED_CHECKPOINT_PATH) == malformed_bytes,
		"Rejected Load preserves the exact malformed file bytes.")
	_expect(sentinel == store.snapshot.capture(content), "Rejected Load leaves all live state unchanged.")
	store.disk.path = LEGACY_CHECKPOINT_PATH
	_expect(FileAccess.get_file_as_string(LEGACY_CHECKPOINT_PATH) == legacy_bytes,
		"Later rejected input never changes the original legacy checkpoint bytes.")


func _clear_checkpoint_sidecars(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	for suffix: String in [".bak", ".tmp", ".pending"]:
		var sidecar: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(sidecar):
			DirAccess.remove_absolute(sidecar)


func _finish() -> void:
	print("WorksiteLegacyAdapterTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
