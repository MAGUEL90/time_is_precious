extends Node2D

const MERCHANT_SCENE: PackedScene = preload("res://scenes/traveling_merchant/traveling_merchant.tscn")
const STATE_NAME: String = "CommonTravelingMerchant"

var failures: int = 0
var player: Player
var merchant: Node2D
var _saved_inventory: Dictionary = {}
var _saved_inventory_max_load: float = 0.0
var _saved_clock: Dictionary = {}
var _saved_clock_paused: bool = false
var _saved_clock_processing: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_set_clock(1, 8, 0)
	player = $Player as Player
	merchant = $TravelingMerchant as Node2D
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	player.global_position = Vector2.ZERO
	merchant.global_position = Vector2.ZERO
	await _settle()
	if merchant.get("player") != player:
		merchant.call("_on_body_entered", player)
	if player.current_interactable != merchant:
		player._on_interactable_activated(merchant)
	await _settle()
	_expect(merchant.call("has_player_access"), "The fixture Player has physical access to the merchant.")

	await _press("interact")
	var greeting: BaseGameDialogueBalloon = await _wait_for_greeting()
	if not is_instance_valid(greeting):
		_finish()
		return
	await _wait_for_greeting_line(greeting)
	var panel: Control = greeting.chat_box_root.get_node("TemplateDialogue")
	_expect(get_viewport().get_visible_rect().encloses(panel.get_global_rect()), "Greeting artwork fits the logical viewport.")
	await _capture_optional_screenshot("line")
	_expect(greeting.dialogue_line.responses.size() == 2,
		"The first greeting offers exactly Trade and Leave.")
	_expect(not is_instance_valid(merchant.get("menu")), "The trade menu stays closed while the greeting is active.")
	_expect(TimeComponentManager.is_paused and not player.can_move,
		"The greeting pauses world time and holds the Player movement lock.")
	greeting.show_responses()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(get_viewport().get_visible_rect().encloses(greeting.responses_menu.get_global_rect()), "Both dialogue choices fit the logical viewport.")
	await _capture_optional_screenshot("responses")
	await _choose_response(greeting, "Trade")
	if not await _wait_until(
		func(): return is_instance_valid(merchant.get("menu")) and not merchant.call("_has_live_greeting_balloon"),
		"Trade opens the menu after the greeting balloon ends."):
		_finish()
		return
	_expect(not TimeComponentManager.is_paused and not player.can_move,
		"Ending the greeting resumes time while the trade menu keeps its own movement lock.")
	merchant.call("close_menu")
	await _settle()
	_set_clock(1, 8, 1)
	await _press("interact")
	greeting = await _wait_for_greeting()
	_expect(not is_instance_valid(merchant.get("menu")), "Every interaction begins with dialogue before trading.")
	await _wait_for_greeting_line(greeting)
	await _choose_response(greeting, "Trade")
	await _wait_until(func(): return is_instance_valid(merchant.get("menu")), "Trade opens after the repeated greeting.")
	merchant.call("close_menu")
	await _settle()

	merchant.queue_free()
	await get_tree().process_frame
	merchant = MERCHANT_SCENE.instantiate() as Node2D
	merchant.global_position = player.global_position
	add_child(merchant)
	await _settle()
	if merchant.get("player") != player:
		merchant.call("_on_body_entered", player)
	if player.current_interactable != merchant:
		player._on_interactable_activated(merchant)
	await _press("interact")
	greeting = await _wait_for_greeting()
	_expect(not is_instance_valid(merchant.get("menu")), "Every interaction begins with dialogue before trading.")
	await _wait_for_greeting_line(greeting)
	await _choose_response(greeting, "Trade")
	await _wait_until(func(): return is_instance_valid(merchant.get("menu")), "Trade opens after the repeated greeting.")
	merchant.call("close_menu")
	await _settle()

	_set_clock(4, 8, 0)
	await _settle()
	await _press("interact")
	greeting = await _wait_for_greeting()
	if not is_instance_valid(greeting):
		_finish()
		return
	await _wait_for_greeting_line(greeting)
	await _choose_response(greeting, "Leave")
	if not await _wait_until(
		func(): return not merchant.call("_has_live_greeting_balloon") and player.can_move and not TimeComponentManager.is_paused,
		"Leave closes the greeting and releases both locks."):
		_finish()
		return
	_expect(not is_instance_valid(merchant.get("menu")), "Leave never opens the trade menu.")
	await _press("interact")
	greeting = await _wait_for_greeting()
	_expect(not is_instance_valid(merchant.get("menu")), "Every interaction begins with dialogue before trading.")
	await _wait_for_greeting_line(greeting)
	await _choose_response(greeting, "Trade")
	await _wait_until(func(): return is_instance_valid(merchant.get("menu")), "Trade opens after the repeated greeting.")
	merchant.call("close_menu")
	await _settle()

	_set_clock(7, 8, 0)
	await _settle()
	await _press("interact")
	greeting = await _wait_for_greeting()
	if not is_instance_valid(greeting):
		_finish()
		return
	player.is_collapsing = true
	if not await _wait_until(
		func(): return not merchant.call("_has_live_greeting_balloon") and player.can_move and not TimeComponentManager.is_paused,
		"Collapse access loss cancels the greeting and clears its pause and movement locks."):
		player.is_collapsing = false
		_finish()
		return
	_expect(not is_instance_valid(merchant.get("menu")), "Collapse cancellation does not open trading.")
	player.is_collapsing = false
	_finish()

