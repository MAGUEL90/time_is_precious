extends Node

const CONTENT = preload("res://scenes/content_scene/content_scene.tscn")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.seconds_per_minute = 100000.0
	for id in ["plot_test_a", "plot_test_b"]:
		var worker := WorkerData.new()
		worker.worker_id = id
		WorkerDatabase.workers_by_id[id] = worker
	var content = CONTENT.instantiate()
	add_child(content)
	var a = content.get_node("YSortWorld/WorkshopPlot").construction
	var b = content.get_node("YSortWorld/WorkshopPlot2").construction
	_expect(a != b and a.order_id != b.order_id, "Each plot owns its state and worker order.")
	_expect(a.start_clearing(["plot_test_a"] as Array[String], false).success, "First plot starts cleaning.")
	TimeComponentManager.advance_minutes(90)
	_expect(b.phase == "uncleared" and b.clearing_remaining == 180, "Untouched plot must not progress with the first plot.")
	_expect(not b.start_clearing(["plot_test_a"] as Array[String], false).success, "A worker cannot clean two plots at once.")
	_expect(b.start_clearing(["plot_test_b"] as Array[String], false).success, "Second plot starts independently with another worker.")
	content.free()
	content = CONTENT.instantiate()
	add_child(content)
	_expect(content.get_node("YSortWorld/WorkshopPlot").construction == a and content.get_node("YSortWorld/WorkshopPlot2").construction == b, "Reload preserves both plot identities.")
	TimeComponentManager.advance_minutes(90)
	_expect(a.phase == "empty" and b.phase == "clearing", "Staggered cleaning completes independently.")
	_expect(not WorkerDatabase.get_worker_data("plot_test_a").is_reserved() and WorkerDatabase.get_worker_data("plot_test_b").is_reserved(), "Finishing A must not release B's worker.")
	Inventory.items.clear()
	for id in a.get_requirements():
		Inventory.add_item(id, a.get_requirements()[id])
	_expect(a.start_build(["plot_test_a"] as Array[String]).success, "Cleared plot can build while the second plot cleans.")
	TimeComponentManager.advance_minutes(90)
	_expect(a.phase == "building" and b.phase == "empty", "Second cleaning completion does not alter first construction.")
	TimeComponentManager.advance_minutes(a.SOLO_MINUTES - 90)
	_expect(a.phase == "built" and b.phase == "empty", "Building only completes the selected plot.")
	_expect(content.get_node("YSortWorld/WorkshopPlot").has_node("BuiltWorkshop") and not content.get_node("YSortWorld/WorkshopPlot2").has_node("BuiltWorkshop"), "Only the built plot gains production access.")
	content.free()
	a.free()
	b.free()
	print("WorkshopPlotIndependenceTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
