extends "res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd"

## Content adapter for the tested worksite loop. Uses the map's existing Player/HUD.
## Session-local playtest data; never opens or overwrites the prototype save slot.
@export_category("Content playtest")
@export var seed_playtest_equipment: bool = true
@export var seed_playtest_hauler: bool = true
@export var enable_time_shortcuts: bool = true

const PLAYTEST_HAULER_ID: String = "content_hauler_belum"

func _ready() -> void:
	if player == null or inventory_ui == null:
		set_process(false)
		set_process_unhandled_input(false)
		if get_parent() == get_tree().root:
			# F6 on this reusable component previews it in its real map context.
			_open_content_preview.call_deferred()
		else:
			push_error("Worksites: set player_path and inventory_ui_path to the map's Player and InventoryUI.")
		return
	super._ready()
	# Notes belong to the isolated fixture, not the content HUD.
	$FixtureNotes.hide()
	$WorkerVisuals.y_sort_enabled = true
	worker_control.can_open = _can_open_worker_hub
	if seed_playtest_equipment:
		city_tools.add_tool_unit("content_cart", "cart", "Cart")
		city_tools.add_tool_unit("content_glove", "basic_glove", "Basic Glove")
		city_tools.add_tool_unit("content_hammer", "stone_hammer", "Raw Hammer")
	if seed_playtest_hauler and not WorkerDatabase.has_worker_data(PLAYTEST_HAULER_ID) and not WorkerDatabase.dismissed_workers.has(PLAYTEST_HAULER_ID):
		# Same legacy WorkerData fixture contract as the existing Naram/Enki roster.
		# This does not alter the city's citizen generation or hiring rules.
		var worker := WorkerData.new()
		worker.worker_id = PLAYTEST_HAULER_ID
		worker.display_name = "Belum"
		worker.profession = WorkerData.Profession.HAULER
		WorkerDatabase.workers_by_id[worker.worker_id] = worker

func _open_content_preview() -> void:
	var result: Error = get_tree().change_scene_to_file("res://scenes/content_scene/content_scene.tscn")
	if result != OK:
		push_error("Worksites: content preview could not load (error %d)." % result)

func _can_open_worker_hub() -> bool:
	return player.can_move and not player.is_sleeping and not player.is_collapsing and not _working and not inspector.visible and not inventory_ui.visible and not get_tree().paused and not SceneTransition.is_transitioning

func _unhandled_input(event: InputEvent) -> void:
	# Existing map interactables (workshop, pickups, etc.) retain ownership of E.
	if event.is_action_pressed("interact") and is_instance_valid(player.current_interactable):
		return
	if OS.is_debug_build() and enable_time_shortcuts and event is InputEventKey and event.pressed and not event.echo and _can_open_worker_hub():
		if event.keycode == KEY_F7:
			TimeComponentManager.advance_minutes(30)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F:
			var minute_of_day: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
			TimeComponentManager.advance_minutes(1440 - minute_of_day + 6 * 60 + 45)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _draw() -> void:
	# Site footprints are authored nodes; the prototype grid is not part of the map.
	pass
