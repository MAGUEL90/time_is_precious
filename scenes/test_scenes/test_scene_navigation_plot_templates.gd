extends Node

## Compare the retained phase templates against the real city colliders.
## The forced construction phases are geometry fixtures, not gameplay.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const HOME_PATH: String = "res://scenes/player_home_interior/player_home_interior.tscn"
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _same_polygons(a: Array[PackedVector2Array], b: Array[PackedVector2Array]) -> bool:
	var remaining: Array[PackedVector2Array] = b.duplicate()
	for polygon: PackedVector2Array in a:
		var index: int = remaining.find(polygon)
		if index < 0:
			return false
		remaining.remove_at(index)
	return remaining.is_empty()

func _run() -> void:
	TimeComponentManager.set_process(false)
	var city: Node = CONTENT.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	for frame: int in range(6):
		await get_tree().process_frame
	var runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	var house_shape: CollisionShape2D = city.get_node("YSortWorld/CitizenHousePlot/HouseBody/CollisionShape2D")
	var original_shape: Shape2D = house_shape.shape
	house_shape.shape = null
	_expect(runtime._plot_navigation_template(city.get_node("YSortWorld/CitizenHousePlot")).is_empty(),
		"A missing house collider fails closed instead of inventing empty geometry")
	house_shape.shape = original_shape
	# Exercise the full inherited world transform, not translation alone.
	var transforms: Dictionary = {
		"CitizenHousePlot": {"rotation": 0.31, "scale": Vector2(1.5, 0.75)},
		"WorkshopPlot": {"rotation": -0.20, "scale": Vector2(0.8, 1.2)},
		"WorkshopPlot2": {"rotation": 0.41, "scale": Vector2(1.1, 0.9)},
	}
	for name: String in transforms:
		var plot: Node2D = city.get_node("YSortWorld/" + name)
		plot.rotation = transforms[name].rotation
		plot.scale = transforms[name].scale
	runtime._refresh_navigation()
	var house_state: Node = city.get_node("YSortWorld/CitizenHousePlot").construction
	var original_phase: String = house_state.phase
	var original_revision: int = runtime.worksite_navigation.revision
	house_state.phase = "clearing"
	house_state.changed.emit()
	house_state.phase = original_phase
	house_state.changed.emit()
	_expect(not runtime.navigation_refresh_pending and runtime.worksite_navigation.revision == original_revision,
		"A phase transition with unchanged collision does not freeze the city")
	house_state.phase = "built"
	house_state.changed.emit()
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_expect(runtime.navigation_refresh_pending and not store.prepare_home_departure(city, HOME_PATH)
		and not is_instance_valid(store.parked_worksite),
		"Home handoff waits for a pending deferred collision refresh")
	house_state.phase = original_phase
	house_state.changed.emit()
	for frame: int in range(8):
		await get_tree().process_frame
	_expect(not runtime.navigation_refresh_pending, "The city finishes the queued collision refresh")
	for name: String in ["CitizenHousePlot", "WorkshopPlot", "WorkshopPlot2"]:
		var plot: Node = city.get_node("YSortWorld/" + name)
		var state: Node = plot.construction
		var template: Dictionary = runtime.navigation_plot_templates.get(state.get_instance_id(), {})
		_expect(not template.is_empty(), "The authored plot has a captured phase template: " + name)
		if template.is_empty():
			continue
		var expected: Array[PackedVector2Array] = runtime.worksite_navigation.polygons.duplicate()
		for polygon: PackedVector2Array in template.open:
			var index: int = expected.find(polygon)
			_expect(index >= 0, "The currently active open collider was captured: " + name)
			if index >= 0:
				expected.remove_at(index)
		expected.append_array(template.built)
		state.phase = "built"
		state.changed.emit()
		for frame: int in range(8):
			await get_tree().process_frame
		_expect(runtime.can_simulate_plot_travel(), "The city navigation refreshes after construction: " + name)
		if not _same_polygons(expected, runtime.worksite_navigation.polygons):
			var extra: Array[PackedVector2Array] = runtime.worksite_navigation.polygons.duplicate()
			for polygon: PackedVector2Array in expected:
				var index: int = extra.find(polygon)
				if index < 0:
					print("TEMPLATE_MISSING ", name, " ", polygon)
				else:
					extra.remove_at(index)
			for polygon: PackedVector2Array in extra:
				print("TEMPLATE_EXTRA ", name, " ", polygon)
		_expect(_same_polygons(expected, runtime.worksite_navigation.polygons),
			"The captured built template exactly matches all real city collision polygons: " + name)
	print("NavigationPlotTemplatesTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
