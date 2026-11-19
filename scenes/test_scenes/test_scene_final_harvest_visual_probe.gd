extends Node

## QA-only: harvest the last unit through the real manual session, then force
## only the test deadline to the present to inspect regrowth without a long wait.
const CITY = preload("res://scenes/content_scene/content_scene.tscn")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	_check(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use disposable game data.")
	TimeComponentManager.set_process(false)
	var city: Node2D = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await get_tree().process_frame
	await get_tree().physics_frame
	var work: Node = city.get_node("YSortWorld/WorkerRuntime")
	var player: Player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	Inventory.max_load = 100000.0
	for site_id: StringName in [&"WoodSite", &"ReedSite"]:
		var site: Node2D = work.get_node("WorksiteMarkers/" + str(site_id))
		var deposit = work.sites[site_id]
		var item_id: String = deposit.item_id
		var old_position: Vector2 = site.global_position
		var before: int = int(Inventory.items.get(item_id, 0))
		deposit.stock = 1
		deposit.participants.assign(["player"])
		work._selected_site = site
		var result: Dictionary = deposit.execute(180, player, work, work._drop_output)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(int(result.units) == 1 and int(result.to_bag) == 1 and not bool(result.interrupted)
			and deposit.stock == 0 and int(Inventory.items.get(item_id, 0)) == before + 1,
			"%s settles its actual last manually harvested unit once." % site_id)
		var particles: CPUParticles2D = site.get_node("ReadyParticles")
		_check(not particles.emitting and not particles.visible and deposit.respawn_due_at > work.daily.now(),
			"%s starts its real respawn deadline and hides readiness particles after the last unit." % site_id)
		if site_id == &"WoodSite":
			for index: int in range(4):
				_check(not site.get_node("WoodGrove/Tree%d" % index).visible and site.get_node("WoodGrove/Stump%d" % index).visible,
					"Wood last-unit settlement shows stump %d." % index)
		else:
			_check(not site.get_node("ResourceIcon").visible and site.get_node("CuttedReed").visible,
				"Reed last-unit settlement shows cut art.")
		player.global_position = site.global_position + Vector2(450, 450)
		deposit.respawn_due_at = work.daily.now() # Fixture-only shortcut; never saved.
		work._queue_depleted_sites()
		for _frame: int in range(8):
			await get_tree().process_frame
		_check(deposit.stock == deposit.deposit_capacity and site.global_position == old_position
			and particles.visible and particles.emitting,
			"%s regrows at the same spot with particles when its deadline is due and clear." % site_id)
		if site_id == &"WoodSite":
			for index: int in range(4):
				_check(site.get_node("WoodGrove/Tree%d" % index).visible and not site.get_node("WoodGrove/Stump%d" % index).visible,
					"Wood regrowth restores tree %d." % index)
		else:
			_check(site.get_node("ResourceIcon").visible and not site.get_node("CuttedReed").visible,
				"Reed regrowth restores ready art.")
		print("FINAL_HARVEST ", site_id, " result=", result, " failures=", failures)
	print("FinalHarvestVisualProbe: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
