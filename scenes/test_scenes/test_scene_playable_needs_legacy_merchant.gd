extends Node

## Write with the pre-offer commit, then read in a fresh process with the new
## code. The disposable checkpoint captures a real, partly traded visit.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const SAVE_PATH: String = "user://playable_needs_legacy/checkpoint.json"
var failures: int = 0
var launched: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var mode: String = "write"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--legacy-mode="):
			mode = arg.trim_prefix("--legacy-mode=")
	var root: String = OS.get_environment("XDG_DATA_HOME")
	_expect(root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG_DATA_HOME.")
	_expect(mode in ["write", "read"], "Use write or read mode.")
	_expect(FileAccess.file_exists(SAVE_PATH) == (mode == "read"), "Write requires a clean slot; read requires the baseline checkpoint.")
	if failures > 0:
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(func(continued: bool): launched = continued == (mode == "read"))
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	if mode == "write":
		menu.new_game_button.pressed.emit()
	else:
		menu.continue_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched, "Start Menu opens the requested session.")
	if not launched:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	var city: Node = get_tree().current_scene
	var player: Player = city.get_node("YSortWorld/Player")
	# This is a checkpoint compatibility fixture, not the normal-play journey.
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	var merchant: Node = WorkStateRuntime.get_node("CommonTravelingMerchant")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	if mode == "write":
		# The pre-change roll deliberately requests only bricks, to verify that
		# loading cannot retrofit a wood quota into an active visit.
		merchant._request_rng.seed = 937
		_expect(_advance_to(1, 8), "The baseline reaches the first scheduled visit.")
		_expect(not merchant._offers.has("simple_clothes"), "Writer runs against the pre-offer baseline.")
		_expect(int(merchant._demand.get("wood_log", 0)) == 0 and int(merchant._demand.get("sun_dried_mudbrick", 0)) > 0, "The baseline captured a brick-only visit.")
		Inventory.add_item("shekel", 20)
		_expect(bool(merchant.trade("clay_lump", 1, true).ok), "The baseline visit has an actual completed purchase.")
		_expect(int(merchant._stock.get("clay_lump", -1)) == 11 and merchant.get_budget() == 122, "The partially traded visit is recorded.")
		_expect(store.save_checkpoint(), "Baseline checkpoint saves: " + store.last_error)
	else:
		_expect(merchant.is_present() and not merchant._offers.has("simple_clothes"), "Loading a baseline visit does not invent mid-visit stock.")
		_expect(int(merchant._demand.get("wood_log", 0)) == 0 and int(merchant._demand.get("sun_dried_mudbrick", 0)) > 0, "The old brick-only request remains unchanged during that visit.")
		_expect(int(merchant._stock.get("clay_lump", -1)) == 11 and merchant.get_budget() == 122 and Inventory.items.get("shekel", 0) == 18 and Inventory.items.get("clay_lump", 0) == 1, "The original trade and balances survive Continue.")
		var old_demand: Dictionary = merchant._demand.duplicate(true)
		_expect(store.load_checkpoint(), "The same old checkpoint can be loaded again: " + store.last_error)
		_expect(merchant._demand == old_demand and merchant.get_budget() == 122 and not merchant._offers.has("simple_clothes"), "Repeated old-save loads preserve visit demand, money and catalog.")
		_expect(_advance_to(4, 8), "The next scheduled visit arrives.")
		_expect(merchant.is_present() and merchant._offers.has("simple_clothes") and int(merchant._stock.get("simple_clothes", -1)) == 2, "The added item appears with its normal stock at the next arrival.")
		_expect(int(merchant._demand.get("wood_log", 0)) >= 3 and int(merchant._demand.get("wood_log", 0)) <= 6, "The next visit adopts a normal, bounded wood request.")
		_expect(bool(merchant.trade("simple_clothes", 1, true).ok), "The migrated merchant can sell a garment.")
		var budget: int = merchant.get_budget()
		TimeComponentManager.emit_time_signal()
		_expect(int(merchant._stock.get("simple_clothes", -1)) == 1 and merchant.get_budget() == budget, "Same-visit refresh cannot restock or reset payment.")
		_expect(store.save_checkpoint() and store.load_checkpoint(), "The migrated, partly traded visit can save and reload: " + store.last_error)
		_expect(int(merchant._stock.get("simple_clothes", -1)) == 1 and merchant.get_budget() == budget and Inventory.items.get("simple_clothes", 0) == 1, "New offer stock and purchase persist across save/load.")
		_expect(_advance_to(7, 8) and int(merchant._stock.get("simple_clothes", -1)) == 2, "The following scheduled visit restocks exactly once.")
	print("PlayableNeedsLegacyMerchant ", mode, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _advance_to(day: int, hour: int) -> bool:
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var target: int = day * 1440 + hour * 60
	return target > now and TimeComponentManager.advance_minutes(target - now)
