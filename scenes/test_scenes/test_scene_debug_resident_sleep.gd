extends Node

## Real Debug action, home transition, sleep autosave and Continue using an isolated profile.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const VALUES: Script = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const CHECKPOINT: String = "user://debug_resident_sleep/checkpoint.json"
const HOME_PATH: String = "res://scenes/player_home_interior/player_home_interior.tscn"
const CITY_PATH: String = "res://scenes/content_scene/content_scene.tscn"
var failures: int = 0
var launched: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _wait_scene(path: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == path and not SceneTransition.is_transitioning:
			for _frame: int in range(3):
				await get_tree().process_frame
			return true
		await get_tree().process_frame
	_expect(false, "The actual scene transition completes: " + path)
	return false

func _run() -> void:
	if OS.get_name() == "Linux":
		var root: String = OS.get_environment("XDG_DATA_HOME")
		var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
		_expect(root.is_absolute_path() and user_root.begins_with(root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG_DATA_HOME.")
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		_expect(not FileAccess.file_exists(CHECKPOINT + suffix), "Do not overwrite an existing checkpoint.")
	if failures:
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = CHECKPOINT
	menu.session_started.connect(func(continued: bool): launched = not continued)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	menu.new_game_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched, "New Game opens the real city.")
	if not launched:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	var city: Node = get_tree().current_scene
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var player: Player = city.get_node("YSortWorld/Player")
	var debug: Node = city.get_node("TimeDebugOverlay")
	debug.resident_needs_button.pressed.emit()
	_expect(storage.get_food_supply_points() == 14 and storage.get_clothing_item_count() == 2 and CityStockManager.shelter_capacity == 2, "The debug button supplies the actual city needs.")
	_expect(not FileAccess.file_exists(CHECKPOINT), "Clicking Debug never writes a checkpoint on its own.")
	for _frame: int in range(4):
		await get_tree().process_frame
	city.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
	if not await _wait_scene(HOME_PATH):
		get_tree().quit(1)
		return
	var home: Node = get_tree().current_scene
	player = home.get_node("YSortWorld/Player")
	player.last_sleep_day = -1
	var bed: SleepSpot = home.get_node("YSortWorld/SleepSpot")
	player.global_position = bed.global_position + Vector2(-22, 8)
	for _frame: int in range(3):
		await get_tree().physics_frame
	await bed.on_player_interact(player)
	_expect(store.status == "Saved" and FileAccess.file_exists(CHECKPOINT), "The actual bed autosaves after the debug action: " + store.last_error)
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT))
	_expect(document is Dictionary and document.get("location", "") == "home", "Sleep writes a home checkpoint.")
	if document is Dictionary:
		var decoded: Variant = VALUES.new().decode(document.get("state", {}))
		_expect(decoded is Dictionary and int(decoded.city_storage.items.get("date_cluster", 0)) == 14 and int(decoded.city_storage.items.get("simple_clothes", 0)) == 2 and int(decoded.stock.shelter_capacity) == 2, "The sleep checkpoint contains the exact debug food, clothing and shelter.")
	home.get_node("YSortWorld/ExitDoor")._on_body_entered(player)
	if not await _wait_scene(CITY_PATH):
		get_tree().quit(1)
		return
	storage.items.clear() # Test-only mutation verifies loading the disk checkpoint.
	CityStockManager.shelter_capacity = 0
	_expect(store.load_checkpoint(), "The sleep checkpoint loads through the actual city store: " + store.last_error)
	if not await _wait_scene(HOME_PATH):
		get_tree().quit(1)
		return
	_expect(store.status == "Loaded" and storage.get_food_supply_points() == 14 and storage.get_clothing_item_count() == 2 and CityStockManager.shelter_capacity == 2, "Continue restores the debug supplies from the actual sleep save.")
	print("DebugResidentSleepTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
