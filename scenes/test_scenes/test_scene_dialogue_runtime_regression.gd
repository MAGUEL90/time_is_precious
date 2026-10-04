extends Node2D

const TEST_DIALOGUE: DialogueResource = preload("res://dialogue/game_dialogue_conversations/test.dialogue")

const COMPILED_DIALOGUE_SOURCE: String = """
~ start
do regression_dialogue_mutation_value = regression_dialogue_mutation_value + 1
Probe: Choose the enabled route.
- Continue [if regression_dialogue_mutation_value == 1]
	Probe: The mutation-enabled conditional route was reached.
	=> END
- Blocked route [if regression_dialogue_mutation_value == 0]
	Probe: The disabled route was incorrectly reached.
	=> END
"""

var failures: int = 0
var player: Player
var npc: NPCBase
var dialogue_manager: Object
var regression_dialogue_mutation_value: int = 0
var activated_count: int = 0
var deactivated_count: int = 0
var dialogue_ended_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(Engine.has_singleton("DialogueManager"), "The Dialogue Manager Engine singleton is registered.")
	dialogue_manager = get_node_or_null("/root/DialogueManager")
	_expect(is_instance_valid(dialogue_manager), "The DialogueManager autoload is present.")
	if not Engine.has_singleton("DialogueManager") or not is_instance_valid(dialogue_manager):
		_finish()
		return
	_expect(Engine.get_singleton("DialogueManager") == dialogue_manager,
		"The Engine singleton resolves to the DialogueManager autoload instance.")

	player = $Player as Player
	npc = $NPC_Gabbi as NPCBase
	_expect(is_instance_valid(player) and is_instance_valid(npc), "The real Player and Gabbi fixtures are present.")
	if not is_instance_valid(player) or not is_instance_valid(npc):
		_finish()
		return

	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	player.can_interact = true
	npc.allow_random_walk = false
	npc.npc_unique_dialogue = TEST_DIALOGUE

	BaseDialogueManager.dialogue_activated.connect(_on_dialogue_activated)
	BaseDialogueManager.dialogue_deactivated.connect(_on_dialogue_deactivated)
	dialogue_manager.connect(&"dialogue_ended", _on_dialogue_ended)

	await get_tree().process_frame
	await _exercise_compiled_dialogue()
	for cycle: int in range(2):
		if not await _exercise_real_dialogue_cycle(cycle + 1):
			_finish()
			return
	_finish()


func _exercise_compiled_dialogue() -> void:
	regression_dialogue_mutation_value = 0
	var compiled_resource: DialogueResource = dialogue_manager.call(
		"create_resource_from_text", COMPILED_DIALOGUE_SOURCE
	) as DialogueResource
	_expect(is_instance_valid(compiled_resource), "The plugin compiles a runtime dialogue resource from text.")
	if not is_instance_valid(compiled_resource):
		return

	var choice_line: DialogueLine = await compiled_resource.get_next_dialogue_line("start", [self])
	_expect(regression_dialogue_mutation_value == 1, "The compiled dialogue executes its mutation against the supplied state.")
	_expect(is_instance_valid(choice_line) and choice_line.responses.size() == 2,
		"The compiled dialogue reaches its two-choice line after the mutation.")
	if not is_instance_valid(choice_line) or choice_line.responses.size() != 2:
		return

	var allowed_responses: Array[DialogueResponse] = []
	for response: DialogueResponse in choice_line.responses:
		if response.is_allowed:
			allowed_responses.append(response)
	_expect(allowed_responses.size() == 1 and allowed_responses[0].text == "Continue",
		"The condition enables only the matching response.")
	if allowed_responses.size() != 1:
		return

	var branch_line: DialogueLine = await compiled_resource.get_next_dialogue_line(allowed_responses[0].next_id, [self])
	_expect(is_instance_valid(branch_line)
		and branch_line.text == "The mutation-enabled conditional route was reached.",
		"Traversing the allowed choice reaches its authored conditional branch.")
	if is_instance_valid(branch_line):
		var end_line: DialogueLine = await compiled_resource.get_next_dialogue_line(branch_line.next_id, [self])
		_expect(not is_instance_valid(end_line), "The compiled branch traverses to conversation end.")


