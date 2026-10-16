extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

const CODEC = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const CHECKPOINT_PATH: String = "user://city_save_test/checkpoint.json"
var store: Node

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	await get_tree().process_frame
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = CHECKPOINT_PATH
	var mode: String = "roundtrip"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--city-save-phase="):
			mode = argument.trim_prefix("--city-save-phase=")
	if mode == "read":
		_expect(store.load_checkpoint(), "A fresh game process loads the disk checkpoint: " + store.last_error)
		_assert_seed()
		_expect(JSON.parse_string(JSON.stringify(store.snapshot.capture(content), "", true, true)) == JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH)), "Fresh-process restore matches every captured owner and RNG state.")
		_finish()
		return
	_clean_files()
	_seed()
	_expect(ui.find_child("SaveButton", true, false) == null and ui.find_child("LoadButton", true, false) == null, "City Hub does not expose manual checkpoint buttons.")
	var saved: bool = store.save_checkpoint()
	_expect(saved, "A checkpoint can be saved: " + store.last_error)
	if not saved:
		_finish()
		return
	_assert_seed()
	if mode == "write":
		_finish()
		return
	var before: Dictionary = store.snapshot.capture(content)
	Inventory.items.clear()
	storage.items.clear()
	state._work_remaining = 1
	state._work_paid.clear()
	WorkStateRuntime.get_node("CityProgression").progress = 0
	player.global_position += Vector2(30, 20)
	player.focus = 0.1
	_expect(store.load_checkpoint(), "Manual Load restores the checkpoint: " + store.last_error)
	_assert_seed()
	var after: Dictionary = store.snapshot.capture(content)
	_expect(before == after, "Every captured owner round-trips exactly, without offline time or duplicated rewards.")
	# Existing version-1 files remain readable after adding home checkpoints.
	var legacy: Dictionary = before.duplicate(true)
	legacy.schema_version = 1
	legacy.erase("location")
	var legacy_file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	_expect(store.load_checkpoint(), "A version-1 manual city checkpoint still loads.")
	_assert_seed()
	_expect(store.save_checkpoint(), "The next explicit save writes the current location-aware version.")
	_expect(JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH)).schema_version == 2, "A successful save explicitly upgrades the legacy header.")
	# A malformed document must fail before any live mutation, and block Save.
	var valid_bytes: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
	var file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var sentinel: Dictionary = store.snapshot.capture(content)
	_expect(not store.load_checkpoint(), "Malformed JSON is rejected.")
	_expect(sentinel == store.snapshot.capture(content), "Invalid Load leaves the complete live world untouched.")
	_expect(not store.save_checkpoint() and FileAccess.get_file_as_string(CHECKPOINT_PATH) == "{broken", "Corrupt primary is preserved, never silently overwritten.")
	file = FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	file.store_string(valid_bytes)
	file.close()
	_expect(store.load_checkpoint(), "Explicit Load accepts a repaired valid file.")
	var values = VALUES.new()
	var raw: Dictionary = values.decode(before.state)
	raw.inventory.items["unknown_item"] = 3
	var invalid: Dictionary = before.duplicate(true)
	invalid.state = values.encode(raw)
	_expect(not store.snapshot.prepare(invalid, content), "Unknown items reject the entire checkpoint.")
	_expect(sentinel == store.snapshot.capture(content), "Schema rejection has no side effects.")
	# Continue the real build, then save during the real raid, after a breach.
	_set_clock_minute(_clock_minute() + state._work_remaining)
	_expect(state.wall_hp == 50 and state._attack_at > _clock_minute(), "Restored construction finishes once and starts a journey.")
	var arrival: int = state._attack_at
	_set_clock_minute(arrival)
	state.set_process(false)
	state.advance_attack(8.0)
	_expect(state.phase == "attacking", "The attack has started before the in-flight checkpoint.")
	_expect(store.save_checkpoint(), "An active raid can be checkpointed: " + store.last_error)
	var hp: int = state.wall_hp
	var elapsed: float = state._elapsed
	state.advance_attack(10.0)
	_expect(store.load_checkpoint(), "An active raid restores.")
	state.set_process(false)
	_expect(state.wall_hp == hp and state._elapsed == elapsed, "Attack HP and real-second hit cadence resume exactly.")
	state.wall_hp = 1
	state.advance_attack(3.0)
	_expect(state.phase == "looting", "The resumed raid reaches the real looting phase.")
	var satisfaction: float = CitizenNeedsManager.get_average_satisfaction()
	var city_progress: int = WorkStateRuntime.get_node("CityProgression").progress
	_expect(store.save_checkpoint(), "Looting state saves: " + store.last_error)
	var loot_before: Dictionary = state._stolen.duplicate()
	state.advance_attack(2.0)
	_expect(store.load_checkpoint(), "Looting state restores.")
	state.set_process(false)
	_expect(state._stolen == loot_before and CitizenNeedsManager.get_average_satisfaction() == satisfaction and WorkStateRuntime.get_node("CityProgression").progress == city_progress,
		"Breach penalties and stolen items are not applied a second time by Load.")
	ui.open_details()
	ui._select_hub_tab(true)
	await capture_defense("city-save-supply.png")
	var frame: Rect2 = ui.details_panel.get_global_rect()
	ui._select_hub_tab(false)
	await capture_defense("city-save-management.png")
	_expect(ui.details_panel.get_global_rect() == frame and frame.size == Vector2(300, 196), "Save/Load footer preserves the fixed Hub frame in both tabs.")
	var footer: Control = ui.details_panel.get_node("Margin/Contents/FooterRow")
	_expect(footer.get_global_rect().end.y <= frame.end.y - 8, "Save/Load controls stay inside the panel.")
	_clean_files()
	_finish()

func _seed() -> void:
	_set_clock_minute(7 * 1440 + 600)
	Inventory.items.assign({"shekel": 17, "stone": 3})
	storage.items = {"stone": 100, "wood_log": 100, "egg": 5}
	player.focus = 0.75
	var pickup: PickUpItem = preload("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	pickup.item_id = "clay_lump"
	pickup.quantity = 4
	pickup.position = Vector2(-210, -260)
	content.get_node("YSortWorld").add_child(pickup)
	_expect(state.request_wall_work(state.get_work_quote()), "The save fixture starts paid construction.")
	WorkStateRuntime.get_node("CityProgression").progress = 35

func _assert_seed() -> void:
	_expect(TimeComponentManager.current_day == 7, "A later-day checkpoint restores into a fresh day-zero session.")
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == 18, "Checkpoint restore preserves the eighteen palm-owned pickup views without duplicating them.")
	var drops: Array = store.snapshot._capture_city_drops(content)
	_expect(drops.size() == 1 and drops[0].quantity == 4 and drops[0].item_id == "clay_lump", "Dropped inventory items survive without duplication.")
	_expect(Inventory.items.get("shekel") == 17 and Inventory.items.get("stone") == 3, "Player inventory survives the checkpoint.")
	_expect(storage.items.get("stone") == 90 and storage.items.get("wood_log") == 95, "Materials already paid for construction remain paid exactly once.")
	_expect(state._work_remaining == 120 and state._work_kind == "build" and state.wall_hp == 0, "Unfinished wall work retains its timer and ruined wall.")
	_expect(WorkStateRuntime.get_node("CityProgression").progress == 35 and player.focus == 0.75, "City progress and player conditions survive.")

func _clean_files() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(CHECKPOINT_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECKPOINT_PATH + suffix))

func _finish() -> void:
	print("CitySaveTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
