extends Node

## Focused regression. Tests use only disposable XDG profiles, never live saves.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const SNAPSHOT = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const STARTERS = preload("res://scenes/content_scene/startup/initial_worksites.gd")
const SAVE_PATH: String = "user://civil_identity_persistence/checkpoint.json"
const ROUNDTRIP_PATH: String = "user://civil_identity_persistence/roundtrip.json"
var checks: int = 0
var failures: int = 0
var launched: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)
	else:
		print("PASS: ", description)

func _run() -> void:
	var root: String = OS.get_environment("XDG_DATA_HOME")
	_check(root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(root.simplify_path().trim_suffix("/") + "/"), "Disposable XDG user data is mandatory.")
	var mode: String = OS.get_environment("TIP_IDENTITY_PROBE_MODE")
	_check(mode in ["writer", "reader", "legacy_reader"], "Explicit writer, reader or legacy_reader mode is required.")
	if failures:
		_finish(mode)
		return
	_unit_probe()
	if OS.get_environment("TIP_IDENTITY_DEFAULTS_CHANGED") == "1":
		var changed_defaults := VisualProfile.new()
		_check(changed_defaults.skin_tone == "warm" and changed_defaults.hair_style == "red_female_03", "Compatibility fixture really uses different generic appearance defaults.")
	if mode != "writer":
		# Simulate an update to new-character generation, not to saved people.
		CitizenGenerator.display_name_container.assign(["Changed pool name"])
		CitizenGenerator.hair_container.assign(["red_female_03"])
		CitizenGenerator.skin_tone_container.assign(["light"])
	_check(FileAccess.file_exists(SAVE_PATH) == (mode != "writer"), "Writer refuses an existing save; reader requires its copied input.")
	if failures:
		_finish(mode)
		return
	var input_hash: String = FileAccess.get_sha256(SAVE_PATH) if mode != "writer" else ""
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(func(continued: bool): launched = continued == (mode != "writer"))
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	if mode != "writer":
		menu.continue_button.pressed.emit()
	else:
		menu.new_game_button.pressed.emit()
	for frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_check(launched, "Real start-menu flow completes in " + mode + ".")
	if not launched:
		_finish(mode)
		return
	await get_tree().create_timer(0.3).timeout
	TimeComponentManager.set_process(false)
	var city: Node = get_tree().current_scene
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var visuals: Node = city.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	if mode == "writer":
		for id: String in [STARTERS.APPLICANT_ID, STARTERS.HAULER_APPLICANT_ID, STARTERS.CITY_HAULER_APPLICANT_ID]:
			var person: CitizenData = CitizenManager.get_citizen(id)
			_check(person != null and _is_baseline_profile(person.visual_profile), "Starter records an explicit profile: " + id)
			var actor: Node = visuals.actors.get(id)
			_check(actor != null and actor.skin_tone == "light" and actor.hair_style == "grey_male_01", "Starter keeps its existing light/grey_male_01 appearance: " + id)
		CitizenGenerator.display_name_container.assign(["Preserved resident name"])
		CitizenGenerator.hair_container.assign(["black_female_02"])
		CitizenGenerator.skin_tone_container.assign(["dark"])
		var person: CitizenData = CitizenGenerator.generate_citizen()
		person.population_status = CitizenData.PopulationStatus.RESIDENT
		CitizenManager.add_citizen(person)
		_check(person.citizen_id == "citizen_001", "First generated resident gets a stable ID.")
		CitizenGenerator.display_name_container.assign(["Preserved pending name"])
		CitizenGenerator.hair_container.assign(["brown_male_03"])
		CitizenGenerator.skin_tone_container.assign(["warm"])
		ImmigrationManager.spawn_immigration(1)
		_check(ImmigrationManager.pending_immigrants.size() == 1 and CitizenGenerator.counter_id == 2, "Pending migrant and generator counter are present.")
		_check(store.save_checkpoint(), "Real CitySave writes an isolated v17 checkpoint: " + store.last_error)
		print("WRITER_SAVE=", ProjectSettings.globalize_path(SAVE_PATH))
	else:
		_check(FileAccess.get_sha256(SAVE_PATH) == input_hash, "Continue leaves source save bytes unchanged.")
		_verify_restored(visuals)
		_test_corrupt_restore(store, city)
		if OS.get_environment("TIP_IDENTITY_SIZE_GUARD") == "1":
			_test_size_guard(store, city)
		for cycle: int in range(3):
			_check(store.load_checkpoint(), "Repeated CitySave load succeeds: " + str(cycle))
			for frame: int in range(4):
				await get_tree().process_frame
			_verify_restored(visuals)
		_check(FileAccess.get_sha256(SAVE_PATH) == input_hash, "Repeated loads leave source save bytes unchanged.")
		store.disk.path = ROUNDTRIP_PATH
		_check(store.save_checkpoint(), "Restored identities can be saved to a separate checkpoint.")
		_check(store.load_checkpoint(), "Separate checkpoint loads.")
		for frame: int in range(4):
			await get_tree().process_frame
		_verify_restored(visuals)
		var new_person: CitizenData = CitizenGenerator.generate_citizen()
		_check(new_person.citizen_id == "citizen_003", "Restored generator counter avoids reused citizen IDs.")
		_check(new_person.display_name == "Changed pool name" and new_person.visual_profile.hair_style == "red_female_03" and new_person.visual_profile.skin_tone == "light", "Updated generation pools apply only to a newly generated citizen.")
	_finish(mode)

