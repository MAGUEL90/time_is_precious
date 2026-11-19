extends Node2D

const VISUAL = preload("res://scenes/worker_visual/base_worker_visual.tscn")
const TONES: Array[String] = ["dark", "light", "tan", "warm"]
const HAIR_COLORS: Array[String] = ["black", "brown", "grey", "red"]
const HAIR_GENDERS: Array[String] = ["female", "male"]
const HAIR_NUMBERS: Array[String] = ["01", "02", "03"]
const CART_ROOT: String = "res://assets/characters/shared_assets"

var examples: Array[Node2D] = []
var failures: int = 0
var reported_failures: Dictionary = {}


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("292d28"))
	var poses: Array[Dictionary] = [
		{"action": "push_cart", "direction": "right"},
		{"action": "push_cart", "direction": "left"},
		{"action": "idle_cart", "direction": "right"},
		{"action": "idle_cart", "direction": "left"},
	]
	for pose_index: int in range(poses.size()):
		for tone_index: int in range(TONES.size()):
			var pose: Dictionary = poses[pose_index]
			_add_example(
				TONES[tone_index],
				str(pose["action"]),
				str(pose["direction"]),
				Vector2(50 + tone_index * 100, 30 + pose_index * 46)
			)
	if OS.get_environment("TIP_TEST_CART_ANIMATION") == "1":
		_verify.call_deferred()


func _add_example(tone: String, action: String, direction: String, position: Vector2) -> Node2D:
	var visual = VISUAL.instantiate()
	visual.position = position
	visual.skin_tone = tone
	visual.default_action = action
	visual.default_direction = direction
	visual.clothes_id = "clay_worn_wrap"
	visual.hair_style = "grey_male_01"
	visual.anim_speed = 6.0
	visual.idle_anim_speed = 1.0
	add_child(visual)
	examples.append(visual)
	var label := Label.new()
	label.text = "%s %s\n%s" % [tone, action, direction]
	label.position = position + Vector2(-34, 18)
	label.add_theme_font_size_override("font_size", 6)
	add_child(label)
	return visual


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		if not reported_failures.has(message):
			reported_failures[message] = true
			push_error(message)


func _assert_layer_source(layer: AnimatedSprite2D, animation: StringName, source_path: String, frame_count: int, message: String) -> void:
	_expect(layer.visible, "%s is visible." % message)
	_expect(layer.sprite_frames.get_frame_count(animation) == frame_count, "%s has %d source frames." % [message, frame_count])
	for index: int in range(frame_count):
		var texture: Texture2D = layer.sprite_frames.get_frame_texture(animation, index)
		_expect(texture is AtlasTexture, "%s uses a frame cut from the supplied sheet." % message)
		if texture is AtlasTexture:
			var atlas: AtlasTexture = texture as AtlasTexture
			_expect(atlas.atlas.resource_path == source_path, "%s uses its exact native source path." % message)
			_expect(atlas.region == Rect2(index * 32, 0, 32, 32), "%s keeps the right-facing source-strip frame order." % message)


