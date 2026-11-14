extends "res://scenes/test_scenes/test_scene_city_transport_flow.gd"

const LEGACY_ADAPTER = preload("res://scenes/new_scenes/save_game/city_save_worksites.gd")

func _write_flow() -> void:
	var data_root := OS.get_environment("XDG_DATA_HOME").simplify_path()
	_expect(data_root.contains("citysave_suite_qa") and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root + "/"), "Use isolated QA storage.")
	if stopped:
		return
	worker_id = "initial_city_storage_hauler"
	Inventory.add_item("shekel", 10)
	var courier: WorkerData = WorkerDatabase.hire_applicant(worker_id, 1, 3)
	_expect(courier != null and central.allocate("initial_worksite_cart", worker_id), "Hire existing Hauler and allocate authored cart.")
	_expect(not runtime.daily.allow_haulers, "New worksite hauling stays disabled.")
	if stopped:
		return
	var marker: Node2D = runtime.get_node("WorksiteMarkers/WoodSite")
	var original := marker.position
	var job: Dictionary = {"ids": [worker_id], "order": "legacy_respawn_test", "units": 0, "progress": {worker_id: 0.0}, "starts": {worker_id: now()}, "stats": {worker_id: {"days": [], "output": 0}}, "drop": runtime._deliver_daily_output.bind(marker)}
	runtime.daily.jobs[&"WoodSite"] = job
	courier.start_work(job.order, "clay_daily")
	runtime.hauling.begin(worker_id, &"WoodSite", now(), {"destination_path": NodePath("WoodStorage"), "destination_name": "Ground", "daily_target": 3})
	var shipment: Dictionary = runtime.hauling.routes[worker_id]
	var destination: Vector2 = runtime.to_global(runtime.LEGACY_STOCKPILES.STOCKPILES["WoodStorage"].position)
	shipment.legacy_final = true
	shipment.removing = true
	shipment.phase = "outbound"
	shipment.cargo.quantity = 3
	shipment.target = destination
	shipment.arrival = now() + runtime.hauling._travel_minutes(shipment.origin.distance_to(destination))
	shipment.destination = LEGACY_ADAPTER.LegacyFinalDestination.new(runtime, destination)
	runtime.daily._sync_activities()
	_expect(store.snapshot.prepare(store.snapshot.capture(content), content), "Supported final shipment validates without enabling new assignments: " + store.snapshot.error)
	if stopped:
		return
	var session = runtime.sites.WoodSite
	session.stock = 0
	session.respawn_started_at = now()
	session.respawn_due_at = now() + 1000
	runtime._set_site_depleted_presentation("WoodSite", true)
	await _frames(4)
	var base: CollisionPolygon2D = marker.get_node("ResourceBase/CollisionPolygon2D")
	var polygon: PackedVector2Array = runtime._resource_occupancy_polygon(marker, base)
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		center += point
	center /= polygon.size()
	var direction: Vector2 = (destination - Vector2(shipment.origin)).normalized()
	marker.global_position += Vector2(shipment.origin) + Vector2(0, 16) + direction * 30.0 - center
	runtime._refresh_navigation()
	session.respawn_due_at = now()
	runtime._queue_depleted_sites()
	await _frames(8)
	_expect(session.stock == 0 and base.disabled, "Upcoming legacy delivery corridor must remain clear of new respawn.")
	if stopped:
		return
	# Another source is independent of the reserved legacy corridor.
	var clay = runtime.sites.ClaySiteA
	clay.stock = 0
	clay.respawn_started_at = now()
	clay.respawn_due_at = now()
	runtime._set_site_depleted_presentation("ClaySiteA", true)
	await _frames(4)
	runtime._queue_depleted_sites()
	await _frames(8)
	_expect(clay.stock == clay.deposit_capacity, "Legacy corridor does not hold unrelated source refill.")
	var saw_empty_return := false
	for minute in range(80):
		if not runtime.hauling.routes.has(worker_id):
			break
		shipment = runtime.hauling.routes[worker_id]
		if shipment.phase == "returning" and int(shipment.cargo.quantity) == 0:
			saw_empty_return = true
			_expect(session.stock == 0 and base.disabled, "Empty legacy cart return also keeps its path clear.")
		_expect(TimeComponentManager.advance_minutes(1), "Advance original legacy route.")
		await _frames(4)
		_expect(_legacy_total() == 3, "Cargo and final ground receipt conserve three logs.")
		if stopped:
			return
	_expect(saw_empty_return and not runtime.hauling.routes.has(worker_id) and not courier.is_reserved(), "Final receipt and empty return release the existing assignment.")
	_expect(TimeComponentManager.advance_minutes(1), "Retry source after final route release.")
	await _frames(8)
	_expect(session.stock == session.deposit_capacity and not base.disabled and session.respawn_due_at == -1, "Deferred source refills normally when the corridor is released.")
	_expect(_legacy_total() == 3 and not runtime.daily.allow_haulers, "No duplicate receipt or new Hauler assignment.")
	marker.position = original
	runtime._refresh_navigation()
	print("RespawnLegacyHaulTest: PASS")

func _legacy_total() -> int:
	var total: int = runtime.hauling.routes.get(worker_id, {}).get("cargo", {}).get("quantity", 0)
	for pile: Node in runtime.get_node("GroundOutput").get_children():
		if pile is PickUpItem and pile.item_id == ITEM_ID and bool(pile.get_meta("legacy_stockpile", false)):
			total += int(pile.quantity)
	return total
