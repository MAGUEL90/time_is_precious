extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const CITIZEN_ACTOR: PackedScene = preload("res://scenes/citizen_actor/citizen_actor.tscn")
const WORKER_ID: String = "fire_visual_lifecycle_worker"
const OTHER_WORKER_ID: String = "fire_visual_lifecycle_worker_shadow"

var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var original_inventory: Dictionary = Inventory.items.duplicate(true)
	var original_rates: Dictionary = WorkerDatabase.onboarding_period_rates.duplicate(true)
	var original_hour: int = TimeComponentManager.current_hour
	var original_minute: int = TimeComponentManager.current_minute
	var original_paused: bool = TimeComponentManager.is_paused
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 1

	var content: Node = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	await get_tree().process_frame
	var runtime: Node = content.get_node("YSortWorld/WorkerRuntime")
	var visuals: Node = runtime.get_node("WorkerVisuals")
	var worker_callback: Callable = Callable(visuals, "_on_worker_roster_changed")

	var citizen := CitizenData.new()
	citizen.citizen_id = WORKER_ID
	citizen.display_name = "Lifecycle Test Worker"
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.APPLICANT
	citizen.profession = WorkerData.Profession.LABORER
	citizen.satisfaction = CitizenData.MIN_APPLICANT_SATISFACTION
	CitizenManager.add_citizen(citizen)
	var price: int = WorkerDatabase.get_contract_price(citizen.profession, 3)
	Inventory.add_item("shekel", price * 2)
	var worker: WorkerData = WorkerDatabase.hire_applicant(WORKER_ID, 1, 3)
	_expect(worker != null and WorkerDatabase.has_worker_data(WORKER_ID), "The fixture hires its citizen through WorkerDatabase.")
	if worker == null:
		await _finish(content, visuals, worker_callback, original_inventory, original_rates, original_hour, original_minute, original_paused)
		return

	var other_worker := WorkerData.new()
	other_worker.worker_id = OTHER_WORKER_ID
	other_worker.display_name = "Similar-ID Worker"
	other_worker.profession = WorkerData.Profession.LABORER
	WorkerDatabase.workers_by_id[OTHER_WORKER_ID] = other_worker
	var actor: Node2D = visuals.ensure_actor(WORKER_ID, Vector2.ZERO)
	var other_actor: Node2D = visuals.ensure_actor(OTHER_WORKER_ID, Vector2(20, 0))
	_expect(actor != null and actor.get_meta("worker_id", "") == WORKER_ID, "The hired worker gets a tagged worker visual.")
	_expect(other_actor != null and other_actor.get_meta("worker_id", "") == OTHER_WORKER_ID, "A similar-ID hired worker gets its own visual.")
	if actor == null or other_actor == null:
		await _finish(content, visuals, worker_callback, original_inventory, original_rates, original_hour, original_minute, original_paused)
		return
	actor.show()
	other_actor.show()
	var actor_instance_id: int = actor.get_instance_id()

	var citizen_actor: CitizenActor = CITIZEN_ACTOR.instantiate() as CitizenActor
	content.add_child(citizen_actor)
	citizen_actor.setup(citizen)
	citizen_actor.global_position = Vector2(40, 0)
	citizen_actor.show()
	_expect(citizen_actor.citizen_data == citizen and citizen_actor.is_visible_in_tree(),
		"A same-ID CitizenActor is present beside the worker visual.")

	visuals.work_cycles[WORKER_ID] = {"fixture": true}
	visuals.roaming[WORKER_ID] = {"fixture": true}
	visuals.site_paths[WORKER_ID] = {"fixture": true}
	visuals.reed_inside[WORKER_ID] = true
	visuals.plot_presence.states[WORKER_ID] = {"fixture": true}
	visuals.plot_presence.tracked[WORKER_ID] = true
	get_tree().paused = true
	_expect(WorkerDatabase.dismiss_worker(WORKER_ID), "Fire succeeds while the game tree is paused.")
	var presentation_clean: bool = not visuals.work_cycles.has(WORKER_ID) and not visuals.roaming.has(WORKER_ID) \
		and not visuals.site_paths.has(WORKER_ID) and not visuals.reed_inside.has(WORKER_ID) \
		and not visuals.plot_presence.states.has(WORKER_ID) and not visuals.plot_presence.tracked.has(WORKER_ID)
	_expect(not visuals.actors.has(WORKER_ID) and not actor.is_visible_in_tree() and presentation_clean,
		"Fire removes only the dismissed worker visual and all of its presentation state while paused.")
	_expect(visuals.actors.get(OTHER_WORKER_ID) == other_actor and WorkerDatabase.has_worker_data(OTHER_WORKER_ID)
		and other_actor.is_visible_in_tree(), "Fire keeps a visible hired worker with a similar ID.")
	_expect(is_instance_valid(citizen_actor) and citizen_actor.is_inside_tree() and citizen_actor.is_visible_in_tree(),
		"Fire keeps the same-ID CitizenActor in the tree and visible.")

	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not is_instance_valid(actor), "The fired worker node is freed after the paused frame resumes.")
	_expect(CitizenManager.register_applicant(WORKER_ID, WorkerData.Profession.LABORER), "The dismissed citizen can reapply for the rehire check.")
	var rehired: WorkerData = WorkerDatabase.hire_applicant(WORKER_ID, 1, 3)
	_expect(rehired != null and WorkerDatabase.has_worker_data(WORKER_ID), "The dismissed worker can be rehired.")
	if rehired != null:
		var rehired_actor: Node2D = visuals.ensure_actor(WORKER_ID, Vector2.ZERO)
		_expect(rehired_actor != null and is_instance_valid(rehired_actor)
			and rehired_actor.get_instance_id() != actor_instance_id
			and rehired_actor.get_meta("worker_id", "") == WORKER_ID,
			"Rehire creates a fresh WorkerVisuals actor for the same worker ID.")
		if rehired_actor != null:
			rehired_actor.show()
			_expect(rehired_actor.is_visible_in_tree(), "The rehired worker visual can be shown again.")

	get_tree().paused = false
	await _finish(content, visuals, worker_callback, original_inventory, original_rates, original_hour, original_minute, original_paused)

