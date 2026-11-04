extends "res://scenes/workshop_plot/worker_entry_dust.gd"

## Reuse the existing pixel puff and freeze it with the city simulation.
func _process(delta: float) -> void:
	if TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return
	super._process(delta)
