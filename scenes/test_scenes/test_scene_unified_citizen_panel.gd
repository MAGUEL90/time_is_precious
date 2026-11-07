extends Node

## Panel-only fixture. It uses memory-only data and never opens a CitySave.
const PANEL: PackedScene = preload("res://scenes/ui/citizen_inspection/citizen_inspection_panel.tscn")
const PERSON_ID: String = "unified_citizen_panel_fixture"
const SECOND_ID: String = "unified_citizen_panel_second"
const LEGACY_ID: String = "unified_citizen_panel_legacy"

var panel: CitizenInspectionPanel
var worker: WorkerData
var summary: Dictionary = {}
var failures: int = 0
var renew_ids: Array[String] = []
var action_ids: Array[String] = []
var close_count: int = 0
var capture_directory: String = ""
var prior_worker: WorkerData
var had_worker: bool = false
var prior_citizens: Dictionary = {}
var first_citizen: CitizenData
var second_citizen: CitizenData
var prior_pause: bool = false
var prior_day: int
var prior_hour: int
var prior_minute: int

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture_directory = OS.get_environment("TIP_UNIFIED_CAPTURE_DIR")
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _frames(count: int = 1) -> void:
	for _index: int in range(count):
		await get_tree().process_frame

func _wait_for_refresh() -> void:
	await get_tree().create_timer(0.3, true).timeout
	await _frames(2)

func _summary_for(id: String) -> Dictionary:
	return summary.duplicate(true) if id in [PERSON_ID, SECOND_ID, LEGACY_ID] else {}

func _fixture_citizen(id: String, display_name: String, profile: VisualProfile) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = display_name
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.visual_profile = profile
	return citizen

func _label(path: String) -> Label:
	return panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/" + path) as Label


