extends Node
## Shared source ledger: slots, optional refill, and independent RNG.
signal changed

var source_scene: String = ""
var source_config: Dictionary = {}
var active_view: WeakRef

var available: Array[bool] = []
var remaining_minutes: int = 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	TimeComponentManager.minute_changed.connect(_on_minute_changed)

func configure(capacity: int) -> void:
	if not available.is_empty():
		return
	available.resize(capacity)
	available.fill(true)

func collect(slot: int) -> void:
	if slot < 0 or slot >= available.size() or not available[slot]:
		return
	available[slot] = false
	if remaining_minutes == 0 and source_config.get("refill_enabled", true):
		remaining_minutes = _rng.randi_range(source_config.get("refill_min_hours", 1), source_config.get("refill_max_hours", 18)) * TimeComponentManager.minute_per_hour
	changed.emit()

func _on_minute_changed(_minute: int) -> void:
	if remaining_minutes <= 0:
		return
	remaining_minutes -= 1
	if remaining_minutes == 0:
		available.fill(true)
		changed.emit()

func debug_refill() -> bool:
	if not OS.is_debug_build():
		return false
	remaining_minutes = 0
	available.fill(true)
	changed.emit()
	return true
