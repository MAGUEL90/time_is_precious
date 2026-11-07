extends Node2D

const VISUAL := preload("res://scenes/worker_visual/base_worker_visual.tscn")
var failures := 0

func _ready() -> void:
	call_deferred("run_test")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_test() -> void:
	var visual = VISUAL.instantiate()
	add_child(visual)
	var citizen := CitizenData.new()
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	visual.set_satisfaction_source(citizen)
	for tone: String in ["dark", "light", "tan", "warm"]:
		for direction: String in ["left", "right"]:
			for item: Array in [[0.0, "angry"], [0.199, "angry"], [0.19999999999999998, "sad"], [0.20, "sad"], [0.399, "sad"], [0.39999999999999997, "base"], [0.40, "base"], [0.749, "base"], [0.7499999999999999, "happy"], [0.75, "happy"], [0.99, "happy"]]:
				citizen.satisfaction = float(item[0])
				visual.play_visual(tone, "base", "idle", direction, "default", "clay_worn_wrap", "grey_male_01")
				var expected := "%s_%s_idle_%s" % [item[1], tone, direction]
				expect(str(visual.head_sprite.animation) == expected, "Wrong animation: " + expected + " got " + str(visual.head_sprite.animation))
				expect(visual.head_sprite.sprite_frames.get_frame_count(expected) == 4, "Wrong count: " + expected)
				if item[1] != "base":
					var atlas := visual.head_sprite.sprite_frames.get_frame_texture(expected, 0) as AtlasTexture
					expect(atlas != null and atlas.region.position.x == (64.0 if direction == "left" else 0.0), "Wrong atlas direction: " + expected)
			for item: Array in [[0.1, "angry"], [0.3, "sad"], [0.55, "base"], [0.9, "happy"]]:
				citizen.satisfaction = float(item[0])
				visual.play_visual(tone, "base", "walk", direction, "default", "clay_worn_wrap", "grey_male_01")
				var expected := "%s_%s_walk_%s" % [item[1], tone, direction]
				expect(str(visual.head_sprite.animation) == expected, "Wrong walking face: " + expected)
				if item[1] != "base":
					for frame_index: int in range(4):
						visual.body_sprite.set_frame_and_progress(frame_index, 0.0)
						var atlas := visual.head_sprite.sprite_frames.get_frame_texture(expected, frame_index) as AtlasTexture
						expect(atlas != null and atlas.region.position.x == (64.0 if direction == "left" else 0.0)
							and visual.head_sprite.frame == frame_index
							and visual.head_sprite.offset == visual._head_default_offset + Vector2(0, frame_index % 2),
							"Walk face and body must remain synchronized: %s frame %d" % [expected, frame_index])
	citizen.satisfaction = 0.8
	visual.play_visual("light", "base", "idle", "left", "default")
	citizen.satisfaction = 0.1
	visual._process(0.3)
	expect(str(visual.head_sprite.animation) == "angry_light_idle_left", "Live satisfaction change did not refresh while idle")
	visual.play_visual("light", "base", "walk", "right", "default")
	expect(str(visual.head_sprite.animation) == "angry_light_walk_right", "Walk should keep the live angry face")
	visual.play_visual("light", "base", "work", "right", "default")
	expect(str(visual.head_sprite.animation) == "base_light_work_right", "Work should fall back to matching pose")
	visual.play_visual("light", "tired", "work", "right", "default")
	expect(str(visual.head_sprite.animation) == "tired_light_work_right", "Tired work animation must remain intact")
	visual.play_visual("light", "tired", "idle", "right", "default")
	expect(str(visual.head_sprite.animation) == "tired_light_idle_right", "Tired priority should remain visible")
	# Worker legacy records use their own Satisfaction; linked workers resolve
	# through the current CitizenManager object instead of stale worker values.
	var legacy := WorkerData.new()
	legacy.satisfaction = 0.1
	visual.set_satisfaction_source(legacy)
	visual.play_visual("light", "base", "idle", "right", "default")
	expect(str(visual.head_sprite.animation) == "angry_light_idle_right", "Legacy worker satisfaction was ignored")
	var linked := CitizenData.new()
	linked.citizen_id = "linked_face_test"
	linked.population_status = CitizenData.PopulationStatus.RESIDENT
	linked.satisfaction = 0.9
	CitizenManager.add_citizen(linked)
	legacy.worker_id = linked.citizen_id
	visual._process(0.3)
	expect(str(visual.head_sprite.animation) == "happy_light_idle_right", "Linked citizen satisfaction was ignored")
	CitizenManager.citizens_by_id.erase(linked.citizen_id)
	# A detached source has no authority to override a manually authored profile.
	visual.set_satisfaction_source(null)
	expect(str(visual.head_sprite.animation) == "base_light_idle_right", "Detaching source must restore the manual profile immediately")
	# Assignment through CitizenActor is required for nonworker residents.
	var actor := preload("res://scenes/citizen_actor/citizen_actor.tscn").instantiate()
	actor.movement_mode = CitizenActor.MovementMode.STATIC
	add_child(actor)
	citizen.visual_profile = VisualProfile.new()
	citizen.satisfaction = 0.9
	actor.setup(citizen)
	await get_tree().process_frame
	actor.base_worker_visual._process(0.3)
	expect(str(actor.base_worker_visual.head_sprite.animation) == "happy_light_idle_right", "CitizenActor did not bind source")
	actor._update_visual_direction(Vector2.LEFT)
	actor._play_visual("walk")
	expect(str(actor.base_worker_visual.head_sprite.animation) == "happy_light_walk_left", "CitizenActor must keep mood walking left")
	expect(not actor._update_visual_direction(Vector2.UP) and not actor._update_visual_direction(Vector2.DOWN)
		and str(actor.base_worker_visual.head_sprite.animation) == "happy_light_walk_left", "Vertical travel retains the last available facing and mood")
	actor._update_visual_direction(Vector2.RIGHT)
	actor._play_visual("walk")
	expect(str(actor.base_worker_visual.head_sprite.animation) == "happy_light_walk_right", "CitizenActor must keep mood walking right")
	# Main map's shared visual owner binds both employed and unemployed residents.
	var owner := preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_worker_visuals.gd").new()
	add_child(owner)
	owner.set_process(false)
	var spawn := Node2D.new()
	add_child(spawn)
	owner.resident_spawn = spawn
	var owner_person := CitizenData.new()
	owner_person.citizen_id = "face_visual_test"
	owner_person.population_status = CitizenData.PopulationStatus.RESIDENT
	owner_person.visual_profile = VisualProfile.new()
	owner_person.satisfaction = 0.8
	CitizenManager.add_citizen(owner_person)
	var shared = owner.ensure_actor(owner_person.citizen_id, Vector2.ZERO)
	_expect_source(shared, owner_person)
	owner._play(shared, "idle", "right")
	expect(str(shared.head_sprite.animation) == "happy_light_idle_right", "Shared visual owner did not bind resident source")
	owner_person.satisfaction = 0.1
	shared._process(0.3)
	expect(str(shared.head_sprite.animation) == "angry_light_idle_right", "Shared visual did not observe updated satisfaction")
	owner._play(shared, "walk", "left")
	expect(str(shared.head_sprite.animation) == "angry_light_walk_left", "The worksite owner must retain the worker's walking mood")
	owner_person.satisfaction = 0.3
	shared._process(0.3)
	expect(str(shared.head_sprite.animation) == "sad_light_walk_left", "The worksite owner must update mood while walking")
	owner._play(shared, "idle", "right")
	# Exercise real raid subtraction near an exact threshold rather than direct assignment.
	owner_person.satisfaction = 0.6
	var raid = preload("res://scenes/raid/raid_state.gd").new()
	raid.config = preload("res://scenes/raid/raid_config.gd").new()
	raid.config.satisfaction_penalty = 0.05
	raid.config.max_fleeing_residents = 0
	for _index: int in range(4):
		raid._apply_population_losses()
	shared._process(0.3)
	expect(str(shared.head_sprite.animation) == "base_light_idle_right", "Four 5% raid losses from 60% should land on the 40% boundary")
	owner_person.satisfaction = 0.3999
	shared._process(0.3)
	expect(str(shared.head_sprite.animation) == "sad_light_idle_right", "A genuine 39.99% remains below the 40% boundary")
	raid.free()
	CitizenManager.citizens_by_id.erase(owner_person.citizen_id)
	await _test_independent_citizens()
	print("SatisfactionFaceTest ", "PASSED" if failures == 0 else "FAILED %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_independent_citizens() -> void:
	var first := CitizenData.new()
	var second := CitizenData.new()
	first.satisfaction = 0.9
	second.satisfaction = 0.1
	var first_visual = VISUAL.instantiate()
	var second_visual = VISUAL.instantiate()
	add_child(first_visual)
	add_child(second_visual)
	first_visual.set_satisfaction_source(first)
	second_visual.set_satisfaction_source(second)
	first_visual.play_visual("dark", "base", "idle", "left", "default", "clay_worn_wrap", "black_male_01")
	second_visual.play_visual("warm", "base", "idle", "right", "default", "plain_linen_wrap", "red_female_01")
	expect(first_visual.head_sprite.animation == &"happy_dark_idle_left"
		and second_visual.head_sprite.animation == &"angry_warm_idle_right",
		"Two simultaneous citizens display their own different satisfaction expressions")
	expect(first_visual.head_sprite.sprite_frames != second_visual.head_sprite.sprite_frames,
		"Each citizen owns independent mutable head animation frames")
	second.satisfaction = 0.8
	await get_tree().create_timer(0.4).timeout
	expect(second_visual.head_sprite.animation == &"happy_warm_idle_right"
		and first_visual.head_sprite.animation == &"happy_dark_idle_left",
		"The live timer updates only the citizen whose satisfaction changed")
	second.satisfaction = 0.1
	await get_tree().create_timer(0.4).timeout
	expect(second_visual.head_sprite.animation == &"angry_warm_idle_right",
		"The same citizen returns to angry through normal timed refresh")
	for sample: Array in [[0.199, "angry"], [0.20, "sad"], [0.399, "sad"], [0.40, "base"], [0.749, "base"], [0.75, "happy"]]:
		first.satisfaction = float(sample[0])
		first_visual._process(0.3)
		second_visual._process(0.3)
		expect(str(first_visual.head_sprite.animation) == "%s_dark_idle_left" % sample[1]
			and second_visual.head_sprite.animation == &"angry_warm_idle_right"
			and second.satisfaction == 0.1,
			"Changing one citizen across a mood boundary does not change the other: " + str(sample[0]))
	first.satisfaction = 0.9
	first_visual.play_visual("dark", "base", "walk", "left", "default", "clay_worn_wrap", "black_male_01")
	second_visual.play_visual("warm", "base", "walk", "right", "default", "plain_linen_wrap", "red_female_01")
	expect(first_visual.head_sprite.animation == &"happy_dark_walk_left" and second_visual.head_sprite.animation == &"angry_warm_walk_right",
		"Two people can walk simultaneously with different moods and facing")
	second.satisfaction = 0.3
	await get_tree().create_timer(0.4).timeout
	expect(first_visual.head_sprite.animation == &"happy_dark_walk_left" and second_visual.head_sprite.animation == &"sad_warm_walk_right",
		"A live walking mood change updates only the corresponding person")
	second.satisfaction = 0.1
	second_visual._process(0.3)
	second_visual.play_visual("warm", "base", "idle", "right", "default", "plain_linen_wrap", "red_female_01")
	first.satisfaction = 0.1
	for action: String in ["walk", "work"]:
		first_visual.play_visual("dark", "base", action, "left", "default", "clay_worn_wrap", "black_male_01")
		first_visual._process(0.3)
		var expected_mood := "angry" if action == "walk" else "base"
		expect(str(first_visual.head_sprite.animation) == "%s_dark_%s_left" % [expected_mood, action]
			and second_visual.head_sprite.animation == &"angry_warm_idle_right",
			"Action %s uses the right face without changing another citizen" % action)
	first_visual.play_visual("dark", "base", "idle", "left", "default", "clay_worn_wrap", "black_male_01")
	expect(first_visual.head_sprite.animation == &"angry_dark_idle_left"
		and second_visual.head_sprite.animation == &"angry_warm_idle_right"
		and first_visual.skin_tone == "dark" and first_visual.hair_style == "black_male_01"
		and first_visual.clothes_id == "clay_worn_wrap"
		and second_visual.skin_tone == "warm" and second_visual.hair_style == "red_female_01"
		and second_visual.clothes_id == "plain_linen_wrap",
		"Returning to idle refreshes the selected citizen without changing either appearance")
	first_visual.free()
	second_visual.free()


func _expect_source(visual: Node2D, citizen: CitizenData) -> void:
	expect(visual != null and visual._satisfaction_source == citizen, "Visual source was not the resident")