func _verify() -> void:
	_expect(examples.size() == TONES.size() * 4, "The pose grid includes both actions and directions for all four tones.")
	for visual: Node2D in examples:
		var action: String = visual.default_action
		var direction: String = visual.default_direction
		var tone: String = visual.skin_tone
		var frame_count: int = 4 if action == "push_cart" else 2
		var core_animation := StringName("cart_native_core_%s_%s_%s" % [tone, action, direction])
		var body_path: String = "%s/body_assets/%s/%s/%s.png" % [CART_ROOT, action, tone, tone]
		var head_path: String = "%s/head_assets/%s/%s/%s.png" % [CART_ROOT, action, tone, tone]
		var mirrored: bool = direction == "left"
		_expect(visual.cart_visual != null and visual.cart_visual.visible, "%s %s keeps its requested cart tool visible." % [tone, action])
		_expect(visual.body_sprite.animation == core_animation and visual.head_sprite.animation == core_animation, "%s %s uses matching native body and head clips." % [tone, action])
		_assert_layer_source(visual.body_sprite, core_animation, body_path, frame_count, "%s %s body" % [tone, action])
		_assert_layer_source(visual.head_sprite, core_animation, head_path, frame_count, "%s %s head" % [tone, action])
		_expect(visual.body_sprite.flip_h == mirrored and visual.head_sprite.flip_h == mirrored, "%s %s mirrors both worker layers for %s." % [tone, action, direction])
		_expect(visual.cart_visual.flip_h == mirrored, "%s %s mirrors the cart for %s." % [tone, action, direction])
		_expect(visual.body_sprite.material == null and visual.head_sprite.material == null, "Native cart skin does not add a recolor material.")
		_expect(visual.skin_tone == tone and visual.clothes_id == "clay_worn_wrap" and visual.hair_style == "grey_male_01", "Cart playback preserves the selected tone, wrap, and hair IDs.")

		var tool_path: String = "%s/tools_assets/%s/%s.png" % [CART_ROOT, action, action]
		_assert_layer_source(visual.cart_visual, StringName("cart_native_tool_%s" % action), tool_path, frame_count, "%s %s cart tool" % [tone, action])
		_expect(visual.cart_visual.name == &"CartVisual" and visual.cart_visual.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Dynamically created cart preserves the authored name and nearest filter.")
		_expect(is_equal_approx(visual.body_sprite.sprite_frames.get_animation_speed(core_animation), 6.0 if action == "push_cart" else 1.0), "%s keeps its existing action speed." % action)
		_expect(visual.cart_visual.material == null and visual.body_sprite.material == null and visual.head_sprite.material == null, "Native cart layers use their original colors without a recolor shader.")

		var clothes_animation := StringName("cart_native_clothes_clay_worn_wrap_%s" % action)
		var clothes_path: String = "%s/cloth_assets/clay_worn_wrap/%s/%s.png" % [CART_ROOT, action, action]
		_assert_layer_source(visual.clothes_sprite, clothes_animation, clothes_path, frame_count, "%s %s selected clay wrap" % [tone, action])
		if action == "push_cart":
			var hand_path: String = "%s/hand_assets/push_cart/%s/%s.png" % [CART_ROOT, tone, tone]
			_expect(visual.hand_sprite.visible and visual.hand_sprite.animation == core_animation, "%s push pose shows its matching hand." % tone)
			_assert_layer_source(visual.hand_sprite, core_animation, hand_path, 4, "%s push hand" % tone)
			_expect(visual.hand_sprite.flip_h == mirrored, "%s push hand mirrors with the worker." % tone)
		else:
			_expect(not visual.hand_sprite.visible, "Idle-cart pose hides the push-only hand.")
		var hair_animation := StringName("cart_native_hair_grey_male_01_%s" % action)
		var hair_path: String = "%s/hair_assets/%s/grey/male/01.png" % [CART_ROOT, action]
		_assert_layer_source(visual.hair_sprite, hair_animation, hair_path, frame_count, "%s %s selected hair" % [tone, action])
		_expect(visual.hair_sprite.flip_h == mirrored, "%s selected hair mirrors with the worker." % tone)
		_expect(not visual.accessories_sprite.visible, "Unmatched accessories stay hidden in cart poses.")

	# Every authored hair selector must resolve to matching push/idle sheets,
	# with the same right-strip/mirrored-left convention in both directions.
	var hair_test: Node2D = examples[0]
	for color: String in HAIR_COLORS:
		for gender: String in HAIR_GENDERS:
			for number: String in HAIR_NUMBERS:
				var style: String = "%s_%s_%s" % [color, gender, number]
				for action: String in ["push_cart", "idle_cart"]:
					var frame_count: int = 4 if action == "push_cart" else 2
					for direction: String in ["right", "left"]:
						hair_test.play_visual("dark", "base", action, direction, "default", "clay_worn_wrap", style)
						var animation := StringName("cart_native_hair_%s_%s" % [style, action])
						var source_path: String = "%s/hair_assets/%s/%s/%s/%s.png" % [CART_ROOT, action, color, gender, number]
						_assert_layer_source(hair_test.hair_sprite, animation, source_path, frame_count, "Selected hair %s %s" % [style, action])
						_expect(hair_test.hair_sprite.flip_h == (direction == "left"), "Selected hair %s mirrors for %s." % [style, direction])
						_expect(hair_test.hair_style == style, "Selected hair ID %s remains unchanged." % style)
	_expect(hair_test.clothes_id == "clay_worn_wrap" and hair_test.skin_tone == "dark", "Cycling hair styles does not alter the selected wrap or skin tone.")

	# A separate instance has its own SpriteFrames and timing, even when the
	# source textures and animation names match another actor.
	var timing_peer = VISUAL.instantiate()
	timing_peer.skin_tone = "dark"
	timing_peer.default_action = "push_cart"
	timing_peer.default_direction = "right"
	timing_peer.clothes_id = "clay_worn_wrap"
	timing_peer.hair_style = "grey_male_01"
	timing_peer.anim_speed = 3.0
	add_child(timing_peer)
	timing_peer.play_visual("dark", "base", "push_cart", "right", "default", "clay_worn_wrap", "grey_male_01")
	_expect(timing_peer.body_sprite.sprite_frames != hair_test.body_sprite.sprite_frames, "Different actors do not share mutable SpriteFrames resources.")
	_expect(is_equal_approx(timing_peer.body_sprite.sprite_frames.get_animation_speed(&"cart_native_core_dark_push_cart_right"), 3.0), "A second actor keeps its own requested playback speed.")
	_expect(is_equal_approx(hair_test.body_sprite.sprite_frames.get_animation_speed(&"cart_native_core_dark_push_cart_right"), 6.0), "Changing one actor's speed does not change another actor's clip speed.")
	timing_peer.queue_free()

	# Repeated live controller calls must preserve frame progression and keep all
	# requested cart layers on the body's frame/progress clock.
	var seen_frames: Dictionary = {}
	var sample_until: int = Time.get_ticks_msec() + 1300
	while Time.get_ticks_msec() < sample_until:
		await get_tree().process_frame
		for visual: Node2D in examples:
			visual.play_visual(visual.skin_tone, "base", visual.default_action, visual.default_direction, "default", visual.clothes_id, visual.hair_style)
			if not seen_frames.has(visual):
				seen_frames[visual] = {}
			seen_frames[visual][visual.body_sprite.frame] = true
			for layer: AnimatedSprite2D in [visual.head_sprite, visual.hand_sprite, visual.clothes_sprite, visual.hair_sprite, visual.cart_visual]:
				if layer != null and layer.visible:
					_expect(layer.frame == visual.body_sprite.frame, "%s remains synchronized with the body under repeated calls." % layer.name)
					_expect(is_equal_approx(layer.frame_progress, visual.body_sprite.frame_progress), "%s progress remains synchronized with the body under repeated calls." % layer.name)
		if OS.get_environment("TIP_TEST_CART_ANIMATION") != "1":
			break
	for visual: Node2D in examples:
		_expect(seen_frames[visual].size() >= 2, "%s %s animation advances through multiple source frames." % [visual.skin_tone, visual.default_action])

	# Defaults and absent optional art never borrow an ordinary walk layer.
	var defaults: Node2D = VISUAL.instantiate()
	defaults.skin_tone = "light"
	defaults.default_action = "push_cart"
	defaults.clothes_id = "default"
	defaults.hair_style = "default"
	add_child(defaults)
	_expect(not defaults.clothes_sprite.visible and not defaults.hair_sprite.visible, "Default optional layers stay hidden in a cart pose.")
	_expect(defaults.skin_tone == "light" and defaults.clothes_id == "default" and defaults.hair_style == "default", "Default IDs are retained without substituting another layer.")
	defaults.queue_free()

	var missing_optional: Node2D = _make_fault_fixture("dark", "hair_assets", false)
	_expect(missing_optional.body_sprite.animation == &"cart_native_core_dark_push_cart_right", "Missing optional hair does not disable valid core cart art.")
	_expect(not missing_optional.hair_sprite.visible and missing_optional.clothes_sprite.visible, "Missing hair is hidden while the selected clay wrap remains visible.")
	_expect(missing_optional.hair_style == "grey_male_01" and missing_optional.clothes_id == "clay_worn_wrap", "Missing optional art preserves both selected IDs.")
	missing_optional.queue_free()
	var missing_wrap: Node2D = _make_fault_fixture("dark", "cloth_assets", false)
	_expect(missing_wrap.body_sprite.animation == &"cart_native_core_dark_push_cart_right", "Missing optional wrap does not disable valid core cart art.")
	_expect(not missing_wrap.clothes_sprite.visible and missing_wrap.hair_sprite.visible, "Missing wrap is hidden while selected hair remains visible.")
	missing_wrap.queue_free()
	var legacy_tool_path: String = "%s/tools/push_cart/push_cart.png" % CART_ROOT
	if ResourceLoader.exists(legacy_tool_path, "Texture2D"):
		var legacy_tool: Node2D = _make_legacy_tool_fixture()
		_assert_layer_source(legacy_tool.cart_visual, &"cart_native_tool_push_cart", legacy_tool_path, 4, "Cloud legacy cart-tool fallback")
		legacy_tool.queue_free()

	# Force each required native layer missing, then malformed, using only an
	# in-memory wrong-size texture fixture. The actual actor falls back to its
	# requested tone's ordinary pose, never to the light cart clips. A valid tool
	# remains visible, matching the legacy action-resolution presentation order.
	for missing_layer: String in ["body_assets", "head_assets", "hand_assets"]:
		var unavailable: Node2D = _make_fault_fixture("tan", missing_layer, false)
		_expect(unavailable.body_sprite.animation == &"tan_walk_right", "Missing %s falls back to the requested tan walk pose." % missing_layer)
		_expect(unavailable.head_sprite.animation == &"base_tan_walk_right", "Missing %s never substitutes the light cart head." % missing_layer)
		_expect(unavailable.cart_visual.visible, "A valid cart tool remains visible under the ordinary-pose fallback, as before.")
		_expect(unavailable.skin_tone == "tan" and unavailable.hair_style == "grey_male_01" and unavailable.clothes_id == "clay_worn_wrap", "Fallback preserves the actor's selected tone, hair, and wrap IDs.")
		_expect(unavailable.body_sprite.animation != &"cart_native_core_light_push_cart_right", "Missing %s cannot select light native cart art." % missing_layer)
		unavailable.queue_free()
	var malformed: Node2D = _make_fault_fixture("warm", "body_assets", true)
	_expect(malformed.body_sprite.animation == &"warm_walk_right" and malformed.head_sprite.animation == &"base_warm_walk_right", "A wrong-sized body sheet safely falls back to the requested warm walk pose.")
	_expect(malformed.cart_visual.visible and malformed.skin_tone == "warm", "Malformed art keeps a valid tool but does not change the selected tone.")
	malformed.queue_free()

	# Return to ordinary movement clears cart mirroring and hides the cart and
	# cart-only optional layers while using the selected ordinary layers again.
	var return_actor: Node2D = examples[1]
	return_actor.play_visual("light", "base", "idle", "right", "default", "clay_worn_wrap", "grey_male_01")
	_expect(return_actor.body_sprite.animation == &"light_idle_right", "Return to ordinary idle restores the native light idle body.")
	_expect(not return_actor.body_sprite.flip_h and not return_actor.head_sprite.flip_h, "Return to ordinary movement resets mirroring.")
	_expect(return_actor.cart_visual != null and not return_actor.cart_visual.visible, "Return to ordinary movement hides the cart tool.")
	_expect(not return_actor.hand_sprite.visible, "Ordinary idle hides hands.")
	_expect(return_actor.clothes_sprite.visible and return_actor.hair_sprite.visible, "Ordinary movement restores its selected wrap and hair layers.")

	for visual: Node2D in examples:
		visual.play_visual(visual.skin_tone, "base", visual.default_action, visual.default_direction, "default", "clay_worn_wrap", "grey_male_01")
	await _capture_pose_grid_if_requested()
	print("WorkerCartAnimationTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _make_fault_fixture(tone: String, target_path_component: String, malformed: bool) -> Node2D:
	var visual = VISUAL.instantiate()
	visual.skin_tone = tone
	visual.default_action = "push_cart"
	visual.default_direction = "right"
	visual.clothes_id = "clay_worn_wrap"
	visual.hair_style = "grey_male_01"
	visual._cart_texture_loader = Callable(self, "_load_cart_fault_fixture").bind(target_path_component, malformed)
	add_child(visual)
	return visual


func _load_cart_fault_fixture(source_path: String, target_path_component: String, malformed: bool) -> Texture2D:
	if source_path.contains("/%s/" % target_path_component):
		if malformed:
			var invalid_image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
			return ImageTexture.create_from_image(invalid_image)
		return null
	if not ResourceLoader.exists(source_path, "Texture2D"):
		return null
	return ResourceLoader.load(source_path) as Texture2D


func _make_legacy_tool_fixture() -> Node2D:
	var visual = VISUAL.instantiate()
	visual.skin_tone = "dark"
	visual.default_action = "push_cart"
	visual.default_direction = "right"
	visual.clothes_id = "default"
	visual.hair_style = "default"
	visual._cart_texture_loader = Callable(self, "_load_legacy_tool_fixture")
	add_child(visual)
	return visual


func _load_legacy_tool_fixture(source_path: String) -> Texture2D:
	if source_path.contains("/tools_assets/"):
		return null
	if not ResourceLoader.exists(source_path, "Texture2D"):
		return null
	return ResourceLoader.load(source_path) as Texture2D


func _capture_pose_grid_if_requested() -> void:
	var capture_dir: String = OS.get_environment("TIP_CART_CAPTURE_DIR")
	if DisplayServer.get_name() == "headless" or capture_dir == "":
		return
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(capture_dir)
	_expect(make_dir_error == OK, "Cart capture directory can be created.")
	await RenderingServer.frame_post_draw
	var output_path: String = capture_dir.path_join("tip-worker-cart-native-grid.png")
	var save_error: Error = get_viewport().get_texture().get_image().save_png(output_path)
	_expect(save_error == OK, "Cart pose grid capture is saved to the requested directory.")
