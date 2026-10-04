extends Node

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
	var fixture: Node = load("res://scenes/test_scenes/fixtures/content_worksites_map.tscn").instantiate()
	fixture.get_node("YSortWorld/Worksites").seed_playtest_hauler = false
	add_child(fixture)
	await get_tree().process_frame
	var player: Player = fixture.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	var worksites: Node = fixture.get_node("YSortWorld/Worksites")
	var site: RefCounted = worksites.sites[&"ClaySiteA"]
	site.toggle_participant("player")
	for sample: Dictionary in [{"fatigue": 0.0, "expected": 17}, {"fatigue": 0.5, "expected": 8}, {"fatigue": 0.75, "expected": 3}]:
		Inventory.items.clear()
		site.stock = 72
		player.fatigue = sample.fatigue
		player.hunger = 0.0
		player.focus = 1.0
		var before: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
		var preview: Dictionary = site.preview(180, player)
		_expect(player.fatigue == sample.fatigue and Inventory.items.is_empty() and site.stock == 72, "Preview never changes conditions or resources.")
		var result: Dictionary = site.execute(180, player, worksites)
		_expect(result.units == sample.expected and preview.units == result.units and result.minutes == 180, "Forecast and actual yield match the energy scenario.")
		_expect(site.stock == 72 - result.units and Inventory.items.get("clay_lump", 0) == result.units, "Only completed units consume stock and reach inventory.")
		_expect(is_equal_approx(player.fatigue, float(sample.fatigue) + 0.09), "Energy drains once through existing minute signals.")
		_expect(TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute - before == 180, "Lower yield does not shorten the chosen session.")
		print("ENERGY_SAMPLE ", JSON.stringify({"start_energy": 1.0 - float(sample.fatigue), "preview": preview.units, "output": result.units, "minutes": result.minutes, "end_energy": 1.0 - player.fatigue}))
	# A real condition change during the job must supersede the initial forecast.
	Inventory.items.clear()
	site.stock = 72
	player.fatigue = 0.5
	player.hunger = 0.0
	player.focus = 1.0
	var ticks: Array[int] = [0]
	var recover: Callable = func(_minute: int):
		ticks[0] += 1
		if ticks[0] == 90:
			player.fatigue = 0.0
	TimeComponentManager.minute_changed.connect(recover)
	var result: Dictionary = site.execute(180, player, worksites)
	TimeComponentManager.minute_changed.disconnect(recover)
	_expect(result.units > 8, "Live recovery increases output beyond the initial forecast; no snapshot cap.")
	# The normal no-needs debug mode remains deterministic at full energy.
	player.debug_disable_player_needs = true
	player.fatigue = 0.0
	site.stock = 5
	var preview: Dictionary = site.preview(180, player)
	result = site.execute(180, player, worksites)
	_expect(preview.minutes == 50 and result.minutes == 50 and result.units == 5, "Depletion stops at exactly the completed available stock.")
	fixture.queue_free()
	await get_tree().process_frame
	print("PlayerEnergyOutputTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
