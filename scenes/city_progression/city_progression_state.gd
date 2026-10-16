extends Node

## Session-only city progress, settled from completed daily needs, never stock previews.
signal changed

const DAILY_BONUS: int = 5
const MISSING_WALL_PENALTY: int = 5
const BREACH_PENALTY: int = 10
const SATISFACTION_THRESHOLD: float = 0.70
const LEVEL_TARGET: int = 100

var level: int = 1
var progress: int = 0
var last_daily: Dictionary = {}
var last_event: String = ""
var last_awarded_day: int = -1
var _last_breach_id: int = 0
var raid_state: Node

func _ready() -> void:
	# Joining the runtime never retroactively awards an already-settled day.
	last_awarded_day = TimeComponentManager.current_day
	CitizenNeedsManager.needs_changed.connect(_on_needs_changed)

func bind_raid(next_raid: Node) -> void:
	if raid_state == next_raid:
		return
	if is_instance_valid(raid_state) and raid_state.wall_breached.is_connected(_on_wall_breached):
		raid_state.wall_breached.disconnect(_on_wall_breached)
	raid_state = next_raid
	if is_instance_valid(raid_state):
		_last_breach_id = int(raid_state.get_last_report().get("id", 0))
		raid_state.wall_breached.connect(_on_wall_breached)
		raid_state.set_city_threat_stage(get_threat_stage())

func get_threat_stage() -> StringName:
	return &"early" if level == 1 else &"developing" if level == 2 else &"advanced"

func _on_needs_changed() -> void:
	var day: int = CitizenNeedsManager.last_processed_day
	if day <= last_awarded_day or not is_instance_valid(raid_state):
		return
	var residents: Array[Dictionary] = []
	for citizen: CitizenData in CitizenManager.get_all_residents():
		var result: Dictionary = CitizenNeedsManager.last_needs_results.get(citizen.citizen_id, {})
		# Applications can add residents after settlement; they join tomorrow's cohort.
		if int(result.get("day", -1)) == day and bool(result.get("evaluated", false)):
			residents.append(result)
	settle_day(day, residents, int(raid_state.wall_hp) > 0)

func settle_day(day: int, residents: Array[Dictionary], wall_standing: bool) -> bool:
	if day <= last_awarded_day:
		return false
	# Latch before emitting; UI refreshes and stock updates cannot settle twice.
	last_awarded_day = day
	var fed: bool = not residents.is_empty()
	var clothed: bool = fed
	var satisfaction: float = 0.0
	for result: Dictionary in residents:
		fed = fed and bool(result.get("food", false))
		clothed = clothed and bool(result.get("clothing", false))
		satisfaction += float(result.get("satisfaction", 0.0))
	if not residents.is_empty():
		satisfaction /= residents.size()
	last_daily = {
		"day": day,
		"food": DAILY_BONUS if fed else 0,
		"clothing": DAILY_BONUS if clothed else 0,
		"satisfaction": DAILY_BONUS if not residents.is_empty() and satisfaction >= SATISFACTION_THRESHOLD else 0,
		"wall": 0 if wall_standing else -MISSING_WALL_PENALTY,
	}
	last_daily.total = int(last_daily.food) + int(last_daily.clothing) + int(last_daily.satisfaction) + int(last_daily.wall)
	var before: int = progress
	progress = clampi(progress + int(last_daily.total), 0, LEVEL_TARGET)
	last_daily.applied = progress - before
	last_event = ""
	changed.emit()
	return true

func _on_wall_breached(raid_id: int) -> void:
	if raid_id <= _last_breach_id:
		return
	_last_breach_id = raid_id
	progress = maxi(0, progress - BREACH_PENALTY)
	last_event = "Wall breached: -10"
	changed.emit()

func request_level_up() -> bool:
	if progress < LEVEL_TARGET or not is_instance_valid(raid_state):
		return false
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	level += 1
	progress = 0
	last_event = "City level increased"
	# RaidState snapshots each departing party. Only the next departure changes.
	raid_state.set_city_threat_stage(get_threat_stage())
	changed.emit()
	return true
