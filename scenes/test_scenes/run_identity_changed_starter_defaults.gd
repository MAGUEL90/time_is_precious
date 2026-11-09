extends SceneTree

func _initialize() -> void:
	# Simulate edited New Game resources while loading an older stored identity.
	# The edits are process-local; original files and fixture bytes stay intact.
	for path: String in ["initial_laborer_seed", "initial_worksite_laborer_seed", "initial_city_hauler_seed"]:
		var seed: InitialCitizenSeed = load("res://scenes/content_scene/startup/" + path + ".tres")
		seed.display_name = "Changed new-citizen name"
		seed.satisfaction = 0.9
		seed.visual_profile.skin_tone = "warm"
		seed.visual_profile.hair_style = "red_female_03"
	var test: Node = load("res://scenes/test_scenes/test_scene_civil_identity_persistence.gd").new()
	root.call_deferred("add_child", test)
