extends SceneTree
func _initialize() -> void:
	_setup.call_deferred()
func _setup() -> void:
	var probe: Node = load("res://scenes/test_scenes/test_scene_nightmare_graphical_exact_probe.gd").new()
	root.add_child(probe)
	current_scene = probe
