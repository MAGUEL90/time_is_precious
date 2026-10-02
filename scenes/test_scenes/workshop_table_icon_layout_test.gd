extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.environment.color = Color.WHITE
	var content: Node = CONTENT.instantiate()
	var plot: Node = content.get_node("YSortWorld/WorkshopPlot")
	var slots: Node2D = plot.get_node("TableResources")
	# Configure only this test-owned instance, like dragging the authored slots.
	for child: Node in slots.get_children():
		child.free()
	for point in [Vector2(-9, -14), Vector2(6, -10)]:
		var icon := Sprite2D.new()
		icon.position = point
		icon.scale = Vector2(0.75, 0.75)
		icon.texture = ItemDatabase.get_item_data("clay_lump").icon
		slots.add_child(icon)
	slots.position += Vector2(3, 0)
	add_child(content)
	content.get_node("TimeDebugOverlay").set_process(false)
	_expect(not slots.visible, "Preview icons stay hidden on an uncleared plot.")
	var transforms: Array[Transform2D] = []
	for icon: Sprite2D in slots.get_children():
		transforms.append(icon.global_transform)
	var worker := WorkerData.new()
	worker.worker_id = "table_icon_layout_builder"
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	_expect(plot.construction.start_clearing([worker.worker_id] as Array[String], false).success, "Clearing starts normally.")
	TimeComponentManager.advance_minutes(180)
	_expect(not slots.visible, "Empty plot still hides the table material previews.")
	Inventory.add_bulk_item(plot.construction.get_requirements())
	_expect(plot.construction.start_build([worker.worker_id] as Array[String]).success, "Normal construction starts.")
	TimeComponentManager.advance_minutes(plot.construction.SOLO_MINUTES)
	var workshop: WorkShop = plot.get_node("BuiltWorkshop")
	_expect(slots.visible and slots.get_child_count() == 2, "Completion displays the two authored slots.")
	for index in range(2):
		_expect(slots.get_child(index).global_transform == transforms[index], "Construction preserves the authored position and scale.")
	var job := JobData.new()
	job.inputs = {"wood_log": 1}
	workshop.available_jobs.assign([job])
	plot._show_table_resource(workshop)
	for index in range(2):
		_expect(slots.get_child(index).texture == ItemDatabase.get_item_data("wood_log").icon and slots.get_child(index).global_transform == transforms[index],
			"A different recipe replaces textures while preserving the same layout.")
	plot._show_table_resource(workshop)
	_expect(slots.get_child_count() == 2, "Refreshing the recipe never duplicates icons.")
	job.inputs.clear()
	plot._show_table_resource(workshop)
	_expect(not slots.visible, "A recipe without inputs hides its material icons.")
	content.free()
	print("WorkshopTableIconLayoutTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
