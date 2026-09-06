class_name WorkProgressEntry extends NinePatchRect

const WORKER_ICON_ACTIVE: Texture2D = preload(
	"res://assets/ui/ui_icon/worker_icon_active_ver_2.png"
)
const WORKER_ICON_INACTIVE: Texture2D = preload(
	"res://assets/ui/ui_icon/worker_icon_inactive_ver_2.png"
)

@onready var job_icon: TextureRect = $EntryMargin/BodyRow/IconFrame/JobIcon
@onready var job_label: Label = $EntryMargin/BodyRow/EntryVBox/HeaderRow/JobLabel
@onready var percent_label: Label = $EntryMargin/BodyRow/EntryVBox/ProgressRow/PercentLabel
@onready var status_label: Label = $EntryMargin/BodyRow/EntryVBox/StatusRow/StatusLabel
@onready var context_label: Label = $EntryMargin/BodyRow/EntryVBox/StatusRow/ContextLabel
@onready var eta_label: Label = $EntryMargin/BodyRow/EntryVBox/StatusRow/EtaLabel
@onready var progress_bar: TextureProgressBar = $EntryMargin/BodyRow/EntryVBox/ProgressRow/ProgressBar
@onready var worker_slot_icons: Array[TextureRect] = [
	$EntryMargin/BodyRow/EntryVBox/HeaderRow/WorkerSummary/WorkerIcons/WorkerSlot1,
	$EntryMargin/BodyRow/EntryVBox/HeaderRow/WorkerSummary/WorkerIcons/WorkerSlot2
	]
@onready var worker_count_label: Label = $EntryMargin/BodyRow/EntryVBox/HeaderRow/WorkerSummary/WorkerCountLabel

@onready var input_item_icons: Array[TextureRect] = [
	$EntryMargin/BodyRow/EntryVBox/RecipeRow/InputIcon1,
	$EntryMargin/BodyRow/EntryVBox/RecipeRow/InputIcon2,
	$EntryMargin/BodyRow/EntryVBox/RecipeRow/InputIcon3
]

@onready var input_plus_icons: Array[TextureRect] = [
	$EntryMargin/BodyRow/EntryVBox/RecipeRow/PlusIcon1,
	$EntryMargin/BodyRow/EntryVBox/RecipeRow/PlusIcon2
]

@onready var recipe_arrow_icon: TextureRect = ($EntryMargin/BodyRow/EntryVBox/RecipeRow/ArrowIcon)
@onready var output_item_icon: TextureRect = ($EntryMargin/BodyRow/EntryVBox/RecipeRow/OutputIcon1)
@onready var worker_icons_container: HBoxContainer = ($EntryMargin/BodyRow/EntryVBox/HeaderRow/WorkerSummary/WorkerIcons)

func setup(progress_data: Dictionary) -> void:
	job_label.text = str(progress_data.get("title", "Unknown Work"))
	var icon_value: Variant = progress_data.get("job_icon")
	if icon_value is Texture2D:
		job_icon.texture = icon_value as Texture2D
	else:
		job_icon.texture = null

	var source: String = str(progress_data.get("source", "work"))
	if source == "process":
		_update_process_summary(progress_data)
	else:
		_update_worker_summary(progress_data)

	_update_recipe(progress_data)

	var progress_ratio: float = clampf(float(progress_data.get("progress_ratio", 0.0)), 0.0, 1.0)
	progress_bar.value = progress_ratio
	percent_label.text = "%d%%" % roundi(progress_ratio * 100.0)
	var status_text: String = str(progress_data.get("status_text", "Working"))
	if source == "process":
		var station_name: String = str(progress_data.get("station_id", "")).capitalize()
		if station_name.is_empty():
			station_name = "Station"
		var total_quantity: int = int (progress_data.get("total_quantity", 0))
		status_label.text = "%s x%d" % [status_text, total_quantity]
		context_label.text = station_name
	else:
		var worker_id: String = str(progress_data.get("worker_id", ""))
		status_label.text = status_text
		context_label.text = _resolve_worker_name(worker_id)

	var remaining_minutes: int = int(
		progress_data.get("remaining_minutes", 0)
	)
	eta_label.text = "ETA %s" % _format_duration(remaining_minutes)


