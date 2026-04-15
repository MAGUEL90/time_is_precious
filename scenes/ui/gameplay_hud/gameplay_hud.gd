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
	_on_time_changed(
		TimeComponentManager.current_day, 
		TimeComponentManager.current_hour, 
		int(TimeComponentManager.current_minute), 
		TimeComponentManager.current_weather)

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

	label_alert_body.text = "FTG: %d%%, HGR: %d%%, FCS: %d%%" % [
		player_ref.get_fatigue_percent(),
		player_ref.get_hunger_percent(),
		player_ref.get_focus_percent()
	]
