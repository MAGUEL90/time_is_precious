extends Node2D

const VISUAL = preload("res://scenes/worker_visual/base_worker_visual.tscn")
var examples: Array[Node2D] = []

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("292d28"))
	var tones: Array[String] = ["dark", "light", "tan", "warm"]
	for column in range(4):
		var label := Label.new()
		label.text = tones[column]
		label.position = Vector2(92 + column * 76, 8)
		label.add_theme_font_size_override("font_size", 10)
		add_child(label)
	for row in range(4):
		var face: String = "base" if row < 2 else "tired"
		var direction: String = "right" if row % 2 == 0 else "left"
		var label := Label.new()
		label.text = face + "\n" + direction
		label.position = Vector2(8, 35 + row * 48)
		label.add_theme_font_size_override("font_size", 10)
		add_child(label)
		for column in range(4):
			var visual = VISUAL.instantiate()
			visual.position = Vector2(108 + column * 76, 49 + row * 48)
			visual.default_action = "work"
			visual.default_direction = direction
			visual.skin_tone = tones[column]
			visual.expression = face
			add_child(visual)
			examples.append(visual)
	if OS.get_environment("TIP_TEST_WORK_ANIMATION") == "1":
		_verify.call_deferred()

func _verify() -> void:
	var failures: int = 0
	for visual in examples:
		for layer: AnimatedSprite2D in [visual.body_sprite, visual.head_sprite]:
			if not layer.visible or layer.sprite_frames.get_frame_count(layer.animation) != 8:
				failures += 1
			for i in range(8):
				var expected_duration: float = 2.0 if visual.expression == "tired" and (i == 0 or i == 7) else 1.0
				if not is_equal_approx(layer.sprite_frames.get_frame_duration(layer.animation, i), expected_duration):
					failures += 1
				var atlas: AtlasTexture = layer.sprite_frames.get_frame_texture(layer.animation, i)
				if not Rect2(Vector2.ZERO, atlas.atlas.get_size()).encloses(atlas.region):
					failures += 1
		if visual.hand_sprite.visible or visual.clothes_sprite.visible or visual.hair_sprite.visible or visual.accessories_sprite.visible:
			failures += 1
	await get_tree().create_timer(0.4).timeout
	for visual in examples:
		if visual.body_sprite.frame == 0 or visual.body_sprite.frame != visual.head_sprite.frame:
			failures += 1
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-worker-work-animation.png"))
	var sample = examples[0]
	sample.play_visual("light", "tired", "work", "left", "default")
	sample.play_visual("light", "base", "work", "left", "default")
	if not is_equal_approx(sample.body_sprite.sprite_frames.get_frame_duration(sample.body_sprite.animation, 0), 1.0):
		failures += 1
	for action: String in ["idle", "walk", "work"]:
		sample.play_visual("light", "base", action, "left", "default", "clay_worn_wrap", "grey_male_01")
		if sample.body_sprite.animation != StringName("light_" + action + "_left"):
			failures += 1
		if action != "work" and (not sample.clothes_sprite.visible or not sample.hair_sprite.visible):
			failures += 1
	print("WorkerWorkAnimationTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
