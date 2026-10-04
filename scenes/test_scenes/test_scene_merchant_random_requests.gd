extends Node

var failures: int = 0
var state: Node
var content: Node

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _clock(day: int, hour: int, minute: int = 0) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.emit_time_signal()

func _profile() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in state.get_catalog():
		if row.requested > 0:
			result[row.item_id] = row.requested
	return result

func _load_map() -> void:
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	state = content.get_node("YSortWorld/TravelingMerchant").state

func _run() -> void:
	TimeComponentManager.set_process(false)
	_clock(0, 10)
	_load_map()
	state._request_rng.seed = 20261004
	var profiles: Dictionary = {}
	for visit: int in range(20):
		var day: int = 1 + visit * 3
		_clock(day, 8)
		var profile: Dictionary = _profile()
		_expect(profile.size() >= 1 and profile.size() <= 2, "Each visit requests one or two eligible goods.")
		for id: String in profile:
			_expect(id in ["wood_log", "sun_dried_mudbrick"], "Randomization does not admit raw resources outside the approved pool.")
			_expect(profile[id] >= (3 if id == "wood_log" else 10) and profile[id] <= (6 if id == "wood_log" else 20), "Random quantity stays inside configuration bounds.")
		profiles[JSON.stringify(profile)] = true
		print("RANDOM_VISIT ", day, " ", JSON.stringify(profile))
		var menu: TravelingMerchantUI = preload("res://scenes/ui/traveling_merchant_ui/traveling_merchant_ui.tscn").instantiate()
		add_child(menu)
		menu.open_menu(state)
		menu.sell_tab.pressed.emit()
		_expect(menu.catalog_list.get_child_count() == profile.size(), "Sell displays only goods selected for this visit.")
		var folder := OS.get_environment("TIP_MERCHANT_CAPTURE_DIR")
		if visit < 3 and not folder.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(folder.path_join("requests-day-%d.png" % day))
		menu.close_menu()
		await get_tree().process_frame
		_expect(_profile() == profile, "Opening/closing the panel cannot reroll requests.")
		# Explicit funds/goods here test quotas, not the fresh-start income route.
		Inventory.items = {"shekel": 100, "wood_log": 6, "sun_dried_mudbrick": 20}
		var selected: String = profile.keys()[0]
		_expect(state.trade(selected, 1, false).ok, "An active request accepts a sale.")
		_expect(state.trade(selected, 1, true).ok, "Sold goods can be bought back at the buy price.")
		var remaining: Dictionary = state._demand.duplicate()
		_expect(remaining[selected] == profile[selected] - 1, "Buyback does not reroll or refill demand.")
		for id: String in ["wood_log", "sun_dried_mudbrick", "water_jar"]:
			if not profile.has(id):
				_expect(not state.trade(id, 1, false).ok, "Unselected goods cannot be sold even if owned.")
		_clock(day, 8, 1)
		_expect(_profile() == profile and state._demand == remaining, "Minute updates preserve both profile and consumed quota.")
		if visit == 0:
			var ledger: Node = state
			content.free()
			_load_map()
			_expect(state == ledger and _profile() == profile and state._demand == remaining, "Main-map reload preserves the exact randomized visit ledger.")
		_clock(day, 7)
		_expect(not state.is_present() and _profile() == profile, "Rewinding cannot roll another request set.")
		_clock(day, 8, 1)
		_expect(state._demand == remaining, "Returning to the same visit does not refill demand.")
		_clock(day, 18)
		_clock(day + 1, 8)
		_expect(not state.is_present() and _profile() == profile, "Non-visit days never roll requests.")
	_expect(profiles.size() > 1, "The seeded multi-visit sample produces varied requests.")
	content.free()
	print("MerchantRandomRequestsTest: ", "PASS" if failures == 0 else "FAIL", " unique_profiles=", profiles.size())
	get_tree().quit(0 if failures == 0 else 1)