func _exercise_real_dialogue_cycle(cycle: int) -> bool:
	var activation_before: int = activated_count
	var deactivation_before: int = deactivated_count
	var ended_before: int = dialogue_ended_count
	TimeComponentManager.is_paused = false
	player.current_interactable = npc
	player.can_interact = true
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	player._unhandled_input(interact_event)

	if not await _wait_until(
		func(): return activated_count == activation_before + 1 and _find_balloon() != null,
		"Cycle %d opens the actual game dialogue balloon and emits one activation." % cycle
	):
		return false

	var balloon: BaseGameDialogueBalloon = _find_balloon()
	if not is_instance_valid(balloon):
		_expect(false, "Cycle %d has one live game balloon." % cycle)
		return false
	_expect(_count_balloons() == 1, "Cycle %d creates exactly one game balloon." % cycle)
	_expect(player.current_npc_dialogue == npc and not player.can_move,
		"Cycle %d locks the actual Player to the active NPC dialogue." % cycle)
	_expect(TimeComponentManager.is_paused,
		"Cycle %d pauses world time when Player opens dialogue." % cycle)

	if not await _wait_until(
		func(): return is_instance_valid(balloon) and is_instance_valid(balloon.dialogue_line),
		"Cycle %d displays the first authored test dialogue line." % cycle
	):
		return false
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	if not await _wait_until(
		func(): return is_instance_valid(balloon) and balloon.is_waiting_for_input,
		"Cycle %d finishes typing and waits for Player input." % cycle
	):
		return false
	_expect(balloon.dialogue_line.text.contains("this is TEST dialogue"),
		"Cycle %d uses the existing test.dialogue fixture through the real balloon." % cycle)
	if cycle == 1:
		await _capture_optional_screenshot()

	balloon.next(balloon.dialogue_line.next_id)
	if not await _wait_until(
		func(): return (is_instance_valid(balloon)
			and is_instance_valid(balloon.dialogue_line)
			and balloon.dialogue_line.responses.size() > 0),
		"Cycle %d advances to the authored response choices." % cycle
	):
		return false
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	if not await _wait_until(
		func(): return is_instance_valid(balloon) and balloon.is_waiting_for_input,
		"Cycle %d completes the choices line before selection." % cycle
	):
		return false

	var end_response: DialogueResponse
	for response: DialogueResponse in balloon.dialogue_line.responses:
		if response.text.strip_edges() == "End the conversation":
			end_response = response
	_expect(is_instance_valid(end_response), "Cycle %d finds the existing end-conversation response." % cycle)
	if not is_instance_valid(end_response):
		return false

	balloon.show_responses()
	var end_button: Control
	for item: Control in balloon.responses_menu.get_menu_items():
		if item.get_meta("response", null) == end_response:
			end_button = item
	_expect(is_instance_valid(end_button), "Cycle %d exposes the end response in the real response menu." % cycle)
	if not is_instance_valid(end_button):
		return false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	end_button.gui_input.emit(click)

	if not await _wait_until(
		func(): return (deactivated_count == deactivation_before + 1
			and dialogue_ended_count == ended_before + 1
			and not TimeComponentManager.is_paused
			and player.can_move
			and _count_balloons() == 0),
		"Cycle %d ends once, restores Player and time, and frees the balloon." % cycle
	):
		return false
	await get_tree().process_frame
	_expect(activated_count == activation_before + 1
		and deactivated_count == deactivation_before + 1
		and dialogue_ended_count == ended_before + 1,
		"Cycle %d produces no duplicate activation, deactivation, or end callbacks." % cycle)
	_expect(not is_instance_valid(balloon) and _count_balloons() == 0 and player.current_npc_dialogue == null,
		"Cycle %d leaves no balloon or stale Player-to-NPC dialogue reference." % cycle)
	return true


func _find_balloon() -> BaseGameDialogueBalloon:
	for child: Node in get_children():
		if child is BaseGameDialogueBalloon and not child.is_queued_for_deletion():
			return child as BaseGameDialogueBalloon
	return null


func _count_balloons() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is BaseGameDialogueBalloon and not child.is_queued_for_deletion():
			count += 1
	return count


func _capture_optional_screenshot() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		return
	var capture_dir: String = OS.get_environment("TEMP")
	if capture_dir.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(capture_dir) != OK:
		push_warning("Could not create optional dialogue test screenshot directory: %s" % capture_dir)
		return
	await RenderingServer.frame_post_draw
	var capture_path: String = capture_dir.path_join("tip-dialogue-runtime-regression.png")
	var save_error: Error = get_viewport().get_texture().get_image().save_png(capture_path)
	if save_error != OK:
		push_warning("Could not save optional dialogue test screenshot: %s" % capture_path)


func _wait_until(predicate: Callable, message: String, timeout_msec: int = 5000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var passed: bool = predicate.call()
	_expect(passed, message)
	return passed


func _on_dialogue_activated() -> void:
	activated_count += 1


func _on_dialogue_deactivated() -> void:
	deactivated_count += 1


func _on_dialogue_ended(_resource: DialogueResource) -> void:
	dialogue_ended_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _finish() -> void:
	print("DialogueRuntimeRegressionTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)
