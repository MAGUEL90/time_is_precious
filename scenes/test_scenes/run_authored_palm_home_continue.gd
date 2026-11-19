extends SceneTree

func _initialize() -> void:
	var fixture: Node = load("res://scenes/test_scenes/test_scene_authored_palm_home_continue.gd").new()
	root.call_deferred("add_child", fixture)
