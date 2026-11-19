extends SceneTree

func _initialize() -> void:
	var test: Node = load("res://scenes/test_scenes/test_scene_authored_palm_copy_migration.gd").new()
	root.call_deferred("add_child", test)
