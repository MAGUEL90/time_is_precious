extends Node

const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const TEST_REQUIREMENTS: Dictionary = {"wood_log": 6, "clay_lump": 12, "reed_bundle": 8}
const TEST_WORKER_IDS: Array[String] = [
	"construction_playtest_one",
	"construction_playtest_two",
	"construction_playtest_three",
]

var _content: Node
var _construction_state: Variant
var _status_label: Label

func _ready() -> void:
	call_deferred("_setup_playtest")

func _setup_playtest() -> void:
	if WorkStateRuntime.get_node_or_null("MainWorkshopConstruction") != null:
		_create_fixture_label()
		_status_label.text = "F6 PLAYTEST NEEDS A FRESH SESSION\nNo fixture data was added."
		return
	_seed_fixture_team()
	Inventory.items.clear()
	Inventory.add_bulk_item(TEST_REQUIREMENTS)
	_content = CONTENT_SCENE.instantiate()
	add_child(_content)
	await get_tree().process_frame
	var plot = _content.get_node("YSortWorld/WorkshopPlot")
	_construction_state = WorkStateRuntime.get_node_or_null("MainWorkshopConstruction")
	var player: Player = _content.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_create_fixture_label()
	_update_fixture_label()
	if _construction_state != null:
		_construction_state.changed.connect(_update_fixture_label)
	if _construction_state == null:
		_status_label.text += "\nERROR: map did not create construction state."

func _seed_fixture_team() -> void:
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	for worker_id: String in TEST_WORKER_IDS:
		var citizen := CitizenData.new()
		citizen.citizen_id = worker_id
		citizen.display_name = "TEST " + worker_id.get_slice("_", 2).capitalize()
		citizen.population_status = CitizenData.PopulationStatus.RESIDENT
		citizen.employment_status = CitizenData.EmploymentStatus.HIRED
		citizen.profession = WorkerData.Profession.LABORER
		CitizenManager.citizens_by_id[worker_id] = citizen

		var worker := WorkerData.new()
		worker.worker_id = worker_id
		worker.display_name = citizen.display_name
		worker.profession = WorkerData.Profession.LABORER
		WorkerDatabase.workers_by_id[worker_id] = worker

func _create_fixture_label() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 8
	overlay.name = "ConstructionPlaytestFixtureOverlay"
	add_child(overlay)
	_status_label = Label.new()
	_status_label.position = Vector2(8, 199)
	_status_label.custom_minimum_size = Vector2(384, 22)
	_status_label.theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
	_status_label.theme_type_variation = &"HudLabelShortcut"
	_status_label.add_theme_font_size_override("font_size", 6)
	overlay.add_child(_status_label)

func _update_fixture_label() -> void:
	if not is_instance_valid(_status_label):
		return
	var phase: String = "Waiting for map"
	var remaining_text: String = ""
	if is_instance_valid(_construction_state):
		phase = str(_construction_state.phase).capitalize()
		if phase == "Building":
			var preview: Dictionary = _construction_state.get_preview([] as Array[String])
			remaining_text = " | %d min left" % int(preview.remaining_minutes)
	_status_label.text = "TEST ONLY: materials + 3 builders\nE: build | F8: +12h | " + phase + remaining_text

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		if is_instance_valid(_construction_state):
			TimeComponentManager.advance_minutes(12 * 60)
			_update_fixture_label()
			get_viewport().set_input_as_handled()
