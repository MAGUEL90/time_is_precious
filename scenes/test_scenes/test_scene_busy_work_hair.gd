extends SceneTree

const WORKER_SCENE_PATH: String = "res://scenes/worker_visual/base_worker_visual.tscn"
const BUSY_HAIR_ROOT: String = "res://assets/characters/shared_assets/hair_assets/busy"
const WORK_HAIR_FRAME_MAPS: Dictionary = {
	"right": [0, 1, 2, 2, 2, 2, 2, 2],
	"left": [3, 3, 3, 3, 3, 3, 4, 5],
}

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = ResourceLoader.load(WORKER_SCENE_PATH) as PackedScene
	_check(packed != null, "worker visual scene loads")
	if packed == null:
		quit(1)
		return
	var actor = packed.instantiate()
	root.add_child(actor)
	await process_frame
	_check(actor.has_method("play_visual"), "worker visual script initializes")

	var body: AnimatedSprite2D = actor.get_node("BodySprite")
	var hair: AnimatedSprite2D = actor.get_node("HairSprite")
	var styles: Array[String] = actor.hair_styles
	for style: String in styles:
		if style == "default":
			actor.play_visual("light", "base", "work", "right", "default", "default", style)
			_check(not hair.visible, "default hairstyle stays hidden in work")
			continue

		var style_parts: PackedStringArray = style.split("_")
		var asset_path: String = "%s/%s/%s/%s.png" % [BUSY_HAIR_ROOT, style_parts[0], style_parts[1], style_parts[2]]
		actor.play_visual("light", "base", "work", "right", "default", "default", style)
		var work_animation: StringName = StringName("%s_work_right" % style)
		_check(hair.visible, "%s work hair remains visible" % style)
		_check(actor.hair_style == style, "%s selected hairstyle is preserved" % style)
		_check(hair.animation == work_animation, "%s work clip selected" % style)
		_check(hair.sprite_frames.get_frame_count(work_animation) == 8, "%s work clip matches eight body poses" % style)
		_check(not hair.flip_h, "%s right-facing work is not mirrored" % style)
		_check(not hair.is_playing(), "%s work hair uses the body as its single clock" % style)
		for frame: int in range(WORK_HAIR_FRAME_MAPS["right"].size()):
			var texture: Texture2D = hair.sprite_frames.get_frame_texture(work_animation, frame)
			var atlas: AtlasTexture = texture as AtlasTexture
			_check(atlas != null, "%s work frame %d uses an atlas" % [style, frame])
			if atlas != null:
				_check(atlas.atlas.resource_path == asset_path, "%s work frame %d uses its selected sheet" % [style, frame])
				_check(atlas.region == Rect2(WORK_HAIR_FRAME_MAPS["right"][frame] * 32, 0, 32, 32), "%s right frame %d uses the right-facing pose" % [style, frame])
				_check(Rect2(Vector2.ZERO, atlas.atlas.get_size()).encloses(atlas.region), "%s right frame %d region stays inside its sheet" % [style, frame])

		actor.play_visual("light", "base", "work", "left", "default", "default", style)
		var left_animation: StringName = StringName("%s_work_left" % style)
		_check(hair.visible and hair.animation == left_animation, "%s left-facing work clip selected" % style)
		_check(not hair.flip_h, "%s left-facing work uses its authored facing poses" % style)
		_check(not hair.is_playing(), "%s left work hair stays on the body clock" % style)
		for frame: int in range(WORK_HAIR_FRAME_MAPS["left"].size()):
			var texture: Texture2D = hair.sprite_frames.get_frame_texture(left_animation, frame)
			var atlas: AtlasTexture = texture as AtlasTexture
			_check(atlas != null, "%s left work frame %d uses an atlas" % [style, frame])
			if atlas != null:
				_check(atlas.atlas.resource_path == asset_path, "%s left work frame %d uses its selected sheet" % [style, frame])
				_check(atlas.region == Rect2(WORK_HAIR_FRAME_MAPS["left"][frame] * 32, 0, 32, 32), "%s left frame %d uses the left-facing pose" % [style, frame])
				_check(Rect2(Vector2.ZERO, atlas.atlas.get_size()).encloses(atlas.region), "%s left frame %d region stays inside its sheet" % [style, frame])

		actor.play_visual("light", "base", "work", "right", "default", "default", style)
		var right_durations: Array[float] = _frame_durations(hair, work_animation)
		actor.play_visual("light", "tired", "work", "right", "default", "default", style)
		var tired_durations: Array[float] = _frame_durations(hair, work_animation)
		if right_durations.size() == 8 and tired_durations.size() == 8:
			_check(is_equal_approx(tired_durations[0], right_durations[0] * actor.tired_first_frame_hold), "%s tired work holds its first hair frame" % style)
			_check(is_equal_approx(tired_durations[7], right_durations[7] * actor.tired_last_frame_hold), "%s tired work holds its last hair frame" % style)
		actor.play_visual("light", "base", "work", "right", "default", "default", style)
		var restored_durations: Array[float] = _frame_durations(hair, work_animation)
		if right_durations.size() == 8 and restored_durations.size() == 8:
			_check(is_equal_approx(restored_durations[0], right_durations[0]), "%s work restores normal first-frame timing" % style)
			_check(is_equal_approx(restored_durations[7], right_durations[7]), "%s work restores normal last-frame timing" % style)

	# A frame change made by a worksite owner must be reflected immediately.
	actor.play_visual("light", "base", "work", "right", "default", "default", "grey_female_01")
	body.pause()
	_check(not hair.is_playing(), "work hair is paused for manual body control")
	body.set_frame_and_progress(5, 0.35)
	_check(hair.frame == body.frame, "work hair follows a manually selected body frame")
	_check(is_equal_approx(hair.frame_progress, body.frame_progress), "work hair follows the body's frame progress")
	body.set_frame_and_progress(1, 0.75)
	_check(hair.frame == body.frame, "work hair follows a second body frame change")
	_check(is_equal_approx(hair.frame_progress, body.frame_progress), "work hair follows a second body progress change")
	await create_timer(0.25).timeout
	_check(hair.frame == body.frame and hair.frame == 1, "paused body holds work hair on its final pose")

	# With normal playback, body frame changes remain the only work-hair clock.
	actor.play_visual("light", "base", "idle", "right", "default", "default", "grey_female_01")
	actor.play_visual("light", "base", "work", "right", "default", "default", "grey_female_01")
	var starting_body_frame: int = body.frame
	await create_timer(0.45).timeout
	_check(body.frame != starting_body_frame, "work body advances during the sync check")
	_check(hair.frame == body.frame, "time-driven work hair remains on the body frame")

	# Busy clips are work-only; established idle and walk clips resume unchanged.
	actor.play_visual("light", "base", "work", "left", "default", "default", "grey_female_01")
	actor.play_visual("light", "base", "idle", "right", "default", "default", "grey_female_01")
	_check(hair.visible and hair.animation == &"grey_female_01_idle_right", "work to idle restores the selected idle hair")
	_check(not hair.flip_h, "idle hair retains its original direction handling")
	_check(hair.sprite_frames.get_frame_count(hair.animation) == 4, "idle hair retains its four-frame clip")
	actor.play_visual("light", "base", "walk", "left", "default", "default", "grey_female_01")
	_check(hair.visible and hair.animation == &"grey_female_01_walk_left", "idle to walk restores the selected walk hair")
	_check(not hair.flip_h, "walk hair retains its original direction handling")
	_check(hair.sprite_frames.get_frame_count(hair.animation) == 4, "walk hair retains its four-frame clip")

	actor.queue_free()
	await process_frame
	print("BUSY_WORK_HAIR_CHECK checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _frame_durations(sprite: AnimatedSprite2D, animation: StringName) -> Array[float]:
	var durations: Array[float] = []
	for index: int in range(sprite.sprite_frames.get_frame_count(animation)):
		durations.append(sprite.sprite_frames.get_frame_duration(animation, index))
	return durations


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", description)
