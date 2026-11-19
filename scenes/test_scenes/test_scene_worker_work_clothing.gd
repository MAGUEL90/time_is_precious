extends Node2D

const VISUAL = preload("res://scenes/worker_visual/base_worker_visual.tscn")
const WORKSITE_OWNER = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_worker_visuals.gd")
const SHEET_PATH: String = "res://assets/characters/shared_assets/cloth_assets/clay_worn_wrap/busy/busy.png"
const FIXTURE_ID: String = "__worker_work_clothing_test__"
const POSES := {
	"right": [0, 1, 2, 3, 4, 5, 6, 5],
	"left": [5, 6, 5, 4, 3, 2, 7, 8],
}

class TestDaily:
	extends RefCounted
	func is_hauler(_id: String) -> bool:
		return false

class TestWorksite:
	extends Node2D
	var daily = TestDaily.new()

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _new_visual(outfit: String = "clay_worn_wrap") -> Node2D:
	var visual = VISUAL.instantiate()
	visual.skin_tone = "light"
	visual.clothes_id = outfit
	visual.hair_style = "black_male_01"
	add_child(visual)
	return visual


func _run() -> void:
	var visual = _new_visual()
	var other = _new_visual()
	_expect(visual.clothes_sprite.sprite_frames != other.clothes_sprite.sprite_frames,
		"Actors must not share mutable clothing animation timing.")

	for direction: String in ["right", "left"]:
		visual.play_visual("light", "base", "work", direction, "default", "clay_worn_wrap", "black_male_01")
		var animation: String = "clay_worn_wrap_work_" + direction
		var frames: SpriteFrames = visual.clothes_sprite.sprite_frames
		_expect(visual.clothes_sprite.visible and visual.clothes_sprite.animation == StringName(animation),
			"The selected clay wrap has a visible work clip facing " + direction)
		_expect(not visual.clothes_sprite.flip_h, "Each facing uses its authored sheet poses without flipping.")
		if not frames.has_animation(animation):
			_expect(false, "The clay work animation exists: " + direction)
			continue
		_expect(frames.get_frame_count(animation) == 8, "The clay work clip covers all eight body poses: " + direction)
		if frames.get_frame_count(animation) != 8:
			continue
		for index: int in range(8):
			var texture: Texture2D = frames.get_frame_texture(animation, index)
			_expect(texture is AtlasTexture, "Every work pose uses an atlas region.")
			if texture is AtlasTexture:
				var atlas: AtlasTexture = texture as AtlasTexture
				_expect(atlas.atlas != null and atlas.atlas.resource_path == SHEET_PATH,
					"Every work pose references the supplied clay work sheet.")
				_expect(atlas.region == Rect2(int(POSES[direction][index]) * 32, 0, 32, 32),
					"Work pose region matches its directional body frame: %s/%d" % [direction, index])
			_expect(is_equal_approx(frames.get_frame_duration(animation, index), 1.0),
				"Normal work uses the unmodified frame duration.")

	# The selected plain wrap has no work sheet. The real clay work wrap is a
	# temporary presentation fallback, not a change to the citizen's profile.
	for direction: String in ["right", "left"]:
		visual.play_visual("light", "base", "work", direction, "default", "plain_worn_wrap", "black_male_01")
		_expect(visual.clothes_id == "plain_worn_wrap" and visual.hair_style == "black_male_01",
			"Work does not replace the selected clothes or hair identity.")
		_expect(visual.clothes_sprite.visible and visual.clothes_sprite.animation == StringName("clay_worn_wrap_work_" + direction),
			"A non-default outfit without matching work art uses the clay wrap temporarily.")
		for action: String in ["idle", "walk"]:
			visual.play_visual("light", "base", action, direction, "default", "plain_worn_wrap", "black_male_01")
			_expect(visual.clothes_sprite.visible and visual.clothes_sprite.animation == StringName("plain_worn_wrap_" + action + "_" + direction),
				"Leaving work restores the selected outfit: " + action + "/" + direction)
			_expect(visual.hair_sprite.visible and visual.hair_sprite.animation == StringName("black_male_01_" + action + "_" + direction),
				"Leaving work restores the selected hair: " + action + "/" + direction)

	for empty_outfit: String in ["default", "none"]:
		visual.play_visual("light", "base", "work", "right", "default", empty_outfit, "default")
		_expect(not visual.clothes_sprite.visible and visual.clothes_id == empty_outfit,
			"An intentional empty outfit stays empty during work: " + empty_outfit)

	# A later genuine outfit-specific eight-pose clip takes precedence over the fallback.
	var clothing_frames: SpriteFrames = visual.clothes_sprite.sprite_frames
	clothing_frames.add_animation("plain_worn_wrap_work_right")
	for index: int in range(8):
		clothing_frames.add_frame("plain_worn_wrap_work_right", clothing_frames.get_frame_texture("clay_worn_wrap_work_right", index))
	visual.play_visual("light", "base", "work", "right", "default", "plain_worn_wrap", "black_male_01")
	_expect(visual.clothes_sprite.animation == &"plain_worn_wrap_work_right",
		"A compatible outfit-specific clip wins over the temporary clay fallback.")
	var missing_atlas := AtlasTexture.new()
	missing_atlas.region = Rect2(0, 0, 32, 32)
	clothing_frames.set_frame("plain_worn_wrap_work_right", 3, missing_atlas)
	visual.play_visual("light", "base", "idle", "right", "default", "plain_worn_wrap", "black_male_01")
	visual.play_visual("light", "base", "work", "right", "default", "plain_worn_wrap", "black_male_01")
	_expect(visual.clothes_sprite.animation == &"clay_worn_wrap_work_right" and visual.clothes_id == "plain_worn_wrap",
		"A missing texture inside an outfit-specific clip uses the intact work fallback without changing identity.")

	# Tired holds apply consistently, then reset, without affecting another actor.
	visual.play_visual("light", "tired", "work", "left", "default", "clay_worn_wrap", "black_male_01")
	for layer: AnimatedSprite2D in [visual.body_sprite, visual.head_sprite, visual.clothes_sprite, visual.hair_sprite]:
		for index: int in range(8):
			var expected: float = 2.0 if index == 0 or index == 7 else 1.0
			_expect(is_equal_approx(layer.sprite_frames.get_frame_duration(layer.animation, index), expected),
				"Tired timing remains aligned across body, head, and work clothing.")
	_expect(is_equal_approx(other.clothes_sprite.sprite_frames.get_frame_duration("clay_worn_wrap_work_left", 0), 1.0),
		"Tired timing does not change a different actor's frames.")
	visual.play_visual("light", "base", "work", "left", "default", "clay_worn_wrap", "black_male_01")
	for layer: AnimatedSprite2D in [visual.body_sprite, visual.head_sprite, visual.clothes_sprite, visual.hair_sprite]:
		_expect(is_equal_approx(layer.sprite_frames.get_frame_duration(layer.animation, 0), 1.0),
			"Returning to a normal expression restores the original frame timing.")

	# Ordinary playback and repeated work requests must keep the same displayed frame.
	var observed: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		visual.play_visual("light", "base", "work", "left", "default", "clay_worn_wrap", "black_male_01")
		observed[visual.body_sprite.frame] = true
		_expect(visual.clothes_sprite.frame == visual.body_sprite.frame and not visual.clothes_sprite.is_playing(),
			"The body clock drives the displayed work clothing frame.")
	_expect(observed.size() > 1, "The body advances while work requests repeat.")

	await _test_full_work_playback(visual)
	_test_missing_work_asset()
	_test_worksite_owner()
	if not OS.get_environment("TIP_WORK_CLOTHING_CAPTURE_DIR").is_empty() and DisplayServer.get_name() != "headless":
		await _capture_pose_grid()
	visual.free()
	other.free()
	print("WorkerWorkClothingTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _test_full_work_playback(visual: Node2D) -> void:
	for direction: String in ["right", "left"]:
		for expression: String in ["base", "tired"]:
			visual.play_visual("light", expression, "work", direction, "default", "clay_worn_wrap", "black_male_01")
			var seen: Dictionary = {}
			var deadline: int = Time.get_ticks_msec() + 600
			while Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
				var frame: int = visual.body_sprite.frame
				seen[frame] = true
				_expect(visual.head_sprite.frame == frame and visual.hair_sprite.frame == frame and visual.clothes_sprite.frame == frame,
					"Timed work playback keeps all visible layers on the same pose: %s/%s/%d" % [direction, expression, frame])
			_expect(seen.size() > 1, "Timed work advances through multiple poses: %s/%s" % [direction, expression])
			# A manual owner must set both independently animated body and head.
			visual.body_sprite.pause()
			visual.head_sprite.pause()
			for frame: int in range(8):
				visual.body_sprite.set_frame_and_progress(frame, 0.0)
				visual.head_sprite.set_frame_and_progress(frame, 0.0)
				_expect(visual.head_sprite.frame == frame and visual.hair_sprite.frame == frame and visual.clothes_sprite.frame == frame,
					"Manual full-character poses stay aligned: %s/%s/%d" % [direction, expression, frame])
		for action: String in ["idle", "walk"]:
			visual.play_visual("light", "base", action, direction, "default", "clay_worn_wrap", "black_male_01")
			_expect(str(visual.head_sprite.animation) == "base_light_%s_%s" % [action, direction]
				and visual.head_sprite.is_playing() and visual.body_sprite.is_playing(),
				"Leaving work restores the original animated body and head: %s/%s" % [action, direction])


func _test_missing_work_asset() -> void:
	var visual = _new_visual("plain_worn_wrap")
	var frames: SpriteFrames = visual.clothes_sprite.sprite_frames
	frames.remove_animation("clay_worn_wrap_work_left")
	frames.remove_animation("clay_worn_wrap_work_right")
	_expect(not visual._install_clay_work_animations(null), "Missing work art does not register invalid animations.")
	var small_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var small_texture := ImageTexture.create_from_image(small_image)
	_expect(not visual._install_clay_work_animations(small_texture), "An incorrectly sized sheet is rejected.")
	_expect(not frames.has_animation("clay_worn_wrap_work_right"), "Invalid input leaves no fabricated work clip.")
	visual.play_visual("light", "base", "work", "right", "default", "plain_worn_wrap", "black_male_01")
	_expect(visual.clothes_sprite.visible and visual.clothes_sprite.animation == &"plain_worn_wrap_idle_right",
		"If the supplied sheet is unavailable, an existing selected outfit pose is held visibly.")
	_expect(not visual.clothes_sprite.is_playing() and visual.clothes_id == "plain_worn_wrap",
		"The missing-sheet pose is static and the profile is retained.")
	visual.play_visual("light", "base", "walk", "right", "default", "plain_worn_wrap", "black_male_01")
	_expect(visual.clothes_sprite.animation == &"plain_worn_wrap_walk_right", "Normal clothing resumes after a missing work sheet.")
	visual.free()


func _test_worksite_owner() -> void:
	var fixture := TestWorksite.new()
	add_child(fixture)
	var owner = Node2D.new()
	owner.set_script(WORKSITE_OWNER)
	owner.set_process(false)
	fixture.add_child(owner)
	var citizen := CitizenData.new()
	citizen.citizen_id = FIXTURE_ID
	citizen.visual_profile = VisualProfile.new()
	citizen.visual_profile.skin_tone = "tan"
	citizen.visual_profile.clothes_id = "plain_worn_wrap"
	citizen.visual_profile.hair_style = "black_male_01"
	var worker := WorkerData.new()
	worker.worker_id = FIXTURE_ID
	CitizenManager.citizens_by_id[FIXTURE_ID] = citizen
	WorkerDatabase.workers_by_id[FIXTURE_ID] = worker
	var actor = owner.ensure_actor(FIXTURE_ID, Vector2.ZERO)
	_expect(actor != null, "A worksite owner creates an actor for the linked profile.")
	if actor != null:
		actor.show()
		_expect(actor.clothes_id == "plain_worn_wrap" and actor.hair_style == "black_male_01",
			"Worksite creation preserves linked clothing and hair identities.")
		for direction: String in ["right", "left"]:
			for index: int in range(7):
				owner.work_cycles[FIXTURE_ID] = {"phase": 1, "elapsed": float(index) / actor.anim_speed,
					"direction": direction, "origin": Vector2.ZERO, "target": Vector2.ZERO, "idle": 1.0}
				owner._update_work_cycle(FIXTURE_ID, actor, Vector2.ZERO, direction, 0.0)
				_expect(actor.body_sprite.frame == index and actor.head_sprite.frame == index and actor.clothes_sprite.frame == index and actor.hair_sprite.frame == index,
					"Manual worksite frames keep body, head, clothing, and hair aligned: %s/%d" % [direction, index])
				_expect(not actor.body_sprite.is_playing() and not actor.head_sprite.is_playing() and not actor.clothes_sprite.is_playing() and not actor.hair_sprite.is_playing(),
					"The worksite owns the manual frame clock.")
		owner.work_cycles[FIXTURE_ID] = {"phase": 1, "elapsed": 7.0 / actor.anim_speed - 0.01,
			"direction": "right", "origin": Vector2.ZERO, "target": Vector2.ZERO, "idle": 1.0}
		owner._update_work_cycle(FIXTURE_ID, actor, Vector2.ZERO, "right", 0.02)
		_expect(actor.body_sprite.animation == &"tan_work_left" and actor.clothes_sprite.animation == &"clay_worn_wrap_work_left",
			"The worksite's facing change updates the clothing with the body.")
		_expect(actor.body_sprite.frame == actor.head_sprite.frame and actor.body_sprite.frame == actor.clothes_sprite.frame and actor.body_sprite.frame == actor.hair_sprite.frame,
			"The worksite's facing transition starts on the same frame.")
		owner._play(actor, "idle", "left")
		_expect(actor.clothes_sprite.animation == &"plain_worn_wrap_idle_left" and actor.hair_sprite.animation == &"black_male_01_idle_left",
			"Worksite idle restores the linked profile after work.")
		_expect(citizen.visual_profile.clothes_id == "plain_worn_wrap" and citizen.visual_profile.hair_style == "black_male_01",
			"Worksite presentation never mutates the linked profile.")
	fixture.free()
	WorkerDatabase.workers_by_id.erase(FIXTURE_ID)
	CitizenManager.citizens_by_id.erase(FIXTURE_ID)


func _capture_pose_grid() -> void:
	var holder := Node2D.new()
	add_child(holder)
	for row: int in range(2):
		var direction: String = "right" if row == 0 else "left"
		for index: int in range(8):
			var actor = VISUAL.instantiate()
			actor.skin_tone = "light"
			actor.clothes_id = "clay_worn_wrap"
			actor.default_action = "work"
			actor.default_direction = direction
			actor.position = Vector2(24 + index * 48, 56 + row * 70)
			holder.add_child(actor)
			actor.body_sprite.pause()
			actor.head_sprite.pause()
			actor.body_sprite.set_frame_and_progress(index, 0.0)
			actor.head_sprite.set_frame_and_progress(index, 0.0)
			var label := Label.new()
			label.text = "%s %d" % [direction, index]
			label.position = actor.position + Vector2(-18, 18)
			label.add_theme_font_size_override("font_size", 6)
			holder.add_child(label)
	var directory: String = OS.get_environment("TIP_WORK_CLOTHING_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(directory.path_join("worker-work-clothing-poses.png"))
	_expect(error == OK, "The real directional work pose grid was captured.")
	holder.free()
