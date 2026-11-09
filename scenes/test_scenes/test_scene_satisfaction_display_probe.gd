extends Node

const SATISFACTION_DISPLAY = preload("res://scenes/ui/satisfaction_display.gd")
const SAMPLE_VALUES: Array[Array] = [
	[0.0, 0],
	[1e-12, 1],
	[0.0049, 1],
	[0.005, 1],
	[0.0099, 1],
	[0.01, 1],
	[0.0149, 1],
	[0.015, 2],
	[0.99, 99],
	[1.0, 100],
]

var failures: int = 0
var _original_workers: Dictionary = {}
var _original_citizens: Dictionary = {}
var _original_tree_paused: bool = false
var _test_worker_id: String = ""
var _test_citizen_ids: Array[String] = []
var _worker: WorkerData
var _residents: Array[CitizenData] = []
var _citizen_panel: Node
var _applicant_card: Node
var _worker_hub: Node
var _inventory_ui: Node
var _gameplay_hud: Node
var _raid_ui: Node
var _worker_control: Node
var _test_nodes: Array[Node] = []
var _display_player: Player


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	_check_isolated_save_environment()
	_snapshot_and_isolate_globals()
	_create_fixtures()
	_instantiate_consumers()
	_test_boundaries_in_all_consumers()
	_test_raw_averages_and_live_refresh()
	_test_invalid_and_clamped_values()
	_restore_globals()
	_free_test_nodes()
	print("SatisfactionDisplayTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check_isolated_save_environment() -> void:
	if OS.get_name() != "Linux":
		return
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var isolated_root: String = data_root.simplify_path().trim_suffix("/")
	_expect(not data_root.is_empty() and data_root.is_absolute_path()
		and user_root.begins_with(isolated_root + "/"),
		"Run with an isolated absolute XDG_DATA_HOME; this test writes no saves.")


func _snapshot_and_isolate_globals() -> void:
	_original_workers = WorkerDatabase.workers_by_id.duplicate()
	_original_citizens = CitizenManager.citizens_by_id.duplicate()
	_original_tree_paused = get_tree().paused
	WorkerDatabase.workers_by_id.clear()
	CitizenManager.citizens_by_id.clear()


func _create_fixtures() -> void:
	_test_worker_id = "satisfaction_display_worker_%d" % OS.get_process_id()
	_worker = WorkerData.new()
	_worker.worker_id = _test_worker_id
	_worker.display_name = "Ashur"
	_worker.profession = WorkerData.Profession.LABORER
	WorkerDatabase.workers_by_id[_test_worker_id] = _worker

	for index: int in range(2):
		var citizen := CitizenData.new()
		citizen.citizen_id = "satisfaction_display_resident_%d_%d" % [OS.get_process_id(), index]
		citizen.display_name = "Naram" if index == 0 else "Nabu"
		citizen.population_status = CitizenData.PopulationStatus.RESIDENT
		citizen.satisfaction = 0.5
		_test_citizen_ids.append(citizen.citizen_id)
		_residents.append(citizen)
		CitizenManager.citizens_by_id[citizen.citizen_id] = citizen


func _instantiate_consumers() -> void:
	_citizen_panel = _instantiate("res://scenes/ui/citizen_inspection/citizen_inspection_panel.tscn")
	_applicant_card = _instantiate("res://scenes/ui/job_board_ui/job_board_candidate_card.tscn")
	_worker_hub = _instantiate("res://scenes/ui/worker_hub_ui/worker_hub_ui.tscn")
	_inventory_ui = _instantiate("res://scenes/ui/inventory_ui/inventory_ui.tscn")
	_gameplay_hud = _instantiate("res://scenes/ui/gameplay_hud/gameplay_hud.tscn")
	_raid_ui = _instantiate("res://scenes/raid/raid_ui.tscn")
	_worker_control = _instantiate("res://scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn")
	_display_player = Player.new()
	_gameplay_hud.set("player_ref", _display_player)


func _instantiate(path: String) -> Node:
	var packed: PackedScene = load(path) as PackedScene
	_expect(packed != null, "Packed scene loads: " + path)
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	_test_nodes.append(instance)
	add_child(instance)
	return instance


func _test_boundaries_in_all_consumers() -> void:
	var applicant := CitizenData.new()
	applicant.citizen_id = "satisfaction_display_applicant_%d" % OS.get_process_id()
	applicant.display_name = "Lugal"
	applicant.profession = WorkerData.Profession.LABORER

	for sample: Array in SAMPLE_VALUES:
		var value: float = float(sample[0])
		var expected_percent: int = int(sample[1])
		_expect(SATISFACTION_DISPLAY.to_percent(value) == expected_percent,
			"Shared helper formats %s as %d%%." % [value, expected_percent])

		_citizen_panel.call("_refresh_satisfaction", {"satisfaction": value})
		var citizen_label: Label = _citizen_panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionLabel")
		var citizen_bar: TextureProgressBar = _citizen_panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionBar")
		_expect_label(citizen_label, "Actual satisfaction: %d%%" % expected_percent, "Citizen inspection")
		_expect_bar_raw(citizen_bar, value * 100.0, "Citizen inspection")

		applicant.satisfaction = value
		_applicant_card.call("show_applicant", applicant, 1, 3, "Laborer")
		var applicant_label: Label = _applicant_card.get_node("Details/SatisfactionLabel")
		var applicant_accessibility: TextureRect = _applicant_card.get_node("Details/MoodIcon")
		var applicant_bar: TextureProgressBar = _applicant_card.get_node("Details/SatisfactionBar")
		_expect_label(applicant_label, "%d%%" % expected_percent, "Job Board applicant")
		_expect(not applicant_accessibility.accessibility_name.contains("<")
			and applicant_accessibility.accessibility_name == "Satisfaction: %d%%" % expected_percent,
			"Job Board accessibility text shows the same whole percent without a < symbol.")
		_expect_bar_raw(applicant_bar, value * 100.0, "Job Board applicant")

		_worker.satisfaction = value
		_worker_hub.call("_refresh_worker_lists")
		var worker_hub_list: VBoxContainer = _worker_hub.get_node("Root/Center/Window/Margin/MainVBox/Body/WorkerPanel/WorkerScroll/WorkerList")
		var worker_button: Button = worker_hub_list.get_child(worker_hub_list.get_child_count() - 1) as Button
		_expect(worker_button != null and worker_button.text.contains("SAT: %d%%" % expected_percent)
			and not worker_button.text.contains("<"),
			"Worker Hub row shows %d%% without a < symbol." % expected_percent)

		_inventory_ui.call("_refresh_worker_list")
		var inventory_list: VBoxContainer = _inventory_ui.get_node("Root/Center/Window/Margin/MainVBox/Body/RightPanel/WorkerPanel/MarginContainer/VBoxContainer/WorkerList")
		var inventory_label: Label = inventory_list.get_child(inventory_list.get_child_count() - 1) as Label
		_expect(inventory_label != null and inventory_label.text.contains("SAT %d%%" % expected_percent)
			and not inventory_label.text.contains("<"),
			"Inventory worker row shows %d%% without a < symbol." % expected_percent)

		for resident: CitizenData in _residents:
			resident.satisfaction = value
		_gameplay_hud.call("_refresh_player_status")
		var hud_body: Label = _gameplay_hud.get_node("Root/MarginContainer/TopLayer/TopRightPanel/MarginContainer/VBoxContainer/LabelAlertBody")
		_expect(hud_body.text.contains("SAT: %d%%" % expected_percent)
			and not hud_body.text.contains("<"),
			"Gameplay HUD average shows %d%% without a < symbol." % expected_percent)

		_raid_ui.call("_render_dashboard", "safe", 10, 10, 1, false)
		var raid_label: Label = _raid_ui.get("satisfaction_value") as Label
		var raid_bar: ProgressBar = _raid_ui.get("satisfaction_meter") as ProgressBar
		_expect_label(raid_label, "Resident avg.  %d%%" % expected_percent, "Raid dashboard")
		_expect_bar_raw(raid_bar, value * 100.0, "Raid dashboard")

		_test_worker_control_sample(value, expected_percent, 0.015)
		_expect(is_equal_approx(applicant.satisfaction, value) and is_equal_approx(_worker.satisfaction, value),
			"UI refreshes leave applicant and worker source satisfaction unchanged at %s." % value)
		for resident: CitizenData in _residents:
			_expect(is_equal_approx(resident.satisfaction, value),
				"UI refreshes leave resident source satisfaction unchanged at %s." % value)


func _test_worker_control_sample(value: float, expected_percent: int, delta: float) -> void:
	var row: Dictionary = {
		"name": "Ashur",
		"wage": "1 Shekel",
		"location": "Test site",
		"productive_days": 0,
		"star": 0,
		"needs": {
			"evaluated": true,
			"satisfaction": value,
			"satisfaction_delta": delta,
			"food": false,
			"clothing": false,
			"shelter": false,
		}
	}
	_worker_control.call("_render_details", row)
	var details_label: Label = _worker_control.get_node("Root/DetailsWindow/Margin/MainVBox/DetailsScroll/Visuals/SatisfactionLabel")
	var details_bar: TextureProgressBar = _worker_control.get_node("Root/DetailsWindow/Margin/MainVBox/DetailsScroll/Visuals/SatisfactionBar")
	var delta_percent: int = roundi(delta * 100.0)
	var delta_sign: String = "+" if delta_percent >= 0 else ""
	var expected_text: String = "Satisfaction: %d%% current (check %s%d%%)" % [expected_percent, delta_sign, delta_percent]
	_expect_label(details_label, expected_text, "Worker Control details")
	_expect_bar_raw(details_bar, clampf(value, 0.0, 1.0) * 100.0, "Worker Control details")


func _test_raw_averages_and_live_refresh() -> void:
	# Averaging the raw 0.0002 and 0.0196 values yields 0.0099 (1%).
	# Averaging their separately formatted 1% and 2% labels would incorrectly yield 2%.
	_residents[0].satisfaction = 0.0002
	_residents[1].satisfaction = 0.0196
	var raw_average: float = (0.0002 + 0.0196) / 2.0
	_expect(is_equal_approx(CitizenNeedsManager.get_average_satisfaction(), raw_average),
		"Fixture average remains the raw mean of resident satisfaction values.")
	_gameplay_hud.call("_refresh_player_status")
	var hud_body: Label = _gameplay_hud.get_node("Root/MarginContainer/TopLayer/TopRightPanel/MarginContainer/VBoxContainer/LabelAlertBody")
	_expect(hud_body.text.contains("SAT: 1%"), "Gameplay HUD formats the average of raw resident values, not average displayed values.")
	_raid_ui.call("_render_dashboard", "safe", 10, 10, 1, false)
	var raid_label: Label = _raid_ui.get("satisfaction_value") as Label
	var raid_bar: ProgressBar = _raid_ui.get("satisfaction_meter") as ProgressBar
	_expect(raid_label.text == "Resident avg.  1%", "Raid dashboard formats the average of raw resident values.")
	_expect_bar_raw(raid_bar, raw_average * 100.0, "Raid dashboard raw average")

	# Repeated live worker-detail refreshes update the same label and preserve the delta's old roundi rule.
	var detail_label: Label = _worker_control.get_node("Root/DetailsWindow/Margin/MainVBox/DetailsScroll/Visuals/SatisfactionLabel")
	var original_label_id: int = detail_label.get_instance_id()
	_test_worker_control_sample(0.0049, 1, 0.0149)
	_expect(detail_label.get_instance_id() == original_label_id and detail_label.text == "Satisfaction: 1% current (check +1%)",
		"Repeated Worker Control detail refresh updates the existing label and keeps daily delta rounding unchanged.")
	_test_worker_control_sample(0.015, 2, 0.015)
	_expect(detail_label.get_instance_id() == original_label_id and detail_label.text == "Satisfaction: 2% current (check +2%)",
		"Live Worker Control detail refresh updates current satisfaction without changing the daily delta rule.")
	_test_worker_control_sample(0.0049, 1, -0.015)
	_expect(detail_label.get_instance_id() == original_label_id and detail_label.text == "Satisfaction: 1% current (check -2%)",
		"Negative daily delta keeps the previous signed roundi behavior after live refresh.")


func _test_invalid_and_clamped_values() -> void:
	var citizen_label: Label = _citizen_panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionLabel")
	var citizen_bar: TextureProgressBar = _citizen_panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionBar")
	var invalid_summaries: Array[Dictionary] = [
		{},
		{"satisfaction": null},
		{"satisfaction": -0.01},
		{"satisfaction": 1.01},
		{"satisfaction": NAN},
		{"satisfaction": INF},
		{"satisfaction": "0.5"},
	]
	for invalid_summary: Dictionary in invalid_summaries:
		_citizen_panel.call("_refresh_satisfaction", invalid_summary)
		_expect_label(citizen_label, "Actual satisfaction: Unknown", "Invalid citizen inspection")
		_expect_bar_raw(citizen_bar, 0.0, "Invalid citizen inspection")

	_test_worker_control_sample(-0.2, 0, 0.0)
	var details_label: Label = _worker_control.get_node("Root/DetailsWindow/Margin/MainVBox/DetailsScroll/Visuals/SatisfactionLabel")
	var details_bar: TextureProgressBar = _worker_control.get_node("Root/DetailsWindow/Margin/MainVBox/DetailsScroll/Visuals/SatisfactionBar")
	_expect(details_label.text == "Satisfaction: 0% current (check +0%)" and is_equal_approx(details_bar.value, 0.0),
		"Worker Control keeps its existing lower clamp before formatting and bar assignment.")
	_test_worker_control_sample(1.2, 100, 0.0)
	_expect(details_label.text == "Satisfaction: 100% current (check +0%)" and is_equal_approx(details_bar.value, 100.0),
		"Worker Control keeps its existing upper clamp before formatting and bar assignment.")


func _expect_label(label: Label, expected_text: String, consumer: String) -> void:
	_expect(label != null and label.text == expected_text and not label.text.contains("<"),
		"%s label should be '%s' with no < symbol; got '%s'." % [consumer, expected_text, label.text if label != null else "<missing>"])


func _expect_bar_raw(bar: Range, raw_value: float, consumer: String) -> void:
	if bar == null:
		_expect(false, "%s bar exists." % consumer)
		return
	# Keep Range's authored step quantization; allow at most half one step from the assigned value.
	var tolerance: float = maxf(bar.step * 0.5001, 0.00001)
	_expect(absf(bar.value - raw_value) <= tolerance,
		"%s bar keeps the raw value %s (within authored step %s); got %s." % [consumer, raw_value, bar.step, bar.value])


func _restore_globals() -> void:
	WorkerDatabase.workers_by_id.clear()
	for worker_id: String in _original_workers:
		WorkerDatabase.workers_by_id[worker_id] = _original_workers[worker_id]
	CitizenManager.citizens_by_id.clear()
	for citizen_id: String in _original_citizens:
		CitizenManager.citizens_by_id[citizen_id] = _original_citizens[citizen_id]
	get_tree().paused = _original_tree_paused


func _free_test_nodes() -> void:
	if is_instance_valid(_display_player):
		_display_player.free()
	for node: Node in _test_nodes:
		if is_instance_valid(node):
			node.free()
