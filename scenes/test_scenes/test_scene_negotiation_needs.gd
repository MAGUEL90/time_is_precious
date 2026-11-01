extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const NPC_SCENE: PackedScene = preload("res://scenes/npc_children/npc_galsal/npc_galsal.tscn")
const GALSAL_DIALOGUE: DialogueResource = preload("res://dialogue/game_dialogue_conversations/gal-sal/galsal.dialogue")

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	var npc: NPCBase = NPC_SCENE.instantiate() as NPCBase
	npc.allow_random_walk = false
	add_child(npc)
	await get_tree().process_frame
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	player.hunger = 0.2
	player.fatigue = 0.3
	var now: int = _now()
	var inventory: Dictionary = Inventory.items.duplicate(true)
	for attempt: int in range(2):
		npc.try_negotiate_contract()
		_expect(_now() == now and is_equal_approx(player.hunger, 0.2) and is_equal_approx(player.fatigue, 0.3), "Disabled negotiation leaves time and player needs unchanged on repeated calls.")
		_expect(not npc.is_contract_activated and Inventory.items == inventory, "Disabled negotiation neither activates a contract nor changes inventory.")

	var greeting: DialogueLine = await GALSAL_DIALOGUE.get_next_dialogue_line("contract_galsal_1", [npc])
	_expect(is_instance_valid(greeting), "The normal contract greeting loads.")
	if is_instance_valid(greeting):
		var first_yes: DialogueResponse = _response(greeting, "Yes")
		_expect(first_yes != null and _response(greeting, "No") != null, "Ordinary Yes and No choices remain available.")
		if first_yes != null:
			var choice: DialogueLine = await GALSAL_DIALOGUE.get_next_dialogue_line(first_yes.next_id, [npc])
			_expect(is_instance_valid(choice), "The normal contract choice loads.")
			if is_instance_valid(choice):
				var contract_yes: DialogueResponse = _response(choice, "Yes")
				_expect(contract_yes != null and _response(choice, "No") != null, "The normal accept and decline choices remain available.")
				_expect(_response(choice, "Listen to me (Negotiate)") == null, "Negotiation is absent from the actual dialogue choices.")
				if contract_yes != null:
					var accepted: DialogueLine = await GALSAL_DIALOGUE.get_next_dialogue_line(contract_yes.next_id, [npc])
					_expect(is_instance_valid(accepted) and accepted.text.contains("You got me"), "Accepting the ordinary contract reaches the existing response.")
					if is_instance_valid(accepted):
						await GALSAL_DIALOGUE.get_next_dialogue_line(accepted.next_id, [npc])
						_expect(npc.is_contract_activated, "The ordinary contract remains functional.")
	var casual: DialogueLine = await GALSAL_DIALOGUE.get_next_dialogue_line("casual_galsal_1", [npc])
	_expect(is_instance_valid(casual) and casual.text.contains("this is TEST dialogue"), "Ordinary casual conversation still opens.")
	BaseDialogueManager.dialogue_deactivated.emit()
	npc.free()
	player.free()
	print("NegotiationNeedsTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _response(line: DialogueLine, text_value: String) -> DialogueResponse:
	for response: DialogueResponse in line.responses:
		if response.is_allowed and response.text == text_value:
			return response
	return null

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
