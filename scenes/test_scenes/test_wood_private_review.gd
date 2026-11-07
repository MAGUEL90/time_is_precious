extends Node
const CITY = preload("res://scenes/content_scene/content_scene.tscn")
const SITE_IDS: Array[StringName] = [&"WoodSite", &"WoodSiteB", &"WoodSiteC"]
const ROOTS: Array[Vector2] = [Vector2(-18, -4), Vector2(-6, -8), Vector2(6, -8), Vector2(18, -4)]
var errors: Array[String] = []
var checks: int = 0
var city: Node2D
var work: Node
var player: Player
func check(condition: bool, msg: String) -> void:
	checks += 1
	if not condition:
		errors.append(msg)
		push_error(msg)
func frames() -> void:
	for i in range(3):
		await get_tree().physics_frame
		await get_tree().process_frame
func _ready() -> void:
	go.call_deferred()
func go() -> void:
	var root_path: String = OS.get_environment("XDG_DATA_HOME")
	check(root_path.is_absolute_path() and ProjectSettings.globalize_path("user://").begins_with(root_path.trim_suffix("/") + "/"), "Isolated XDG profile")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	city = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await frames()
	work = city.get_node("YSortWorld/WorkerRuntime")
	player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	player.set_physics_process(false)
	for id in SITE_IDS:
		var marker: Node2D = work.get_node("WorksiteMarkers/" + str(id))
		var grove: Node2D = marker.get_node_or_null("WoodGrove")
		var area: Area2D = marker.get_node_or_null("WoodInteractionArea")
		check(grove != null and area != null, "%s has grove and Area2D" % id)
		if grove == null or area == null:
			continue
		var rect: RectangleShape2D = area.get_child(0).shape
		var center: Vector2 = area.get_child(0).position
		for i in range(4):
			var tree: Sprite2D = grove.get_node_or_null("Tree%d" % i)
			var stump: Sprite2D = grove.get_node_or_null("Stump%d" % i)
			check(tree != null and tree.visible and stump != null and not stump.visible, "%s tree %d visible before depletion" % [id, i])
			check(tree.position == stump.position and tree.position == ROOTS[i], "%s tree %d and stump share bottom anchor" % [id, i])
			check(Rect2(center - rect.size / 2, rect.size).has_point(tree.position), "%s area covers tree %d trunk point" % [id, i])
			player.current_interactable = null
			player.global_position = marker.to_global(ROOTS[i] + Vector2(0, 8))
			await frames()
			var nearest: Node = work._nearest_interaction_site()
			check(area.overlaps_body(player), "%s tree %d area detects player" % [id, i])
			check(nearest == marker, "%s tree %d interaction selects intended site; got %s" % [id, i, nearest.name if nearest else "none"])
			if i == 0 and nearest == marker:
				var interact := InputEventAction.new()
				interact.action = "interact"
				interact.pressed = true
				work._unhandled_input(interact)
				check(work.inspector.visible and work._selected_site == marker, "%s actual interaction opens correct inspector" % id)
				work._close_inspector()
				await frames()
		player.global_position = marker.to_global(Vector2(80, 100))
		await frames()
		var original: Vector2 = marker.position
		var site = work.sites[id]
		site.stock = 0
		work._sync_site_timer(id)
		await frames()
		var due: int = site.respawn_due_at
		check(due - site.respawn_started_at >= 2880 and due - site.respawn_started_at <= 4320, "%s timer 2–3 days" % id)
		for i in range(4):
			check(not grove.get_node("Tree%d" % i).visible and grove.get_node("Stump%d" % i).visible, "%s stump %d visible after depletion" % [id, i])
		# Exercise direct deadline without waiting whole day, using the real scheduler clock.
		var elapsed: int = due - work.daily.now()
		check(TimeComponentManager.advance_minutes(elapsed), "%s advances to deadline" % id)
		await frames()
		check(site.stock == site.deposit_capacity and marker.position == original, "%s regenerates at same location at due time" % id)
		for i in range(4):
			check(grove.get_node("Tree%d" % i).visible and not grove.get_node("Stump%d" % i).visible, "%s tree %d returns" % [id, i])
	# Real save/continue roundtrip while WoodSiteB is depleted.
	var store: Node = WorkStateRuntime.get_node("CitySave")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://wood_private_review"))
	store.disk.path = "user://wood_private_review/checkpoint.json"
	var marker_b: Node2D = work.get_node("WorksiteMarkers/WoodSiteB")
	var site_b = work.sites[&"WoodSiteB"]
	player.global_position = marker_b.to_global(Vector2(80, 100))
	await frames()
	site_b.stock = 0
	work._sync_site_timer(&"WoodSiteB")
	await frames()
	var due_b: int = site_b.respawn_due_at
	var original_b: Vector2 = marker_b.position
	check(store.save_checkpoint(), "Save depleted WoodSiteB: " + store.last_error)
	site_b.stock = site_b.deposit_capacity
	work._set_site_depleted_presentation(&"WoodSiteB", false)
	await frames()
	check(store.load_checkpoint(), "Continue depleted WoodSiteB: " + store.last_error)
	await frames()
	check(site_b.stock == 0 and site_b.respawn_due_at == due_b and marker_b.position == original_b, "Continue restores original depleted stock, deadline and position")
	check(not marker_b.get_node("WoodGrove/Tree0").visible and marker_b.get_node("WoodGrove/Stump0").visible, "Continue restores stump")
	check(store.load_checkpoint() and site_b.respawn_due_at == due_b, "Repeated Continue never rerolls deadline")
	await frames()
	# The player occupying the original collider blocks regrowth instead of
	# getting trapped; leaving should allow retry at a subsequent clock tick.
	var collision: CollisionPolygon2D = marker_b.get_node("ResourceBase/CollisionPolygon2D")
	var centroid := Vector2.ZERO
	for p in collision.polygon:
		centroid += p
	centroid /= float(collision.polygon.size())
	player.global_position = collision.to_global(centroid) + Vector2(0, 4)
	await frames()
	check(not work._wood_regrowth_clear(marker_b), "Regrowth detects player in original resource collider")
	check(TimeComponentManager.advance_minutes(due_b - work.daily.now()), "Advance to blocked deadline")
	await frames()
	check(site_b.stock == 0 and marker_b.get_node("WoodGrove/Stump0").visible, "Blocked regrowth stays depleted")
	player.global_position = marker_b.to_global(Vector2(80, 100))
	await frames()
	check(TimeComponentManager.advance_minutes(1), "Tick after player leaves")
	await frames()
	check(site_b.stock == site_b.deposit_capacity and marker_b.position == original_b, "Regrowth retries at same location when clear")
	# A valid v5 relocation already present in an older save stays put instead
	# of snapping back to its original authored marker or relocating again.
	var legacy_offset := Vector2(48, 48)
	marker_b.position = Vector2(work._site_origins[&"WoodSiteB"]) + legacy_offset
	work._refresh_navigation()
	await frames()
	site_b.stock = 0
	work._sync_site_timer(&"WoodSiteB")
	await frames()
	var legacy_due: int = site_b.respawn_due_at
	check(store.save_checkpoint(), "Save valid earlier WoodSiteB offset: " + store.last_error)
	marker_b.position = Vector2(work._site_origins[&"WoodSiteB"])
	check(store.load_checkpoint(), "Continue valid earlier WoodSiteB offset: " + store.last_error)
	await frames()
	check(work.resource_site_offset(&"WoodSiteB") == legacy_offset and site_b.respawn_due_at == legacy_due, "Earlier v5 offset and deadline preserved")
	player.global_position = marker_b.to_global(Vector2(80, 100))
	await frames()
	check(TimeComponentManager.advance_minutes(legacy_due - work.daily.now()), "Advance earlier offset to regrowth")
	await frames()
	check(site_b.stock == site_b.deposit_capacity and work.resource_site_offset(&"WoodSiteB") == legacy_offset, "Earlier saved offset regrows in place")
	city.queue_free()
	await get_tree().process_frame
	print("Wood private review: ", "PASS" if errors.is_empty() else "FAIL", " checks=", checks, " failures=", errors.size())
	get_tree().quit(0 if errors.is_empty() else 1)