func _snapshot_globals() -> void:
	_saved_inventory = Inventory.items.duplicate()
	_saved_inventory_max_load = Inventory.max_load
	_saved_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
	}
	_saved_clock_paused = TimeComponentManager.is_paused
	_saved_clock_processing = TimeComponentManager.is_processing()

func _set_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.emit_time_signal()

func _settle() -> void:
	for _frame: int in range(4):
		await get_tree().physics_frame
	await get_tree().process_frame

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame

func _wait_for_greeting() -> BaseGameDialogueBalloon:
	var found: bool = await _wait_until(
		func(): return merchant.call("_has_live_greeting_balloon"),
		"Interacting opens the owned merchant greeting balloon."
	)
	if not found:
		return null
	return merchant.get("greeting_balloon") as BaseGameDialogueBalloon

func _wait_for_greeting_line(balloon: BaseGameDialogueBalloon) -> void:
	var line_ready: bool = await _wait_until(
		func(): return is_instance_valid(balloon) and is_instance_valid(balloon.dialogue_line),
		"The merchant greeting line appears."
	)
	if not line_ready:
		return
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	await _wait_until(
		func(): return is_instance_valid(balloon) and balloon.is_waiting_for_input,
		"The greeting waits for the Player's response."
	)

func _choose_response(balloon: BaseGameDialogueBalloon, response_text: String) -> void:
	if not is_instance_valid(balloon) or not is_instance_valid(balloon.dialogue_line):
		_expect(false, "A live greeting is available before response selection.")
		return
	if not balloon.responses_menu.visible:
		balloon.show_responses()
	var response_button: Control
	for item: Control in balloon.responses_menu.get_menu_items():
		var response: DialogueResponse = item.get_meta("response") as DialogueResponse
		if is_instance_valid(response) and response.text.strip_edges() == response_text:
			response_button = item
	_expect(is_instance_valid(response_button), "The greeting exposes the %s response." % response_text)
	if not is_instance_valid(response_button):
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	response_button.gui_input.emit(click)

func _capture_optional_screenshot(suffix: String) -> void:
	var folder: String = OS.get_environment("TIP_MERCHANT_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name().to_lower() == "headless":
		return
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_warning("Could not create merchant greeting screenshot directory: %s" % folder)
		return
	await RenderingServer.frame_post_draw
	var capture_path: String = folder.path_join("merchant-greeting-" + suffix + ".png")
	var save_error: Error = get_viewport().get_texture().get_image().save_png(capture_path)
	if save_error != OK:
		push_warning("Could not save merchant greeting screenshot: %s" % capture_path)

func _wait_until(predicate: Callable, message: String, timeout_msec: int = 5000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var passed: bool = predicate.call()
	_expect(passed, message)
	return passed

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _finish() -> void:
	if is_instance_valid(merchant):
		merchant.free()
	if is_instance_valid(player):
		player.free()
	var state: Node = WorkStateRuntime.get_node_or_null(STATE_NAME)
	if is_instance_valid(state):
		state.free()
	Inventory.items.clear()
	for item_id: Variant in _saved_inventory:
		Inventory.items[item_id] = _saved_inventory[item_id]
	Inventory.max_load = _saved_inventory_max_load
	Inventory.items_changed.emit()
	TimeComponentManager.current_day = int(_saved_clock.day)
	TimeComponentManager.current_hour = int(_saved_clock.hour)
	TimeComponentManager.current_minute = int(_saved_clock.minute)
	TimeComponentManager.current_weather = str(_saved_clock.weather)
	TimeComponentManager.emit_time_signal()
	TimeComponentManager.is_paused = _saved_clock_paused
	TimeComponentManager.set_process(_saved_clock_processing)
	print("TravelingMerchantGreetingTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