func _verify_restored(visuals: Node) -> void:
	var person: CitizenData = CitizenManager.get_citizen("citizen_001")
	_check(person != null and person.display_name == "Preserved resident name" and person.visual_profile != null and person.visual_profile.skin_tone == "dark" and person.visual_profile.hair_style == "black_female_02", "Saved resident ID/name/hair/body color remain exact after changed generation pools.")
	var actor: Node = visuals.actors.get("citizen_001")
	_check(actor != null and actor.skin_tone == "dark" and actor.hair_style == "black_female_02", "World actor uses the restored resident profile.")
	_check(ImmigrationManager.pending_immigrants.size() == 1, "Pending migrant survives save/load.")
	if ImmigrationManager.pending_immigrants.size() == 1:
		var pending: CitizenData = ImmigrationManager.pending_immigrants[0]
		_check(pending.citizen_id == "citizen_002" and pending.display_name == "Preserved pending name" and pending.visual_profile != null and pending.visual_profile.skin_tone == "warm" and pending.visual_profile.hair_style == "brown_male_03", "Pending migrant identity remains exact.")
	_check(CitizenGenerator.counter_id == 2, "Saved generator counter remains exact.")
	for id: String in [STARTERS.APPLICANT_ID, STARTERS.HAULER_APPLICANT_ID, STARTERS.CITY_HAULER_APPLICANT_ID]:
		var starter: CitizenData = CitizenManager.get_citizen(id)
		if id == STARTERS.APPLICANT_ID and OS.get_environment("TIP_IDENTITY_CUSTOM_STARTER") == "1":
			_check(starter != null and starter.display_name == "Saved custom starter" and starter.visual_profile != null and starter.visual_profile.skin_tone == "tan" and starter.visual_profile.hair_style == "brown_female_02", "A saved custom starter name and profile remain exact through real Continue.")
		else:
			_check(starter != null and _is_baseline_profile(starter.visual_profile), "Save/load retains an explicit starter baseline: " + id)
			var expected_name: String = {STARTERS.APPLICANT_ID: STARTERS.LABORER_NAME, STARTERS.HAULER_APPLICANT_ID: STARTERS.HAULER_NAME, STARTERS.CITY_HAULER_APPLICANT_ID: STARTERS.CITY_HAULER_NAME}[id]
			_check(starter != null and starter.display_name == expected_name, "Save/load retains the recorded starter name: " + id)

func _unit_probe() -> void:
	var codec = VALUES.new()
	var person := CitizenData.new()
	person.citizen_id = "identity_probe"
	person.display_name = "Preserved Énki"
	person.visual_profile = VisualProfile.new()
	person.visual_profile.skin_tone = "tan"
	person.visual_profile.hair_style = "red_female_02"
	for cycle: int in range(5):
		var encoded: Variant = codec.encode(person)
		_check(codec.error.is_empty(), "Identity encodes: " + str(cycle))
		person = codec.decode(JSON.parse_string(JSON.stringify(encoded, "", true, true)))
		_check(codec.error.is_empty() and person != null and person.display_name == "Preserved Énki" and person.visual_profile.skin_tone == "tan" and person.visual_profile.hair_style == "red_female_02", "Codec retains exact identity strings: " + str(cycle))
	var encoded: Dictionary = codec.encode(person)
	encoded.fields.visual_profile.fields.erase("hair_style")
	codec.decode(encoded)
	_check(not codec.error.is_empty(), "Missing saved hair key rejects instead of silently generating a replacement.")
	_test_staged_profiles()

func _is_baseline_profile(profile: VisualProfile) -> bool:
	return profile != null and profile.skin_tone == "light" and profile.hair_style == "grey_male_01" and profile.expression == "base" and profile.clothes_id == "clay_worn_wrap" and profile.accessory == "default"

