extends SceneTree
func _initialize() -> void:
	root.call_deferred("add_child", load("res://scenes/test_scenes/test_scene_disabled_legacy_world.gd").new())
