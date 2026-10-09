class_name WallWorldIndicator extends Node2D

@onready var progress_bar: ProgressBar = $ProgressBar

var raid_state: Node

func _ready() -> void:
	visible = false

func _exit_tree() -> void:
	_unbind_state()

func bind_state(next_state: Node) -> void:
	if raid_state == next_state:
		refresh()
		return
	_unbind_state()
	raid_state = next_state
	if is_instance_valid(raid_state) and raid_state.has_signal("changed"):
		var changed_callable: Callable = Callable(self, "_on_state_changed")
		if not raid_state.is_connected("changed", changed_callable):
			raid_state.connect("changed", changed_callable)
	refresh()

func refresh() -> void:
	if not is_instance_valid(raid_state) or not raid_state.has_method("get_status"):
		visible = false
		return
	var status_value: Variant = raid_state.call("get_status")
	if not status_value is Dictionary:
		visible = false
		return
	var status: Dictionary = status_value
	var phase: String = str(status.get("phase", ""))
	if phase in ["attacking", "looting"]:
		_render_wall_hp(status)
		visible = true
		return
	var work_kind: String = str(status.get("work_kind", ""))
	if work_kind.is_empty():
		visible = false
		return
	_render_work_progress(status)
	visible = true

func _render_wall_hp(status: Dictionary) -> void:
	var hp: int = int(status.get("hp", 0))
	var max_hp: int = maxi(int(status.get("max_hp", 0)), 1)
	progress_bar.max_value = float(max_hp)
	progress_bar.value = float(clampi(hp, 0, max_hp))

func _render_work_progress(status: Dictionary) -> void:
	var total_minutes: int = maxi(int(status.get("work_total", 0)), 1)
	var remaining_minutes: int = clampi(int(status.get("work_remaining", 0)), 0, total_minutes)
	var completed_minutes: int = total_minutes - remaining_minutes
	progress_bar.max_value = float(total_minutes)
	progress_bar.value = float(completed_minutes)

func _unbind_state() -> void:
	if not is_instance_valid(raid_state):
		raid_state = null
		return
	if raid_state.has_signal("changed"):
		var changed_callable: Callable = Callable(self, "_on_state_changed")
		if raid_state.is_connected("changed", changed_callable):
			raid_state.disconnect("changed", changed_callable)
	raid_state = null

func _on_state_changed() -> void:
	refresh()