func _update_recipe(progress_data: Dictionary) -> void:
	var inputs: Dictionary = progress_data.get("inputs", {})
	var outputs: Dictionary = progress_data.get("outputs", {})

	var input_ids: Array[String] = _get_positive_item_ids(inputs)
	var output_ids: Array[String] = _get_positive_item_ids(outputs)

	for icon_index in range(input_item_icons.size()):
		var icon_node: TextureRect = input_item_icons[icon_index]
		icon_node.visible = icon_index < input_ids.size()

		if icon_node.visible:
			icon_node.texture = _get_item_icon(
				input_ids[icon_index]
			)
	var visible_plus_count: int = mini(
		maxi(input_ids.size() - 1, 0),
		input_plus_icons.size()
	)
	for plus_index in range(input_plus_icons.size()):
		input_plus_icons[plus_index].visible = (
			plus_index < visible_plus_count
		)
	var has_output: bool = not output_ids.is_empty()
	recipe_arrow_icon.visible = (
		not input_ids.is_empty()
		and has_output
	)
	output_item_icon.visible = has_output

	if has_output:
		output_item_icon.texture = _get_item_icon(
			output_ids[0]
		)

func _get_positive_item_ids(items: Dictionary) -> Array[String]:
	var item_ids: Array[String] = []

	for item_id_value in items.keys():
		if int(items[item_id_value]) <= 0:
			continue

		var item_id: String = str(item_id_value)
		if not item_id.is_empty():
			item_ids.append(item_id)

	return item_ids

func _get_item_icon(item_id: String) -> Texture2D:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)

	if item_data == null:
		return null

	return item_data.icon

func _update_process_summary(progress_data: Dictionary) -> void:
	worker_icons_container.hide()
	var slot_capacity: int = maxi(int(progress_data.get("process_slot_capacity", 0)), 0)
	var active_slot_count: int = clampi(int(progress_data.get("active_process_slot_count", 0)), 0, slot_capacity)

	worker_count_label.text = "Active %d/%d" % [active_slot_count, slot_capacity]

func _update_worker_summary(progress_data: Dictionary) -> void:
	worker_icons_container.show()

	var slot_capacity: int = clampi(
		int(progress_data.get("worker_slot_capacity", 1)),
		1,
		worker_slot_icons.size()
	)
	var active_worker_count: int = clampi(
		int(progress_data.get("active_worker_count", 0)),
		0,
		slot_capacity
	)
	worker_count_label.text = "%d/%d" % [
		active_worker_count,
		slot_capacity
	]
	for slot_index in range(worker_slot_icons.size()):
		var slot_icon: TextureRect = worker_slot_icons[slot_index]
		slot_icon.visible = slot_index < slot_capacity
		slot_icon.texture = (
			WORKER_ICON_ACTIVE
			if slot_index < active_worker_count
			else WORKER_ICON_INACTIVE
		)

func _resolve_worker_name(worker_id: String) -> String:
	if worker_id.is_empty():
		return "Unassigned"

	var worker_data: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	if worker_data == null:
		return worker_id

	var display_name: String = worker_data.get_resolved_display_name()
	return display_name if not display_name.is_empty() else worker_id

func _format_duration(total_minutes: int) -> String:
	var safe_minutes: int = maxi(total_minutes, 0)

	if safe_minutes < 60:
		return "%dm" % safe_minutes

	var hours: int = floori(float(safe_minutes) / 60.0)
	var minutes: int = safe_minutes % 60

	if minutes == 0:
		return "%dh" % hours

	return "%dh %dm" % [hours, minutes]
