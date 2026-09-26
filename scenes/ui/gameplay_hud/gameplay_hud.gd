class_name GameplayHUD extends CanvasLayer

const QUICK_SLOT_ACTION: Array[String] = [
	"quick_slot_1",
	"quick_slot_2",
	"quick_slot_3",
	"quick_slot_4",
	"quick_slot_5"
]

@onready var label_day: Label = $Root/MarginContainer/TopLayer/TopLeftPanel/MarginContainer/VBoxContainer/LabelDay
@onready var label_time: Label = $Root/MarginContainer/TopLayer/TopLeftPanel/MarginContainer/VBoxContainer/LabelTime
@onready var label_weather: Label = $Root/MarginContainer/TopLayer/TopLeftPanel/MarginContainer/VBoxContainer/LabelWeather

@onready var shortcut_bag: Button = $Root/MarginContainer/BottomLayer/BottomMenuPanel/MarginContainer/HBoxContainer/ShortcutBag
@onready var quick_consumable_tray: PanelContainer = $Root/MarginContainer/BottomLayer/QuickConsumableTray
@onready var consumable_tray_hide_timer: Timer = $ConsumableTrayHideTimer
@onready var consumable_slots_container: HBoxContainer = $Root/MarginContainer/BottomLayer/QuickConsumableTray/MarginContainer/ConsumableSlotsContainer

@onready var label_alert_title: Label = $Root/MarginContainer/TopLayer/TopRightPanel/MarginContainer/VBoxContainer/LabelAlertTitle
@onready var label_alert_body: Label = $Root/MarginContainer/TopLayer/TopRightPanel/MarginContainer/VBoxContainer/LabelAlertBody

var is_mouse_over_bag: bool = false
var is_mouse_over_consumable_tray: bool = false
var is_ui_blocking_quick_slots: bool = false
var consumable_slots: Array[Button] = []
var quick_slot_item_ids: Array[String] = []
var player_ref: Player



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	player_ref = get_tree().get_first_node_in_group("player")

	_cache_consumable_slots()
	_connect_consumable_slots()

	quick_consumable_tray.visible = false

	TimeComponentManager.time_changed.connect(_on_time_changed)
	_connect_food_refresh_signals()
	_on_time_changed(
		TimeComponentManager.current_day, 
		TimeComponentManager.current_hour, 
		int(TimeComponentManager.current_minute), 
		TimeComponentManager.current_weather)

func _exit_tree() -> void:
	var citizen_manager: Node = get_node_or_null("/root/CitizenManager")
	if is_instance_valid(citizen_manager) and citizen_manager.has_signal("citizen_added") and citizen_manager.is_connected("citizen_added", _on_citizen_added):
		citizen_manager.disconnect("citizen_added", _on_citizen_added)

func _connect_food_refresh_signals() -> void:
	var citizen_manager: Node = get_node_or_null("/root/CitizenManager")
	if is_instance_valid(citizen_manager) and citizen_manager.has_signal("citizen_added") and not citizen_manager.is_connected("citizen_added", _on_citizen_added):
		citizen_manager.connect("citizen_added", _on_citizen_added)

func _on_citizen_added(_citizen: Variant) -> void:
	_refresh_player_status()

func _process(_delta: float) -> void:
	if quick_consumable_tray.visible:
		_update_consumable_hover_state()

func _unhandled_input(event: InputEvent) -> void:
	for i in range(QUICK_SLOT_ACTION.size()):
		if event.is_action_pressed(QUICK_SLOT_ACTION[i]):
			use_consumable_slot(i)
			break

func _on_time_changed(day:int, hour:int, minute:int, weather: String) -> void:
	label_day.text = "Day: %02d " % [day]
	label_time.text = "Hour: %02d Minute: %02d " % [hour, minute]
	label_weather.text = "Weather: %s" % [weather]

	_refresh_player_status()

func _on_shortcut_bag_mouse_entered() -> void:
	show_consumable_tray()

func _on_shortcut_bag_mouse_exited() -> void:
	_update_consumable_hover_state()

func show_consumable_tray() -> void:
	quick_consumable_tray.visible = true
	_update_consumable_hover_state()
	
func _on_consumable_tray_hide_timer_timeout() -> void:
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	
	is_mouse_over_bag = shortcut_bag.get_global_rect().has_point(mouse_position)
	is_mouse_over_consumable_tray = _is_mouse_over_tray_area(mouse_position)
	
	if not is_mouse_over_bag and not is_mouse_over_consumable_tray:
		quick_consumable_tray.visible = false
	
	
func _update_consumable_hover_state() -> void:
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	
	is_mouse_over_bag = shortcut_bag.get_global_rect().has_point(mouse_position)
	is_mouse_over_consumable_tray = _is_mouse_over_tray_area(mouse_position)
	
	if is_mouse_over_bag or is_mouse_over_consumable_tray:
		consumable_tray_hide_timer.stop()
	else:
		if consumable_tray_hide_timer.is_stopped():
			consumable_tray_hide_timer.start()
	# print("is_mouse_over_bag: ", is_mouse_over_bag, " and is_mouse_over_tray: ", is_mouse_over_consumable_tray)


