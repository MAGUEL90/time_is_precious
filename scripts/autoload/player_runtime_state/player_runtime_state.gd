extends Node

# Persists gameplay state between scene-local Player instances for this run.

var _state: Dictionary = {}

func capture(player: Player) -> void:
	_state = {
		"fatigue": player.fatigue,
		"hunger": player.hunger,
		"focus": player.focus,
		"current_experience": player.current_experience,
		"last_sleep_day": player.last_sleep_day,
		"last_collapse_day": player.last_collapse_day,
		"total_collapse_count": player.total_collapse_count
	}

func restore(player: Player) -> void:
	if _state.is_empty():
		return

	player.fatigue = float(_state.get("fatigue", player.fatigue))
	player.hunger = float(_state.get("hunger", player.hunger))
	player.focus = float(_state.get("focus", player.focus))

	player.current_experience = int(
		_state.get("current_experience", player.current_experience)
	)

	player.last_sleep_day = int(
		_state.get("last_sleep_day", player.last_sleep_day)
	)

	player.last_collapse_day = int(
		_state.get("last_collapse_day", player.last_collapse_day)
	)

	player.total_collapse_count = int(
		_state.get("total_collapse_count", player.total_collapse_count)
	)