func _finish(
	content: Node,
	visuals: Node,
	worker_callback: Callable,
	original_inventory: Dictionary,
	original_rates: Dictionary,
	original_hour: int,
	original_minute: int,
	original_paused: bool
) -> void:
	get_tree().paused = false
	TimeComponentManager.is_paused = false
	WorkerDatabase.workers_by_id.erase(WORKER_ID)
	WorkerDatabase.workers_by_id.erase(OTHER_WORKER_ID)
	WorkerDatabase.dismissed_workers.erase(WORKER_ID)
	WorkerDatabase.dismissed_workers.erase(OTHER_WORKER_ID)
	CitizenManager.citizens_by_id.erase(WORKER_ID)
	WorkerDatabase.onboarding_period_rates = original_rates
	Inventory.items = original_inventory
	Inventory.items_changed.emit()
	if is_instance_valid(visuals):
		visuals.queue_free()
	if is_instance_valid(content):
		content.queue_free()
	await get_tree().process_frame
	_expect(not WorkerDatabase.payroll_changed.is_connected(worker_callback),
		"WorkerVisuals disconnects its roster signal when it exits the scene tree.")
	TimeComponentManager.current_hour = original_hour
	TimeComponentManager.current_minute = original_minute
	TimeComponentManager.is_paused = original_paused
	if failures == 0:
		print("WorkerVisualLifecycleTest PASSED")
	else:
		print("WorkerVisualLifecycleTest FAILED: %d" % failures)
	get_tree().current_scene = self
	get_tree().quit(0 if failures == 0 else 1)
