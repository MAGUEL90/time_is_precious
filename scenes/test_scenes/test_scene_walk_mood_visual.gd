extends Node2D

const VISUAL := preload("res://scenes/worker_visual/base_worker_visual.tscn")
var retained_sources: Array[CitizenData] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color("354443")
	bg.size = Vector2(400, 225)
	add_child(bg)
	_add_label("Walk expression: frames 0 and 1", Vector2(90, 8), 220)
	for col: int in range(3):
		var item: Array = [["ANGRY", 0.1], ["SAD", 0.3], ["HAPPY", 0.9]][col]
		_add_label(item[0], Vector2(40 + col * 110, 30), 70)
		for row: int in range(2):
			var direction := "right" if row == 0 else "left"
			for frame_index: int in range(2):
				var actor = VISUAL.instantiate()
				actor.position = Vector2(54 + col * 110 + frame_index * 38, 80 + row * 70)
				actor.scale = Vector2(2, 2)
				add_child(actor)
				var citizen := CitizenData.new()
				citizen.satisfaction = float(item[1])
				retained_sources.append(citizen)
				actor.set_satisfaction_source(citizen)
				actor.play_visual("light", "base", "walk", direction, "default", "clay_worn_wrap", "grey_male_01")
				actor.body_sprite.pause()
				actor.body_sprite.set_frame_and_progress(frame_index, 0.0)
				actor._sync_walk_mood_frame()
	_add_label("RIGHT", Vector2(4, 65), 42)
	_add_label("LEFT", Vector2(4, 135), 42)
	await get_tree().process_frame
	await get_tree().process_frame
	var directory := OS.get_environment("TIP_MOOD_CAPTURE_DIR")
	if not directory.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(directory)
		await RenderingServer.frame_post_draw
		var result := get_viewport().get_texture().get_image().save_png(directory.path_join("walk-moods.png"))
		if result != OK:
			push_error("Could not save walk mood evidence: %s" % result)
			get_tree().quit(1)
			return
	print("WalkMoodVisualTest PASSED")
	get_tree().quit(0)

func _add_label(value: String, pos: Vector2, width: float) -> void:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.size = Vector2(width, 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	add_child(label)
