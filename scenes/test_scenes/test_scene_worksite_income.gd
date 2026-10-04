extends Node

## Measurement harness only: no money, materials, equipment, or workers granted.
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
	var scenario: String = OS.get_environment("TIP_INCOME_SCENARIO")
	if scenario.is_empty():
		scenario = "main"
	var main_map: bool = scenario == "main"
	var content: Node = load("res://scenes/content_scene/content_scene.tscn" if main_map else "res://scenes/test_scenes/fixtures/content_worksites_map.tscn").instantiate()
	if not main_map:
		content.get_node("YSortWorld/Worksites").seed_playtest_hauler = false
	add_child(content)
	await get_tree().process_frame
	var player: Player = content.get_node("YSortWorld/Player")
	_expect(Inventory.items.is_empty(), "Scenario starts with no money or inventory goods.")
	if main_map:
		var runtime: Node = content.get_node("YSortWorld/WorkerRuntime")
		print("INCOME_AUDIT ", JSON.stringify({"scenario": scenario, "sites": runtime.sites.keys(), "inventory": Inventory.items,
			"needs_disabled": player.debug_disable_player_needs, "fatigue_disabled": player.debug_disable_fatigue}))
		_expect(runtime.sites.is_empty(), "Current main map has no gathering markers.")
	else:
		# Arrival-day comparison. Clock placement is a scenario boundary, not earned playtime.
		TimeComponentManager.current_day = 1
		TimeComponentManager.current_hour = 8
		TimeComponentManager.current_minute = 0
		TimeComponentManager.emit_time_signal()
		if scenario in ["WaterNeeds", "MixedNeeds"]:
			player.debug_disable_player_needs = false
			player.debug_disable_fatigue = false
		var worksites: Node = content.get_node("YSortWorld/Worksites")
		var site_id: String = "WaterSite" if scenario in ["WaterRepeat", "WaterNeeds", "MixedNeeds"] else scenario
		var site: RefCounted = worksites.sites[StringName(site_id)]
		worksites._selected_site = worksites.get_node("WorksiteMarkers/" + site_id)
		player.global_position = worksites._selected_site.global_position
		_expect(site.toggle_participant("player"), "Player can gather without hiring or funds.")
		var merchant: Node = load("res://scenes/traveling_merchant/merchant_state.gd").new()
		add_child(merchant)
		var batches: int = 3 if scenario in ["WaterRepeat", "WaterNeeds", "MixedNeeds"] else 1
		for index: int in range(batches):
			if scenario == "MixedNeeds" and index == 2:
				site_id = "ClaySiteA"
				site = worksites.sites[&"ClaySiteA"]
				worksites._selected_site = worksites.get_node("WorksiteMarkers/ClaySiteA")
				site.toggle_participant("player")
			var before: Dictionary = {"fatigue": player.fatigue, "hunger": player.hunger, "focus": player.focus}
			var preview: Dictionary = site.preview(180, player)
			var result: Dictionary = site.execute(180, player, worksites, worksites._drop_output)
			var quantity: int = int(Inventory.items.get(site.item_id, 0))
			var sale: Dictionary = merchant.trade(site.item_id, quantity, false)
			print("INCOME_MEASURE ", JSON.stringify({"scenario": scenario, "batch": index + 1, "preview": preview, "result": result,
				"item": site.item_id, "sale": sale, "inventory": Inventory.items, "merchant": merchant.get_budget(), "stock_left": site.stock,
				"hour": TimeComponentManager.current_hour, "minute": TimeComponentManager.current_minute,
				"before": before, "after": {"fatigue": player.fatigue, "hunger": player.hunger, "focus": player.focus},
				"needs_disabled": player.debug_disable_player_needs, "fatigue_disabled": player.debug_disable_fatigue}))
			if scenario == "MixedNeeds":
				for drop: Node2D in worksites.get_node("GroundOutput").get_children():
					if not drop.is_collecting:
						player.global_position = drop.global_position
						drop.on_player_interact(player)
				var recovered: int = int(Inventory.items.get(site.item_id, 0))
				if recovered > 0:
					_expect(merchant.trade(site.item_id, recovered, false).ok, "Overflow can be picked up after selling and sold normally.")
				print("INCOME_RECOVERED ", JSON.stringify({"batch": index + 1, "recovered": recovered, "wallet": Inventory.items.get("shekel", 0), "merchant": merchant.get_budget()}))
				_expect(Inventory.items.get("shekel", 0) == [36, 72, 90][index], "Mixed route income reconciles without grants.")
			if index == 0:
				_expect(result.minutes == 180 and not result.interrupted, "First three-hour gathering completes without seeded inputs.")
			if site_id == "ReedSite":
				_expect(not sale.ok, "Merchant does not buy reed in the current catalog.")
			elif result.units > 0:
				_expect(sale.ok, "Gathered goods can be sold for actual Shekel.")
		merchant.queue_free()
	content.queue_free()
	await get_tree().process_frame
	print("WorksiteIncomeTest ", scenario, ": ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