func _is_mouse_over_tray_area(mouse_position: Vector2) -> bool:
	# check rect parent
	if quick_consumable_tray.get_global_rect().has_point(mouse_position):
		return true
	
	# cek semua button satu per satu
	for consumable_slot in consumable_slots_container.get_children():
		if consumable_slot is Control:
			if consumable_slot.get_global_rect().has_point(mouse_position):
				return true
		
	return false

func _cache_consumable_slots() -> void:
	consumable_slots.clear()
	
	for child in consumable_slots_container.get_children():
		if child is Button:
			consumable_slots.append(child)
	
func _connect_consumable_slots() -> void:
	for i in range(consumable_slots.size()):
		consumable_slots[i].pressed.connect(_on_consumable_slot_pressed.bind(i))

func _on_consumable_slot_pressed(slot_index: int) -> void:
	use_consumable_slot(slot_index)

func use_consumable_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= consumable_slots.size():
		return
		
	print("Use consumable slot %d" % (slot_index + 1)) 

func _refresh_player_status() -> void:
	if player_ref == null:
		player_ref = get_tree().get_first_node_in_group("player")

		if player_ref == null:
			return

	var food_summary: Dictionary = _get_food_supply_summary()
	var food_points: int = int(food_summary.get("points", 0))
	var food_daily_need: int = int(food_summary.get("daily_need", 0))
	var clothing_summary: Dictionary = _get_clothing_supply_summary()
	var status_lines: Array[String] = [
		"FTG: %d%%, HGR: %d%%, FCS: %d%%" % [
		player_ref.get_fatigue_percent(),
		player_ref.get_hunger_percent(),
		player_ref.get_focus_percent()],
		"Food: %d pt / %d/day (%s)" % [food_points, food_daily_need, _get_food_supply_status(food_summary)],
		_get_last_food_result_text(),
		_get_clothing_stock_text(clothing_summary),
		_get_clothing_coverage_text(clothing_summary),
		_get_last_clothing_result_text(clothing_summary),
		_get_shelter_capacity_status(),
		"SAT: %d%%" % roundi(CitizenNeedsManager.get_average_satisfaction() * 100.0),
	]
	label_alert_body.text = "\n".join(status_lines)

func _get_food_supply_status(summary: Dictionary) -> String:
	var points: int = int(summary.get("points", 0))
	var daily_need: int = int(summary.get("daily_need", 0))
	var consumer_count: int = int(summary.get("consumer_count", 0))
	var days_remaining: int = int(summary.get("days_remaining", -1))
	if consumer_count <= 0 or daily_need <= 0 or days_remaining < 0:
		return "No daily need"
	if points < daily_need:
		return "SHORTAGE"
	return "%d full day(s)" % days_remaining

func _get_last_food_result_text() -> String:
	return "Fed: %d / %d" % [CitizenNeedsManager.last_food_fulfilled_count, CitizenNeedsManager.get_food_consumer_count()]

func _get_food_supply_summary() -> Dictionary:
	var manager: Node = get_node_or_null("/root/CitizenNeedsManager")
	if not is_instance_valid(manager) or not manager.has_method("get_food_supply_summary"):
		return {}
	var result: Variant = manager.call("get_food_supply_summary")
	return result if result is Dictionary else {}

func _get_clothing_supply_summary() -> Dictionary:
	var manager: Node = get_node_or_null("/root/CitizenNeedsManager")
	if is_instance_valid(manager) and manager.has_method("get_clothing_supply_summary"):
		var result: Variant = manager.call("get_clothing_supply_summary")
		if result is Dictionary:
			return result
	return {}

func _get_clothing_stock_text(summary: Dictionary) -> String:
	if not summary.has("stock_items") or not summary.has("replacement_need"):
		return "Clothes stock: unavailable"
	return "Clothes: %d stock / %d due" % [int(summary.get("stock_items", 0)), int(summary.get("replacement_need", 0))]

func _get_clothing_coverage_text(summary: Dictionary) -> String:
	if not summary.has("covered_count") or not summary.has("consumer_count") or not summary.has("can_cover_all"):
		return "Clothing coverage: unavailable"
	var covered_count: int = int(summary.get("covered_count", 0))
	var consumer_count: int = int(summary.get("consumer_count", 0))
	var status: String = "NONE" if consumer_count <= 0 else ("OK" if bool(summary.get("can_cover_all", false)) else "SHORT")
	return "Coverage: %d/%d (%s)" % [covered_count, consumer_count, status]

func _get_last_clothing_result_text(summary: Dictionary) -> String:
	if not summary.has("consumer_count"):
		return "Last clothed: unavailable"
	return "Last clothed: %d/%d" % [CitizenNeedsManager.last_clothing_fulfilled_count, int(summary.get("consumer_count", 0))]

func _get_shelter_capacity_status() -> String:
	return "Shelter Capacity: %d, Need: %d" % [CityStockManager.shelter_capacity, CitizenNeedsManager.get_daily_shelter_capacity_need()]
