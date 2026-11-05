extends CanvasLayer
class_name CitizenInspectionPanel

signal closed

const UNKNOWN_TEXT: String = "Unknown"
const COLOR_NEED_MET: Color = Color(0.86, 1.0, 0.72)
const COLOR_NEED_MISSING: Color = Color(1.0, 0.77, 0.64)
const COLOR_NEED_UNKNOWN: Color = Color(1.0, 0.94, 0.82)
const COLOR_TREND_DOWN: Color = Color(1.0, 0.77, 0.64)
const COLOR_TREND_UP: Color = Color(0.86, 1.0, 0.72)
const COLOR_TREND_STABLE: Color = Color(1.0, 0.91, 0.68)

var summary_provider: Callable = Callable()
var selected_id: String = ""

@onready var _root: Control = $Root
@onready var _name_label: Label = $Root/Frame/Margin/Contents/NameRow/NameLabel
@onready var _daily_check_label: Label = $Root/Frame/Margin/Contents/DailyCheckLabel
@onready var _food_status_label: Label = $Root/Frame/Margin/Contents/DailyNeedsRow/FoodStatus/Label
@onready var _clothing_status_label: Label = $Root/Frame/Margin/Contents/DailyNeedsRow/ClothingStatus/Label
@onready var _shelter_status_label: Label = $Root/Frame/Margin/Contents/DailyNeedsRow/ShelterStatus/Label
@onready var _clothing_days_label: Label = $Root/Frame/Margin/Contents/ClothingDaysLabel
@onready var _satisfaction_label: Label = $Root/Frame/Margin/Contents/SatisfactionLabel
@onready var _condition_label: Label = $Root/Frame/Margin/Contents/ConditionLabel
@onready var _food_stock_label: Label = $Root/Frame/Margin/Contents/CityStockRow/FoodStock/Label
@onready var _clothing_stock_label: Label = $Root/Frame/Margin/Contents/CityStockRow/ClothingStock/Label
@onready var _shelter_stock_label: Label = $Root/Frame/Margin/Contents/CityStockRow/ShelterStock/Label
@onready var _close_button: TextureButton = $Root/Frame/Margin/Contents/NameRow/CloseButton
@onready var _refresh_timer: Timer = $RefreshTimer

func _ready() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_button.pressed.connect(close)
	_refresh_timer.timeout.connect(_refresh_view)
	visible = false

func open_for(person_id: String) -> void:
	selected_id = person_id.strip_edges()
	if selected_id.is_empty():
		close()
		return

	visible = true
	_refresh_view()
	if visible:
		_refresh_timer.start(0.2)

func close() -> void:
	var was_open: bool = visible or not selected_id.is_empty()
	selected_id = ""
	_refresh_timer.stop()
	visible = false
	if was_open:
		closed.emit()

func _refresh_view() -> void:
	if not visible or selected_id.is_empty():
		return
	if not summary_provider.is_valid():
		close()
		return

	var summary_value: Variant = summary_provider.call(selected_id)
	if not summary_value is Dictionary:
		close()
		return

	var summary: Dictionary = summary_value
	if summary.is_empty():
		close()
		return
	_name_label.text = _safe_name(summary.get("name", ""))
	_refresh_daily_check(summary)
	_refresh_satisfaction(summary)
	_refresh_condition(summary)
	_refresh_city_stock(summary)

func _refresh_daily_check(summary: Dictionary) -> void:
	var evaluated: bool = bool(summary.get("evaluated", false))
	if not evaluated:
		_daily_check_label.text = "LAST DAILY CHECK · NOT EVALUATED"
		_set_need_status(_food_status_label, "Food", null)
		_set_need_status(_clothing_status_label, "Clothing", null)
		_set_need_status(_shelter_status_label, "Shelter", null)
		_clothing_days_label.text = "Clothing days left: %s" % UNKNOWN_TEXT
		return

	_daily_check_label.text = "LAST DAILY CHECK · DAY %d" % int(summary.get("day", 0))
	_set_need_status(_food_status_label, "Food", bool(summary.get("food", false)))
	_set_need_status(_clothing_status_label, "Clothing", bool(summary.get("clothing", false)))
	_set_need_status(_shelter_status_label, "Shelter", bool(summary.get("shelter", false)))
	var clothing_days_left: int = int(summary.get("clothing_days_left", 0))
	_clothing_days_label.text = "Clothing days left: %d" % maxi(0, clothing_days_left)

func _refresh_satisfaction(summary: Dictionary) -> void:
	var satisfaction: float = clampf(float(summary.get("satisfaction", 0.0)), 0.0, 1.0)
	_satisfaction_label.text = "Actual satisfaction: %d%%" % roundi(satisfaction * 100.0)

func _refresh_condition(summary: Dictionary) -> void:
	var evaluated: bool = bool(summary.get("evaluated", false))
	var condition: float = float(summary.get("condition_target", -1.0))
	if not evaluated or not is_finite(condition) or condition < 0.0:
		_condition_label.text = "Condition (daily): %s" % UNKNOWN_TEXT
		_condition_label.add_theme_color_override("font_color", COLOR_NEED_UNKNOWN)
		return

	var trend: String = _trend_text(str(summary.get("trend", "unknown")))
	_condition_label.text = "Condition (daily): %d%% · %s" % [roundi(clampf(condition, 0.0, 1.0) * 100.0), trend]
	_condition_label.add_theme_color_override("font_color", _trend_color(trend))

func _refresh_city_stock(summary: Dictionary) -> void:
	_food_stock_label.text = "%d pts" % maxi(0, int(summary.get("food_stock", 0)))
	_clothing_stock_label.text = "%d units" % maxi(0, int(summary.get("clothing_stock", 0)))
	_shelter_stock_label.text = "%d capacity" % maxi(0, int(summary.get("shelter_capacity", 0)))

func _safe_name(value: Variant) -> String:
	var person_name: String = str(value).strip_edges()
	return person_name if not person_name.is_empty() else "Citizen"

func _set_need_status(label: Label, need_name: String, is_met: Variant) -> void:
	if is_met == null:
		label.text = "%s: %s" % [need_name, UNKNOWN_TEXT]
		label.add_theme_color_override("font_color", COLOR_NEED_UNKNOWN)
		return
	var status_text: String = "Met" if bool(is_met) else "Missing"
	label.text = "%s: %s" % [need_name, status_text]
	label.add_theme_color_override("font_color", COLOR_NEED_MET if bool(is_met) else COLOR_NEED_MISSING)

func _trend_color(trend: String) -> Color:
	match trend:
		"Up":
			return COLOR_TREND_UP
		"Down":
			return COLOR_TREND_DOWN
		"Stable":
			return COLOR_TREND_STABLE
		_:
			return COLOR_NEED_UNKNOWN

func _trend_text(trend: String) -> String:
	match trend.to_lower():
		"up":
			return "Up"
		"down":
			return "Down"
		"stable":
			return "Stable"
		_:
			return UNKNOWN_TEXT
