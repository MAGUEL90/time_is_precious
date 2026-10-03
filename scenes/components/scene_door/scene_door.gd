class_name SceneDoor extends Area2D

@export_file("*.tscn") var target_scene_path: String
@export var target_spawn_point: StringName
@export var transition_message: String = ""

var _is_triggered: bool = false

# Lifecycle

func _ready() -> void:
	body_entered.connect(_on_body_entered)

# Door interaction

func _on_body_entered(body: Node2D) -> void:
	if _is_triggered or SceneTransition.is_transitioning or not body is Player:
		return

	if target_scene_path.is_empty():
		push_warning("SceneDoor has no target scene.")
		return

	_is_triggered = true

	# A successful scene swap frees this door; the autoload owns the full fade.
	SceneTransition.run_with_fade(
		Callable(self, "_change_scene"),
		0.35,
		0.15,
		transition_message
	)

func _change_scene() -> bool:
	SceneTransition.queue_spawn_point(target_spawn_point)
	var error: Error = get_tree().change_scene_to_file(target_scene_path)

	if error != OK:
		SceneTransition.clear_spawn_point()
		_is_triggered = false
		return false

	return true
