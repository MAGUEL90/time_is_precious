extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const NPC_SCENE: PackedScene = preload("res://scenes/npc_children/npc_galsal/npc_galsal.tscn")

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	var npc: NPCBase = NPC_SCENE.instantiate() as NPCBase
	npc.allow_random_walk = false
	add_child(npc)
	await get_tree().process_frame
	# Compare negotiation against the same elapsed time, not a second needs formula.
	for duration: int in [15, 30]:
		_set_conditions(player)
		TimeComponentManager.advance_minutes(duration)
		var expected: Vector3 = Vector3(player.hunger, player.fatigue, player.focus)
		_set_conditions(player)
		npc.negotiation_base_duration_minutes = duration
		var before: int = _now()
		npc.try_negotiate_contract()
		_expect(_now() - before == duration, "Negotiation advances its configured world time exactly once.")
		_expect(is_equal_approx(player.hunger, expected.x), "Negotiation adds no direct Hunger cost beyond elapsed time.")
		_expect(is_equal_approx(player.fatigue, expected.y), "Negotiation adds no direct Fatigue cost beyond elapsed time.")
		_expect(is_equal_approx(player.focus, expected.z), "Existing time-driven Focus loss is preserved.")
		_expect(not player.is_collapsing, "Healthy negotiation does not trigger an unexpected collapse.")
	npc.free()
	player.free()
	print("NegotiationNeedsTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _set_conditions(player: Player) -> void:
	player.hunger = 0.2
	player.fatigue = 0.3
	player.focus = 0.8

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