func _test_staged_profiles() -> void:
	var first := CitizenData.new()
	first.citizen_id = STARTERS.APPLICANT_ID
	first.display_name = "Preserve custom starter name"
	first.satisfaction = 0.73
	first.experience = 7.0
	var second := CitizenData.new()
	second.citizen_id = STARTERS.HAULER_APPLICANT_ID
	second.display_name = "Another saved name"
	second.visual_profile = VisualProfile.new()
	second.visual_profile.skin_tone = "dark"
	second.visual_profile.hair_style = "brown_female_03"
	var third := CitizenData.new()
	third.citizen_id = STARTERS.CITY_HAULER_APPLICANT_ID
	third.display_name = "Third saved name"
	var unrelated := CitizenData.new()
	unrelated.citizen_id = "unrelated_legacy_citizen"
	unrelated.display_name = "Untouched"
	var original_people: Dictionary = {first.citizen_id: first, second.citizen_id: second, third.citizen_id: third, unrelated.citizen_id: unrelated}
	var original_owner: Dictionary = {"citizens_by_id": original_people}
	var raw: Dictionary = {"citizens": original_owner}
	var codec = VALUES.new()
	var original_encoded: Variant = codec.encode(original_people)
	var state = SNAPSHOT.new()
	_check(state._stage_missing_starter_profiles(raw), "Only missing starter profiles are staged.")
	_check(codec.encode(original_people) == original_encoded and first.visual_profile == null and third.visual_profile == null, "Staging does not mutate the supplied people or source owner.")
	var staged_first: CitizenData = raw.citizens.citizens_by_id[first.citizen_id]
	var staged_third: CitizenData = raw.citizens.citizens_by_id[third.citizen_id]
	_check(staged_first != first and _is_baseline_profile(staged_first.visual_profile) and staged_first.display_name == first.display_name and staged_first.satisfaction == first.satisfaction and staged_first.experience == first.experience, "Missing profile gets the explicit current baseline without changing its saved name or other state.")
	_check(_is_baseline_profile(staged_third.visual_profile) and staged_first.visual_profile != staged_third.visual_profile, "Each staged starter owns a distinct profile.")
	_check(raw.citizens.citizens_by_id[second.citizen_id] == second and second.visual_profile.skin_tone == "dark" and second.visual_profile.hair_style == "brown_female_03" and second.display_name == "Another saved name", "A non-null saved profile and name are not overwritten.")
	_check(raw.citizens.citizens_by_id[unrelated.citizen_id] == unrelated and unrelated.visual_profile == null and raw.citizens.citizens_by_id.size() == original_people.size(), "Unrelated legacy people are neither changed nor supplemented.")
	var staged_encoded: Variant = codec.encode(raw)
	_check(not state._stage_missing_starter_profiles(raw) and codec.encode(raw) == staged_encoded, "Repeated staging is idempotent.")
	_check(not state._stage_missing_starter_profiles({"citizens": {"citizens_by_id": {}}}), "Missing starter IDs are not recreated by profile initialization.")
	var independent_a: VisualProfile = STARTERS.create_initial_visual_profile()
	var independent_b: VisualProfile = STARTERS.create_initial_visual_profile()
	independent_a.skin_tone = "tan"
	_check(independent_b.skin_tone == "light", "New starter profiles do not share mutable resource state.")

func _test_corrupt_restore(store: Node, city: Node) -> void:
	var codec = VALUES.new()
	var before: Variant = codec.encode(CitizenManager.citizens_by_id)
	var invalid: Dictionary = store.snapshot.capture(city)
	var person: Dictionary = _encoded_person(invalid, "citizen_001")
	_check(not person.is_empty(), "Corrupt-input fixture locates its exact citizen by ID.")
	if person.is_empty():
		return
	person.fields.visual_profile.fields.erase("hair_style")
	_check(not store.snapshot.prepare(invalid, city) and not store.snapshot.error.is_empty(), "Incomplete saved hair rejects before apply.")
	_check(codec.encode(CitizenManager.citizens_by_id) == before, "A rejected restore does not alter live identities.")

func _encoded_person(value: Variant, id: String) -> Dictionary:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == "CitizenData" and value.get("fields", {}).get("citizen_id") == id:
			return value
		for child: Variant in value.values():
			var found: Dictionary = _encoded_person(child, id)
			if not found.is_empty():
				return found
	elif value is Array:
		for child: Variant in value:
			var found: Dictionary = _encoded_person(child, id)
			if not found.is_empty():
				return found
	return {}

func _test_size_guard(store: Node, city: Node) -> void:
	var source: Dictionary = store.snapshot.capture(city)
	for id: String in [STARTERS.APPLICANT_ID, STARTERS.HAULER_APPLICANT_ID, STARTERS.CITY_HAULER_APPLICANT_ID]:
		_encoded_person(source, id).fields.visual_profile = null
	var large_person: Dictionary = _encoded_person(source, "citizen_001")
	large_person.fields.display_name = ""
	var before_size: int = JSON.stringify(source, "", true, true).to_utf8_buffer().size()
	large_person.fields.display_name = "x".repeat(store.disk.MAX_FILE_BYTES - before_size - 1)
	_check(store.snapshot._within_save_size_limit(source), "Near-limit legacy input fits the existing save cap before profile staging.")
	var source_digest: String = JSON.stringify(source, "", true, true).sha256_text()
	var codec = VALUES.new()
	var live_before: Variant = codec.encode(CitizenManager.citizens_by_id)
	_check(not store.snapshot.prepare(source, city) and store.snapshot.error == "Migrated checkpoint exceeds the existing save size limit.", "A profile migration that cannot fit rejects instead of weakening the file limit.")
	_check(codec.encode(CitizenManager.citizens_by_id) == live_before and JSON.stringify(source, "", true, true).sha256_text() == source_digest, "Size-limit rejection preserves both live identities and its input document.")

func _finish(mode: String) -> void:
	print("CivilIdentityPersistence: ", "PASS" if failures == 0 else "FAIL", " mode=", mode, " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
