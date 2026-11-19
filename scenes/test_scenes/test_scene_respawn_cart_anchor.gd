extends "res://scenes/test_scenes/test_scene_city_transport_flow.gd"

## Native cart interpolation may be ahead of its committed leg origin. A
## temporary runtime marker tests respawn on that origin without editing the map.
var marker: Node2D
var collider: CollisionPolygon2D
var marker_origin: Vector2
var visuals: Node

func _write_flow() -> void:
	var data_root := OS.get_environment("XDG_DATA_HOME").simplify_path()
	_expect(data_root.contains("citysave_suite_qa") and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root + "/"), "Use an isolated QA profile.")
	if stopped:
		return
	worker_id = "initial_city_storage_hauler"
	Inventory.add_item("shekel", 10)
	var courier: WorkerData = WorkerDatabase.hire_applicant(worker_id, 1, 3)
	_expect(courier != null and central.allocate("initial_worksite_cart", worker_id), "Hire and equip the real Hauler.")
	_expect(central.try_add_worksite_output(ITEM_ID, 6) and transport.start(worker_id, "city", ITEM_ID, 3), "Load one native city shipment.")
	if stopped:
		return
	marker = runtime.get_node("WorksiteMarkers/WoodSite")
	collider = marker.get_node("ResourceBase/CollisionPolygon2D")
	marker_origin = marker.position
	visuals = runtime.get_node("WorkerVisuals")
	await _check_anchor("loaded outbound")
	if stopped:
		return
	for minute in range(20):
		if transport.route.get("phase", "") == "returning":
			break
		_expect(TimeComponentManager.advance_minutes(1), "Advance outbound route.")
		await _frames(3)
	_expect(transport.route.get("phase", "") == "returning" and int(transport.route.quantity) == 0 and int(annex.items.get(ITEM_ID, 0)) == 3, "One receipt starts the empty return leg.")
	if stopped:
		return
	await _check_anchor("empty return")
	if stopped:
		return
	await _finish_route()
	_expect(transport.route.is_empty() and int(central.items.get(ITEM_ID, 0)) == 3 and int(annex.items.get(ITEM_ID, 0)) == 3, "Both protected legs finish without cargo loss or duplication.")
	print("RespawnCartAnchorTest: PASS")

func _check_anchor(label: String) -> void:
	var session = runtime.sites.WoodSite
	session.stock = 0
	session.respawn_started_at = now()
	session.respawn_due_at = now() + 1000
	runtime._set_site_depleted_presentation("WoodSite", true)
	await _frames(4)
	var anchor: Vector2 = transport.route.leg_origin + transport.FEET_OFFSET
	var direction: Vector2 = (transport._leg_target(transport.route) - transport.route.leg_origin).normalized()
	var polygon: PackedVector2Array = runtime._resource_occupancy_polygon(marker, collider)
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		center += point
	center /= polygon.size()
	marker.global_position += anchor - direction * 4.0 - center
	runtime._refresh_navigation()
	var deadline := Time.get_ticks_msec() + 10000
	while visuals.fraction < 0.95 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var actor: Node2D = visuals.actors.get(worker_id)
	_expect(is_instance_valid(actor) and visuals.fraction >= 0.95 and actor.global_position.distance_to(Vector2(transport.route.leg_origin)) > 9.0, "Native interpolation advances ahead of committed origin: " + label)
	if stopped:
		return
	session.respawn_due_at = now()
	runtime._queue_depleted_sites()
	await _frames(8)
	_expect(session.stock == 0 and collider.disabled and runtime.worksite_navigation.is_clear(anchor), "Respawn protects cart origin even when the visible actor has left: " + label)
	if stopped:
		return
	visuals.set_process(false)
	actor.hide()
	_expect(not runtime._site_regrowth_clear(marker), "Transport origin remains occupied without its visual: " + label)
	visuals.set_process(true)
	_expect(TimeComponentManager.advance_minutes(1), "Commit the next collision-clear cart position.")
	await _frames(8)
	_expect(session.stock == 24 and not collider.disabled and runtime.worksite_navigation.is_clear(Vector2(transport.route.leg_origin) + transport.FEET_OFFSET), "Refill resumes once the committed cart origin clears: " + label)
	marker.position = marker_origin
	runtime._refresh_navigation()
	_expect(int(central.items.get(ITEM_ID, 0)) + int(annex.items.get(ITEM_ID, 0)) + int(transport.route.get("quantity", 0)) == 6, "Cargo ownership remains conserved: " + label)
