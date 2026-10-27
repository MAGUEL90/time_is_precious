extends NinePatchRect

signal selection_toggled(checked: bool)

const HAULER_ICON: Texture2D = preload("res://assets/ui/ui_icon/hauler_icon.png")
const LABORER_ICON: Texture2D = preload("res://assets/ui/ui_icon/laborer_icon.png")
const WORKER_ICON: Texture2D = preload("res://assets/ui/ui_icon/worker_portrait_icon.png")

@onready var details: Control = $Details
@onready var portrait: TextureRect = $Details/PortraitFrame/Portrait
@onready var name_label: Label = $Details/NameLabel
@onready var role_label: Label = $Details/RoleLabel
@onready var duty_label: Label = $Details/DutyLabel
@onready var satisfaction_heading: Label = $Details/SatisfactionHeading
@onready var mood_icon: TextureRect = $Details/MoodIcon
@onready var satisfaction_bar: TextureProgressBar = $Details/SatisfactionBar
@onready var satisfaction_label: Label = $Details/SatisfactionLabel
@onready var preview_label: Label = $Details/PreviewLabel
@onready var wage_label: Label = $Details/WageValue
@onready var selection_button: Button = $Details/SelectionButton
@onready var check_icon: TextureRect = $Details/SelectionButton/CheckIcon

var citizen_id: String = ""
var _snapshot: Array = []

func _ready() -> void:
	selection_button.toggled.connect(_on_toggled)
	details.resized.connect(_layout_card_rows)

func show_applicant(citizen: CitizenData, package_price: int, contract_days: int, profession_name: String) -> void:
	citizen_id = citizen.citizen_id
	var snapshot: Array = [citizen.display_name, citizen.profession, citizen.satisfaction, package_price, contract_days]
	if snapshot == _snapshot:
		return
	_snapshot = snapshot
	name_label.text = citizen.display_name
	role_label.text = "Job: " + profession_name
	duty_label.text = "Hauls worksite goods to assigned storage." if citizen.profession == WorkerData.Profession.HAULER else ""
	if citizen.profession == WorkerData.Profession.LABORER:
		duty_label.text = "Gathers resources and works at workshops."
	portrait.texture = HAULER_ICON if citizen.profession == WorkerData.Profession.HAULER else WORKER_ICON
	if citizen.profession == WorkerData.Profession.LABORER:
		portrait.texture = LABORER_ICON
	var frame: Control = portrait.get_parent()
	if portrait.texture == HAULER_ICON or portrait.texture == LABORER_ICON:
		var used: Rect2i = portrait.texture.get_image().get_used_rect()
		portrait.position = (frame.size * 0.5 - Vector2(used.position) - Vector2(used.size) * 0.5).round()
	else:
		portrait.position = ((frame.size - portrait.size) * 0.5).round()
	satisfaction_bar.value = citizen.satisfaction * 100.0
	satisfaction_label.text = "%d%%" % roundi(citizen.satisfaction * 100.0)
	# The baseline has no mood-to-icon thresholds; keep the existing neutral art.
	mood_icon.tooltip_text = "Satisfaction: %d%%. Neutral icon is illustrative." % roundi(citizen.satisfaction * 100.0)
	wage_label.text = "%d / %dd" % [package_price, contract_days] if package_price > 0 else "Unavailable"
	_layout_card_rows()

func _layout_card_rows() -> void:
	# Align the role to the checkbox; long names use the remaining measured space.
	var role_width: float = ceilf(role_label.get_theme_font("font").get_string_size(role_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, role_label.get_theme_font_size("font_size")).x)
	var name_width: float = ceilf(name_label.get_theme_font("font").get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x)
	role_label.position.x = selection_button.position.x - 6.0 - role_width
	var available: float = role_label.position.x - 6.0 - name_label.position.x
	name_label.size.x = minf(name_width, maxf(available, 0.0))
	role_label.size.x = role_width
	_layout_status_row()

func _layout_status_row() -> void:
	# Center measured text and the existing native-size icon/bar controls together.
	var row: Array[Control] = [satisfaction_heading, mood_icon, satisfaction_bar, $Details/WageHeading, $Details/ShekelIcon, wage_label]
	var gaps: Array[float] = [3.0, 4.0, 8.0, 3.0, 3.0]
	var widths: Array[float] = []
	var total: float = 0.0
	for control: Control in row:
		var width: float = control.size.x
		if control is Label:
			width = ceilf(control.get_theme_font("font").get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x)
			control.size.x = width
		widths.append(width)
		total += width
	for gap: float in gaps:
		total += gap
	var cursor: float = roundf((details.size.x - total) * 0.5)
	for index: int in range(row.size()):
		row[index].position.x = cursor
		cursor += widths[index] + (gaps[index] if index < gaps.size() else 0.0)

func set_selected(checked: bool) -> void:
	selection_button.set_pressed_no_signal(checked)
	check_icon.visible = checked
	selection_button.tooltip_text = ("Deselect " if checked else "Select ") + name_label.text

func _on_toggled(checked: bool) -> void:
	selection_toggled.emit(checked)
