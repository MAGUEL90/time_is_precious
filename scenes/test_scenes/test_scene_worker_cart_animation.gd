extends Node2D

const VISUAL = preload("res://scenes/worker_visual/base_worker_visual.tscn")

var examples: Array[Node2D] = []
var failures: int = 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("292d28"))
	_add_example("push_cart", "right", Vector2(110, 64))
	_add_example("push_cart", "left", Vector2(190, 64))
	_add_example("idle_cart", "right", Vector2(110, 122))
	_add_example("idle_cart", "left", Vector2(190, 122))
	_add_example("push_cart", "right", Vector2(270, 64), "dark")
	_add_example("push_cart", "left", Vector2(350, 64), "dark")
	_add_example("idle_cart", "right", Vector2(270, 122), "dark")
	_add_example("idle_cart", "left", Vector2(350, 122), "dark")
	if OS.get_environment("TIP_TEST_CART_ANIMATION") == "1":
		_verify.call_deferred()


func _add_example(action: String, direction: String, position: Vector2, tone: String = "light") -> void:
	var visual = VISUAL.instantiate()
	visual.position = position
	visual.skin_tone = tone
	visual.default_action = action
	visual.default_direction = direction
	add_child(visual)
	examples.append(visual)
	var label := Label.new()
	label.text = tone + " " + action + "\n" + direction
	label.position = position + Vector2(-28, 18)
	label.add_theme_font_size_override("font_size", 6)
	add_child(label)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _verify() -> void:
	var push_right: Node2D = examples[0]
	var push_left: Node2D = examples[1]
	var idle_right: Node2D = examples[2]
	var idle_left: Node2D = examples[3]
	_expect(is_equal_approx(idle_right.idle_anim_speed, 1.0), "World idle retains its original speed.")
	for visual: Node2D in examples:
		_expect(visual.cart_visual.visible and visual.cart_visual.animation == StringName(visual.default_action), "Supplied cart layer follows the requested action.")
		_expect(visual.cart_visual.flip_h == (visual.default_direction == "left"), "Cart layer mirrors with worker.")

	for visual: Node2D in [push_right, push_left]:
		_expect(visual.body_sprite.animation == StringName("light_push_cart_" + ("right" if visual == push_right else "left")), "Push body uses the cart clip.")
		_expect(visual.head_sprite.animation == StringName("base_light_push_cart_" + ("right" if visual == push_right else "left")), "Push head uses the cart clip.")
		_expect(visual.hand_sprite.animation == visual.body_sprite.animation, "Push hand stays synchronized with the body clip.")
		_expect(visual.body_sprite.sprite_frames.get_frame_count(visual.body_sprite.animation) == 4, "Push body has four source frames.")
		_expect(visual.head_sprite.sprite_frames.get_frame_count(visual.head_sprite.animation) == 4, "Push head has four source frames.")
		_expect(visual.hand_sprite.sprite_frames.get_frame_count(visual.hand_sprite.animation) == 4, "Push hand has four source frames.")
		_expect(visual.hand_sprite.visible, "Push pose shows the supplied hand layer.")
		_expect(visual.clothes_sprite.visible == false and visual.hair_sprite.visible == false and visual.accessories_sprite.visible == false, "Push pose hides unmatched optional layers.")
		var mirrored: bool = visual == push_left
		_expect(visual.body_sprite.flip_h == mirrored and visual.head_sprite.flip_h == mirrored and visual.hand_sprite.flip_h == mirrored, "Cart pose mirrors consistently in both directions.")

	for visual: Node2D in [idle_right, idle_left]:
		var direction: String = "right" if visual == idle_right else "left"
		_expect(visual.body_sprite.animation == StringName("light_idle_cart_" + direction), "Idle body uses the cart clip.")
		_expect(visual.head_sprite.animation == StringName("base_light_idle_cart_" + direction), "Idle head uses the cart clip.")
		_expect(visual.body_sprite.sprite_frames.get_frame_count(visual.body_sprite.animation) == 2, "Idle body has two source frames.")
		_expect(visual.head_sprite.sprite_frames.get_frame_count(visual.head_sprite.animation) == 2, "Idle head has two source frames.")
		_expect(not visual.hand_sprite.visible, "Idle pose does not use the push-only hand layer.")
		_expect(visual.clothes_sprite.visible == false and visual.hair_sprite.visible == false and visual.accessories_sprite.visible == false, "Idle pose hides unmatched optional layers.")
		var mirrored: bool = visual == idle_left
		_expect(visual.body_sprite.flip_h == mirrored and visual.head_sprite.flip_h == mirrored, "Idle cart pose mirrors consistently in both directions.")

	# The live controller calls play_visual every frame. It must not restart a clip.
	var seen_frames: Dictionary = {}
	var sample_until: int = Time.get_ticks_msec() + 1300
	while Time.get_ticks_msec() < sample_until:
		await get_tree().process_frame
		for visual: Node2D in examples:
			visual.play_visual(visual.skin_tone, "base", visual.default_action, visual.default_direction, "default", "default", "default")
			if not seen_frames.has(visual):
				seen_frames[visual] = {}
			seen_frames[visual][visual.body_sprite.frame] = true
			_expect(visual.cart_visual.frame == visual.body_sprite.frame and visual.head_sprite.frame == visual.body_sprite.frame, "Cart, head and body frames stay synchronized during repeated playback requests.")
			if visual.default_action == "push_cart":
				_expect(visual.hand_sprite.frame == visual.body_sprite.frame, "Pushing hand advances with body and cart.")
	for visual: Node2D in examples:
		_expect(seen_frames[visual].size() >= 2, "Both light and dark cart animations visibly advance through multiple frames.")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-worker-cart-animation.png"))

	var fallback = VISUAL.instantiate()
	fallback.skin_tone = "dark"
	add_child(fallback)
	fallback.play_visual("dark", "base", "push_cart", "left", "default", "clay_worn_wrap", "grey_male_01")
	_expect(fallback.body_sprite.animation == &"light_push_cart_left", "A dark Hauler still uses the supplied push-cart motion.")
	_expect(fallback.body_sprite.material == null and fallback.head_sprite.material == null and fallback.hand_sprite.material == null, "Cart skin uses the original light colors without an added recolor shader.")
	for layer: AnimatedSprite2D in [fallback.body_sprite, fallback.head_sprite, fallback.hand_sprite]:
		var atlas: AtlasTexture = layer.sprite_frames.get_frame_texture(layer.animation, 0)
		var part: String = {"BodySprite": "body", "HeadSprite": "head", "HandSprite": "hand"}[str(layer.name)]
		_expect(atlas.atlas.resource_path == "res://assets/characters/shared_assets/%s_assets/push_cart/light/light.png" % part, "Push-cart layers use the supplied head, body and hand assets directly.")
	_expect(fallback.body_sprite.flip_h and fallback.head_sprite.flip_h and fallback.hand_sprite.flip_h, "Shared cart motion mirrors all worker layers together.")
	fallback.play_visual("dark", "base", "idle_cart", "left", "default", "clay_worn_wrap", "grey_male_01")
	_expect(fallback.body_sprite.animation == &"light_idle_cart_left", "A dark Hauler uses idle-cart motion while waiting.")
	_expect(not fallback.hand_sprite.visible, "Idle-cart fallback keeps hands hidden.")
	for tone: String in ["dark", "tan", "warm"]:
		for direction: String in ["left", "right"]:
			fallback.play_visual(tone, "base", "push_cart", direction, "default", "default", "default")
			_expect(fallback.body_sprite.animation == StringName("light_push_cart_" + direction) and fallback.skin_tone == tone, "Every profile uses the supplied light cart motion without altering its stored profile.")
			_expect(fallback.body_sprite.material == null and fallback.head_sprite.material == null and fallback.hand_sprite.material == null, "All three cart layers keep the original light asset colors.")
			_expect(not fallback.clothes_sprite.visible and not fallback.hair_sprite.visible, "Cart fallback does not add unrequested clothes or hair.")
		fallback.play_visual(tone, "base", "walk", "right", "default", "default", "default")
		_expect(fallback.body_sprite.animation == StringName(tone + "_walk_right") and fallback.body_sprite.material == null and fallback.head_sprite.material == null and fallback.hand_sprite.material == null, "Ordinary movement restores the native skin art and materials.")
	fallback.queue_free()

	push_left.play_visual("light", "base", "idle", "right", "default", "clay_worn_wrap", "grey_male_01")
	_expect(not push_left.body_sprite.flip_h and not push_left.head_sprite.flip_h, "Returning to ordinary art clears cart mirroring.")

	print("WorkerCartAnimationTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
