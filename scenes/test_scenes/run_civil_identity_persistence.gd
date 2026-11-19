extends SceneTree

func _initialize() -> void:
	var test: Node = load("res://scenes/test_scenes/test_scene_civil_identity_persistence.gd").new()
	root.call_deferred("add_child", test)
