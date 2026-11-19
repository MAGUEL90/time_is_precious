extends SceneTree
func _initialize() -> void:
	var probe: Node = load("res://scenes/test_scenes/test_scene_sleep_pending_home_probe.gd").new()
	probe.cross_shift = OS.get_cmdline_user_args().has("--cross-shift")
	root.call_deferred("add_child", probe)
