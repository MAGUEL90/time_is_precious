extends CanvasLayer
class_name CitizenInspectionPanel

signal closed
signal renew_requested(person_id: String)
signal actions_requested(person_id: String)

const UNKNOWN_TEXT: String = "Unknown"
const COLOR_NEED_MISSING: Color = Color(1.0, 0.77, 0.64)
const COLOR_NEED_UNKNOWN: Color = Color(1.0, 0.94, 0.82)

var summary_provider: Callable = Callable()
## Kept for existing scene hosts; this card now presents needs only.
var worker_details_provider: Callable = Callable()
var selected_id: String = ""

@onready var _root: Control = $Root
@onready var _name_label: Label = $Root/Frame/Margin/Contents/NameRow/NameLabel
@onready var _body_scroll: ScrollContainer = $Root/Frame/Margin/Contents/BodyScroll
@onready var _food_status: VBoxContainer = $Root/Frame/Margin/Contents/BodyScroll/Body/DailyNeedsRow/FoodStatus
@onready var _clothing_status: VBoxContainer = $Root/Frame/Margin/Contents/BodyScroll/Body/DailyNeedsRow/ClothingStatus
@onready var _shelter_status: VBoxContainer = $Root/Frame/Margin/Contents/BodyScroll/Body/DailyNeedsRow/ShelterStatus
@onready var _satisfaction_label: Label = $Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionLabel
@onready var _satisfaction_bar: TextureProgressBar = $Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionBar
@onready var _close_button: TextureButton = $Root/Frame/Margin/Contents/NameRow/CloseButton
@onready var _refresh_timer: Timer = $RefreshTimer

func _ready() -> void:
	# K pauses the tree while showing this same panel. The panel and its timer
	# must continue to process without taking ownership of that pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(close)
	_refresh_timer.timeout.connect(_refresh_view)
	visible = false

func open_for(person_id: String) -> void:
	selected_id = person_id.strip_edges()
	_body_scroll.scroll_vertical = 0
	if selected_id.is_empty():
		close()
		return

	visible = true
	_refresh_view()
	if visible:
		_refresh_timer.start(0.2)

## Used by modal hosts such as the worker hub; map inspection does not call it.
func focus_primary() -> void:
	if visible and is_instance_valid(_close_button):
		_close_button.grab_focus()

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
	_name_label.accessibility_name = _name_label.text
	_refresh_needs(summary)
	_refresh_satisfaction(summary)

func _refresh_needs(summary: Dictionary) -> void:
	var evaluated: bool = bool(summary.get("evaluated", false))
	if not evaluated:
		_set_need_status(_food_status, "Food", null)
		_set_need_status(_clothing_status, "Clothing", null)
		_set_need_status(_shelter_status, "Shelter", null)
		return

	_set_need_status(_food_status, "Food", bool(summary.get("food", false)))
	_set_need_status(_clothing_status, "Clothing", bool(summary.get("clothing", false)))
	_set_need_status(_shelter_status, "Shelter", bool(summary.get("shelter", false)))

func _refresh_satisfaction(summary: Dictionary) -> void:
	var value: Variant = summary.get("satisfaction", null)
	if (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0:
		var percent: int = roundi(float(value) * 100.0)
		var percent_text: String = "<1%" if float(value) > 0.0 and percent == 0 else "%d%%" % percent
		_satisfaction_label.text = "Actual satisfaction: %s" % percent_text
		_satisfaction_bar.value = float(value) * 100.0
	else:
		_satisfaction_label.text = "Actual satisfaction: %s" % UNKNOWN_TEXT
		_satisfaction_bar.value = 0.0

func _safe_name(value: Variant) -> String:
	var person_name: String = str(value).strip_edges()
	return person_name if not person_name.is_empty() else "Citizen"

func _set_need_status(card: VBoxContainer, need_name: String, is_met: Variant) -> void:
	var met: bool = is_met != null and bool(is_met)
	var status_text: String = UNKNOWN_TEXT if is_met == null else ("Met" if met else "Missing")
	var status_label: Label = card.get_node("Status/Label") as Label
	var check_icon: TextureRect = card.get_node("Status/MetIcon") as TextureRect
	status_label.text = status_text
	status_label.visible = not met
	status_label.add_theme_color_override("font_color", COLOR_NEED_UNKNOWN if is_met == null else COLOR_NEED_MISSING)
	check_icon.visible = met
	# Accessibility conveys the word represented by the icon.
	var description: String = "%s: %s" % [need_name, status_text]
	card.accessibility_name = description
	card.get_node("Icon").accessibility_name = description
	status_label.accessibility_name = description
	check_icon.accessibility_name = description