func _need_matches(need: String, value: Variant) -> bool:
	var card: Control = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/DailyNeedsRow/" + need + "Status") as Control
	var label: Label = card.get_node("Status/Label") as Label
	var icon: TextureRect = card.get_node("Status/MetIcon") as TextureRect
	var met: bool = value != null and bool(value)
	var text: String = "Unknown" if value == null else ("Met" if met else "Missing")
	var texture: AtlasTexture = icon.texture as AtlasTexture
	return card.get_node("Label").text == need and icon.visible == met and label.visible == not met \
		and label.text == text and card.accessibility_name == need + ": " + text \
		and card.tooltip_text == need + ": " + text and card.get_node("Icon").tooltip_text == need + ": " + text \
		and card.get_node("Status").tooltip_text == need + ": " + text and icon.accessibility_name == need + ": " + text \
		and texture != null and texture.region == Rect2(84, 68, 8, 8) \
		and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_window().size = Vector2i(1200, 675)
		await _frames(3)
	_expect(get_window().size == Vector2i(1200, 675)
		and get_viewport().get_visible_rect().size == Vector2(400, 225),
		"The compact Needs panel is tested in the 1200x675 window at 400x225 logical size.")
	prior_pause = get_tree().paused
	prior_day = TimeComponentManager.current_day
	prior_hour = TimeComponentManager.current_hour
	prior_minute = TimeComponentManager.current_minute
	had_worker = WorkerDatabase.workers_by_id.has(PERSON_ID)
	prior_worker = WorkerDatabase.get_worker_data(PERSON_ID)
	WorkerDatabase.workers_by_id.erase(PERSON_ID)
	for id: String in [PERSON_ID, SECOND_ID, LEGACY_ID]:
		if CitizenManager.citizens_by_id.has(id):
			prior_citizens[id] = CitizenManager.citizens_by_id[id]
		CitizenManager.citizens_by_id.erase(id)
	var first_profile := VisualProfile.new()
	first_profile.skin_tone = "dark"
	first_profile.expression = "base"
	first_profile.hair_style = "black_male_01"
	first_profile.clothes_id = "clay_worn_wrap"
	first_profile.accessory = "default"
	first_citizen = _fixture_citizen(PERSON_ID, "Bellum", first_profile)
	var second_profile := VisualProfile.new()
	second_profile.skin_tone = "warm"
	second_profile.expression = "tired"
	second_profile.hair_style = "red_female_01"
	second_profile.clothes_id = "plain_worn_wrap"
	second_profile.accessory = "farmer_hat"
	second_citizen = _fixture_citizen(SECOND_ID, "Naram", second_profile)
	CitizenManager.citizens_by_id[PERSON_ID] = first_citizen
	CitizenManager.citizens_by_id[SECOND_ID] = second_citizen
	CitizenManager.citizens_by_id[LEGACY_ID] = _fixture_citizen(LEGACY_ID, "Legacy", null)
	get_tree().paused = true
	TimeComponentManager.current_day = 40
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 30
	summary = {
		"name": "Bellum", "evaluated": true, "day": 40,
		"food": true, "clothing": false, "shelter": true, "clothing_days_left": 0,
		"satisfaction": 0.55, "satisfaction_delta": -0.05,
		"condition_target": 0.66, "trend": "stable"
	}
	panel = PANEL.instantiate() as CitizenInspectionPanel
	panel.summary_provider = _summary_for
	panel.renew_requested.connect(func(id: String): renew_ids.append(id))
	panel.actions_requested.connect(func(id: String): action_ids.append(id))
	panel.closed.connect(func(): close_count += 1)
	add_child(panel)
	panel.open_for(PERSON_ID)
	await _frames(3)

	var frame: Control = panel.get_node("Root/Frame") as Control
	var name_label: Label = panel.get_node("Root/Frame/Margin/Contents/NameRow/NameLabel") as Label
	var satisfaction_bar: TextureProgressBar = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionBar") as TextureProgressBar
	var close_button: TextureButton = panel.get_node("Root/Frame/Margin/Contents/NameRow/CloseButton") as TextureButton
	var scroll: ScrollContainer = panel.get_node("Root/Frame/Margin/Contents/BodyScroll") as ScrollContainer
	_expect(panel.visible and panel.selected_id == PERSON_ID and get_tree().paused,
		"The panel opens while the caller owns the paused tree.")
	_expect(_label("NeedsHeading").text == "NEEDS"
		and _label("NeedsHeading").horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
		and panel.find_child("WorkerSection", true, false) == null
		and panel.find_child("WorkerActions", true, false) == null
		and panel.find_child("RenewButton", true, false) == null
		and panel.find_child("ActionsButton", true, false) == null,
		"The centered Needs card contains no Work section or action controls.")
	_expect(_need_matches("Food", true)
		and _need_matches("Clothing", false)
		and _need_matches("Shelter", true)
		and _label("SatisfactionLabel").text == "Actual satisfaction: 55%"
		and is_equal_approx(satisfaction_bar.value, 55.0),
		"All individual needs and live satisfaction are shown.")
	# Exercise every state and reopening without adding duplicate check icons.
	for value: Variant in [true, false, null]:
		summary.evaluated = value != null
		for key: String in ["food", "clothing", "shelter"]:
			summary[key] = value == true
		panel.call("_refresh_view")
		for need: String in ["Food", "Clothing", "Shelter"]:
			_expect(_need_matches(need, value), "Needs state remains clear and accessible: %s/%s" % [need, str(value)])
	panel.open_for(PERSON_ID)
	panel.open_for(PERSON_ID)
	for need: String in ["Food", "Clothing", "Shelter"]:
		var card: Control = scroll.get_node("Body/DailyNeedsRow/" + need + "Status") as Control
		_expect(card.find_children("MetIcon", "TextureRect", true, false).size() == 1, "Reopening keeps one check icon: " + need)
	summary.evaluated = true
	summary.food = true
	summary.clothing = false
	summary.shelter = true
	panel.call("_refresh_view")
	summary.satisfaction = 0.42
	panel.call("_refresh_view")
	_expect(_label("SatisfactionLabel").text == "Actual satisfaction: 42%"
		and is_equal_approx(satisfaction_bar.value, 42.0),
		"A later satisfaction change leaves the last daily-check delta intact.")
	summary.evaluated = false
	panel.call("_refresh_view")
	_expect(_need_matches("Food", null) and _need_matches("Clothing", null) and _need_matches("Shelter", null)
		and is_equal_approx(satisfaction_bar.value, 42.0)
		and panel.find_child("DailyCheckLabel", true, false) == null
		and panel.find_child("ClothingDaysLabel", true, false) == null
		and panel.find_child("DailyChangeLabel", true, false) == null
		and panel.find_child("ConditionLabel", true, false) == null,
		"An unevaluated citizen keeps unknown needs while daily-check and lower detail rows stay omitted.")
	summary.satisfaction = 0.55
	panel.call("_refresh_view")
	await _frames(3)
	await _capture("unevaluated")
	summary.evaluated = true
	summary.erase("satisfaction_delta")
	summary.erase("clothing_days_left")
	summary.erase("condition_target")
	panel.call("_refresh_view")
	_expect(panel.find_child("DailyChangeLabel", true, false) == null
		and panel.find_child("ClothingDaysLabel", true, false) == null
		and panel.find_child("ConditionLabel", true, false) == null,
		"Optional daily details are omitted even when the summary contains them.")
	summary.satisfaction_delta = -0.05
	summary.clothing_days_left = 0
	summary.condition_target = 0.66
	for invalid_value: Variant in [null, NAN, INF, -0.01, 1.01, "0.55"]:
		summary.satisfaction = invalid_value
		panel.call("_refresh_view")
		_expect(_label("SatisfactionLabel").text == "Actual satisfaction: Unknown"
			and is_zero_approx(satisfaction_bar.value),
			"An invalid satisfaction value is Unknown, never a fabricated percentage.")
	summary.erase("satisfaction")
	panel.call("_refresh_view")
	_expect(_label("SatisfactionLabel").text == "Actual satisfaction: Unknown"
		and is_zero_approx(satisfaction_bar.value), "Missing satisfaction is Unknown.")
	summary.satisfaction = 0.55
	panel.call("_refresh_view")
	_expect(panel.find_child("ClothingDaysLabel", true, false) == null
		and panel.find_child("DailyChangeLabel", true, false) == null
		and panel.find_child("ConditionLabel", true, false) == null,
		"Daily ledger details remain omitted while the core needs and satisfaction update.")
	_expect(scroll.get_node_or_null("Body/CityStockLabel") == null
		and scroll.get_node_or_null("Body/CityStockRow") == null,
		"The personal panel does not duplicate the City Hub supply display.")
	_expect(get_viewport().get_visible_rect().encloses(frame.get_global_rect())
		and scroll.size.y > 40.0 and not scroll.get_h_scroll_bar().visible
		and not scroll.get_v_scroll_bar().visible,
		"The compact card and non-scrolling needs viewport fit the logical viewport.")
	for need: String in ["FoodStatus", "ClothingStatus", "ShelterStatus"]:
		var icon: TextureRect = scroll.get_node("Body/DailyNeedsRow/" + need + "/Icon") as TextureRect
		_expect(icon.size == Vector2(16, 16) and icon.texture.get_size() == Vector2(16, 16)
			and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"Each need uses its nearest-filtered native 16-pixel icon: " + need)
	_expect(name_label.get_theme_font_size("font_size") == 6
		and _label("NeedsHeading").get_theme_font_size("font_size") == 6,
		"The panel keeps the project's integer pixel font sizes.")
	_expect(panel.find_child("PortraitFrame", true, false) == null
		and panel.find_child("PortraitVisual", true, false) == null
		and name_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"The Needs header has no portrait and centers the citizen's name.")
	var left_spacer: Control = panel.get_node("Root/Frame/Margin/Contents/NameRow/LeftSpacer") as Control
	_expect(is_equal_approx(left_spacer.size.x, close_button.size.x)
		and absf(name_label.get_global_rect().get_center().x - frame.get_global_rect().get_center().x) < 1.0
		and frame.get_global_rect().encloses(name_label.get_global_rect())
		and scroll.get_global_rect().encloses(satisfaction_bar.get_global_rect()),
		"The name and close button fit with balanced margins and the needs remain visible.")
	var initial_frame_rect: Rect2 = frame.get_global_rect()
	await _capture("nonworker")
	summary.name = "Naram"
	summary.evaluated = false
	panel.open_for(SECOND_ID)
	await _frames(3)
	_expect(name_label.text == "Naram" and name_label.accessibility_name == "Naram"
		and panel.selected_id == SECOND_ID and _need_matches("Food", null),
		"Switching resident updates the centered name and their displayed needs.")
	await _capture("second")
	summary.name = "Legacy"
	panel.open_for(LEGACY_ID)
	await _frames(3)
	_expect(name_label.text == "Legacy" and panel.visible,
		"A legacy person without a visual profile still has an accessible name.")
	CitizenManager.citizens_by_id.erase(LEGACY_ID)
	panel.call("_refresh_view")
	_expect(panel.visible and name_label.text == "Legacy", "The summary remains usable without a portrait source.")
	summary.name = "A very long citizen name that must not overlap the close button"
	panel.open_for(PERSON_ID)
	await _frames(3)
	_expect(name_label.clip_text and name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
		and name_label.tooltip_text == summary.name and name_label.accessibility_name == summary.name
		and name_label.get_global_rect().end.x <= close_button.get_global_rect().position.x,
		"Long names stay within the centered header and remain fully accessible.")
	await _capture("long-name")
	summary.name = "Bellum"
	summary.evaluated = true
	panel.call("_refresh_view")
	await _wait_for_refresh()
	_expect(name_label.text == "Bellum", "The timer refreshes the current name while the tree is paused.")
	worker = WorkerData.new()
	worker.worker_id = PERSON_ID
	worker.profession = WorkerData.Profession.HAULER
	WorkerDatabase.workers_by_id[PERSON_ID] = worker
	panel.worker_details_provider = func(id: String) -> Dictionary:
		return {"location": "Clay Site 2", "productive_days": 4} if id == PERSON_ID else {}
	await _wait_for_refresh()
	_expect(WorkerDatabase.get_worker_data(PERSON_ID) == worker
		and panel.find_child("WorkerSection", true, false) == null
		and panel.find_child("WorkerActions", true, false) == null
		and panel.find_child("RenewButton", true, false) == null
		and panel.find_child("ActionsButton", true, false) == null
		and frame.get_global_rect() == initial_frame_rect,
		"A linked worker does not expand the Needs card or expose Work details and controls.")
	panel.focus_primary()
	_expect(close_button.has_focus(), "The host can explicitly focus Close on the compact card.")
	panel.renew_requested.emit(PERSON_ID)
	panel.actions_requested.emit(PERSON_ID)
	_expect(renew_ids == [PERSON_ID] and action_ids == [PERSON_ID],
		"Host-facing renewal and action signals remain available without panel buttons.")
	scroll.scroll_vertical = 9999
	await _frames(3)
	_expect(scroll.scroll_vertical == 0,
		"The non-scrolling Needs body cannot retain an obsolete vertical scroll offset.")
	WorkerDatabase.workers_by_id.erase(PERSON_ID)
	await _wait_for_refresh()
	_expect(panel.visible and panel.find_child("WorkerSection", true, false) == null
		and panel.find_child("WorkerActions", true, false) == null,
		"Removing a worker leaves the resident Needs card open and unchanged.")
	WorkerDatabase.workers_by_id[PERSON_ID] = worker
	_expect(panel.find_child("WorkerSection", true, false) == null
		and WorkerDatabase.get_worker_data(PERSON_ID) == worker
		and name_label.text == "Bellum",
		"Worker records remain intact without exposing Work details in the Needs card.")

	summary.name = "An exceptionally long resident display name that must remain inside the header and be available in full"
	panel.call("_refresh_view")
	var refresh_timer: Timer = panel.get_node("RefreshTimer") as Timer
	refresh_timer.stop()
	await _frames(3)
	_expect(name_label.tooltip_text == summary.name and frame.get_global_rect().encloses(name_label.get_global_rect())
		and not scroll.get_h_scroll_bar().visible and name_label.get_line_count() <= name_label.get_visible_line_count(),
		"A long name remains bounded and available in full without clipping or horizontal scrolling (tooltip=%s lines=%d/%d label=%s frame=%s hbar=%s)." % [
			name_label.tooltip_text == summary.name, name_label.get_line_count(), name_label.get_visible_line_count(),
			name_label.get_global_rect(), frame.get_global_rect(), scroll.get_h_scroll_bar().visible])
	scroll.scroll_vertical = 9999
	await _frames(3)
	var body: Control = scroll.get_node("Body") as Control
	_expect(scroll.scroll_vertical == 0 and body.get_combined_minimum_size().y <= scroll.size.y
		and scroll.get_global_rect().encloses(_label("DailyNeedsRow/FoodStatus/Label").get_global_rect())
		and scroll.get_global_rect().encloses(_label("DailyNeedsRow/ClothingStatus/Label").get_global_rect())
		and scroll.get_global_rect().encloses(_label("DailyNeedsRow/ShelterStatus/Label").get_global_rect()),
		"Long names and remaining need details fit in the viewport without stale scrolling.")
	scroll.scroll_vertical = 14
	panel.open_for(PERSON_ID)
	await _frames(3)
	_expect(scroll.scroll_vertical == 0,
		"Opening the same citizen again resets any stale needs scroll offset.")
	await _capture("long-values")
	panel.close()
	_expect(refresh_timer.is_stopped(), "Closing stops the refresh timer.")
	_expect(not panel.visible and panel.selected_id.is_empty() and close_count == 1 and get_tree().paused,
		"Closing clears the selection and leaves the caller's pause untouched.")
	_finish()

func _capture(stage: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	if not capture_directory.is_absolute_path():
		_expect(false, "TIP_UNIFIED_CAPTURE_DIR must be an absolute path.")
		return
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(capture_directory)
	if directory_error != OK:
		_expect(false, "Unable to create the requested capture directory.")
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_expect(image.save_png(capture_directory.path_join(stage + ".png")) == OK,
		"The optional panel capture is saved: " + stage)

func _finish() -> void:
	if is_instance_valid(panel):
		panel.free()
	if had_worker:
		WorkerDatabase.workers_by_id[PERSON_ID] = prior_worker
	else:
		WorkerDatabase.workers_by_id.erase(PERSON_ID)
	for id: String in [PERSON_ID, SECOND_ID, LEGACY_ID]:
		if prior_citizens.has(id):
			CitizenManager.citizens_by_id[id] = prior_citizens[id]
		else:
			CitizenManager.citizens_by_id.erase(id)
	TimeComponentManager.current_day = prior_day
	TimeComponentManager.current_hour = prior_hour
	TimeComponentManager.current_minute = prior_minute
	get_tree().paused = prior_pause
	if failures == 0:
		print("UnifiedCitizenPanelTest PASSED")
	else:
		print("UnifiedCitizenPanelTest FAILED: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
