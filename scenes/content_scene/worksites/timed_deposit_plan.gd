extends RefCounted

## Standalone deposit respawn state. This prototype is not attached to a
## worksite, settlement signal, or save state; its caller owns all integration.
## Call record_depletion_after_commit() only after a zero-stock result is final
## and can no longer be rolled back.

const MINUTES_PER_DAY: int = 1440
const MIN_RESPAWN_DELAY_MINUTES: int = 2 * MINUTES_PER_DAY
const MAX_RESPAWN_DELAY_MINUTES: int = 3 * MINUTES_PER_DAY
const SNAPSHOT_VERSION: int = 1
const MAX_VALID_MINUTE: int = 9223372036854775807 - MAX_RESPAWN_DELAY_MINUTES

var last_error: String = ""

var _initialized: bool = false
var _stock: int = 0
var _respawn_pending: bool = false
var _depleted_at_minute: int = -1
var _respawn_due_minute: int = -1


## Initialize from caller-owned worksite stock and capacity. Capacity is never
## stored or selected by this component; a later capacity change does not clamp
## existing stock.
func initialize_stock(initial_stock: Variant, capacity: Variant) -> bool:
	last_error = ""
	if _initialized:
		return _fail("Deposit plan is already initialized.")
	if not _is_positive_capacity(capacity):
		return _fail("Capacity must be a positive integer supplied by the caller.")
	if typeof(initial_stock) != TYPE_INT or int(initial_stock) < 1:
		return _fail("Initial stock must be a positive integer.")
	_stock = int(initial_stock)
	_respawn_pending = false
	_depleted_at_minute = -1
	_respawn_due_minute = -1
	_initialized = true
	return true


## Record a committed partial stock change. Existing stock may exceed a newly
## supplied capacity, so this method never clamps it. Zero must use
## record_depletion_after_commit(), which records the timer in the same call.
func update_remaining_stock_after_commit(new_stock: Variant, capacity: Variant) -> bool:
	last_error = ""
	if not _is_valid_state():
		return _fail("Deposit plan is not in a valid initialized state.")
	if not _is_positive_capacity(capacity):
		return _fail("Capacity must be a positive integer supplied by the caller.")
	if typeof(new_stock) != TYPE_INT or int(new_stock) < 1 or int(new_stock) > _stock:
		return _fail("Committed remaining stock must be a positive integer no greater than current stock.")
	if _respawn_pending:
		return _fail("Pending deposits can only gain stock through an approved refill.")
	_stock = int(new_stock)
	return true


## Call once the worksite's depletion has committed. The supplied RNG is the
## only randomness source. Repeated calls while pending are idempotent and do
## not reroll or consume the RNG.
func record_depletion_after_commit(current_minute: Variant, rng: Variant) -> bool:
	last_error = ""
	if not _is_valid_state():
		return _fail("Deposit plan is not in a valid initialized state.")
	if not _is_valid_minute(current_minute):
		return _fail("Current game minute must be a nonnegative integer within range.")
	if not (rng is RandomNumberGenerator):
		return _fail("A caller-owned RandomNumberGenerator is required.")
	if _respawn_pending:
		return true
	if int(current_minute) > MAX_VALID_MINUTE:
		return _fail("Current game minute cannot safely hold a respawn deadline.")
	var delay: int = rng.randi_range(MIN_RESPAWN_DELAY_MINUTES, MAX_RESPAWN_DELAY_MINUTES)
	_stock = 0
	_respawn_pending = true
	_depleted_at_minute = int(current_minute)
	_respawn_due_minute = int(current_minute) + delay
	return true


## Refill only after the due minute and only when the caller confirms the
## location/capacity is available. A successful call clears the timer, making
## subsequent calls no-ops until a later committed depletion.
func try_refill(current_minute: Variant, location_confirmed: Variant, capacity: Variant) -> bool:
	last_error = ""
	if not _is_valid_state():
		return _fail("Deposit plan is not in a valid initialized state.")
	if not _is_valid_minute(current_minute):
		return _fail("Current game minute must be a nonnegative integer within range.")
	if typeof(location_confirmed) != TYPE_BOOL:
		return _fail("Location confirmation must be a boolean supplied by the caller.")
	if not _is_positive_capacity(capacity):
		return _fail("Capacity must be a positive integer supplied by the caller.")
	if not _respawn_pending or not bool(location_confirmed) or int(current_minute) < _respawn_due_minute:
		return false
	_stock = int(capacity)
	_respawn_pending = false
	_depleted_at_minute = -1
	_respawn_due_minute = -1
	return true


func get_stock() -> int:
	return _stock


func is_respawn_pending() -> bool:
	return _respawn_pending


func get_depleted_at_minute() -> int:
	return _depleted_at_minute


func get_respawn_due_minute() -> int:
	return _respawn_due_minute


## Return a plain value dictionary for CitySaveValues.encode(). Integers are
## left as integers so the existing codec can tag them and preserve them.
func to_save_value() -> Dictionary:
	last_error = ""
	if not _is_valid_state():
		_fail("Deposit plan is not in a valid initialized state.")
		return {}
	var depleted_value: Variant = _depleted_at_minute if _respawn_pending else null
	var due_value: Variant = _respawn_due_minute if _respawn_pending else null
	return {
		"schema_version": SNAPSHOT_VERSION,
		"stock": _stock,
		"depleted_at_minute": depleted_value,
		"respawn_due_minute": due_value,
	}


## Restore a CitySaveValues-decoded value atomically. Legacy values may be a
## stock integer or a {"stock": n} record, optionally with the old Vector2
## deposit offset. A legacy zero has no known depletion time, so migration
## starts at checkpoint_minute and waits the conservative maximum of 3 days;
## this is deterministic and does not access either RNG. Positive legacy or
## current stock is preserved even if it exceeds today's supplied capacity;
## only a future refill adopts the current capacity.
func restore_from_save_value(snapshot: Variant, capacity: Variant, checkpoint_minute: Variant = null) -> bool:
	last_error = ""
	if not _is_positive_capacity(capacity):
		return _fail("Capacity must be a positive integer supplied by the caller.")
	if checkpoint_minute != null and not _is_valid_minute(checkpoint_minute):
		return _fail("Checkpoint minute must be null or a nonnegative integer within range.")

	var staged: Dictionary = {}
	if typeof(snapshot) == TYPE_INT:
		staged = _stage_legacy_stock(int(snapshot), checkpoint_minute)
	elif snapshot is Dictionary:
		if snapshot.has("schema_version"):
			staged = _stage_current_snapshot(snapshot)
		else:
			if not _has_exact_string_keys(snapshot, ["stock"]) and not _has_exact_string_keys(snapshot, ["stock", "offset"]):
				return _fail("Invalid legacy deposit snapshot fields.")
			if snapshot.has("offset"):
				var offset: Variant = snapshot["offset"]
				if typeof(offset) != TYPE_VECTOR2 or not is_finite(offset.x) or not is_finite(offset.y):
					return _fail("Legacy deposit offset must be a finite Vector2.")
			if typeof(snapshot["stock"]) != TYPE_INT:
				return _fail("Legacy deposit stock must be an integer.")
			staged = _stage_legacy_stock(int(snapshot["stock"]), checkpoint_minute)
	else:
		return _fail("Deposit snapshot must be a current dictionary or a supported legacy stock value.")
	if not bool(staged.get("ok", false)):
		return _fail(str(staged.get("error", "Invalid deposit snapshot.")))
	if checkpoint_minute != null and bool(staged.pending) and int(staged.depleted_at) > int(checkpoint_minute):
		return _fail("Deposit depletion cannot be later than its checkpoint.")

	# Commit only after every field and cross-field invariant has been checked.
	_stock = int(staged["stock"])
	_respawn_pending = bool(staged["pending"])
	_depleted_at_minute = int(staged["depleted_at"])
	_respawn_due_minute = int(staged["due"])
	_initialized = true
	return true


func _stage_current_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_string_keys(snapshot,
		["schema_version", "stock", "depleted_at_minute", "respawn_due_minute"]):
		return _invalid_stage("Invalid current deposit snapshot fields.")
	if typeof(snapshot["schema_version"]) != TYPE_INT or int(snapshot["schema_version"]) != SNAPSHOT_VERSION:
		return _invalid_stage("Unsupported deposit snapshot version.")
	if typeof(snapshot["stock"]) != TYPE_INT or int(snapshot["stock"]) < 0:
		return _invalid_stage("Current deposit stock must be a nonnegative integer.")
	var depleted: Variant = snapshot["depleted_at_minute"]
	var due: Variant = snapshot["respawn_due_minute"]
	if depleted == null and due == null:
		if int(snapshot["stock"]) == 0:
			return _invalid_stage("A current zero-stock snapshot requires its depletion schedule.")
		return _valid_stage(int(snapshot["stock"]), false, -1, -1)
	if typeof(depleted) != TYPE_INT or typeof(due) != TYPE_INT:
		return _invalid_stage("Current depletion timestamps must both be null or both be integers.")
	if int(snapshot["stock"]) != 0 or not _is_valid_minute(depleted) or not _is_valid_minute(due):
		return _invalid_stage("Pending respawn requires zero stock and valid nonnegative timestamps.")
	var delay: int = int(due) - int(depleted)
	if delay < MIN_RESPAWN_DELAY_MINUTES or delay > MAX_RESPAWN_DELAY_MINUTES:
		return _invalid_stage("Saved respawn delay is outside the approved 2-to-3-day interval.")
	return _valid_stage(0, true, int(depleted), int(due))


func _stage_legacy_stock(legacy_stock: int, checkpoint_minute: Variant) -> Dictionary:
	if legacy_stock < 0:
		return _invalid_stage("Legacy stock must be a nonnegative integer.")
	if legacy_stock > 0:
		return _valid_stage(legacy_stock, false, -1, -1)
	if checkpoint_minute == null or int(checkpoint_minute) > MAX_VALID_MINUTE:
		return _invalid_stage("Legacy zero stock requires a checkpoint minute that can hold a respawn deadline.")
	return _valid_stage(0, true, int(checkpoint_minute), int(checkpoint_minute) + MAX_RESPAWN_DELAY_MINUTES)


func _valid_stage(stock: int, pending: bool, depleted_at: int, due: int) -> Dictionary:
	return {"ok": true, "stock": stock, "pending": pending, "depleted_at": depleted_at, "due": due}


func _invalid_stage(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _is_valid_state() -> bool:
	if not _initialized:
		return false
	if _respawn_pending:
		if _stock != 0 or not _is_valid_minute(_depleted_at_minute) or not _is_valid_minute(_respawn_due_minute):
			return false
		var delay: int = _respawn_due_minute - _depleted_at_minute
		return delay >= MIN_RESPAWN_DELAY_MINUTES and delay <= MAX_RESPAWN_DELAY_MINUTES
	return _stock > 0 and _depleted_at_minute == -1 and _respawn_due_minute == -1


func _is_positive_capacity(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) > 0


func _is_valid_minute(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= 9223372036854775807


func _has_exact_string_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not expected.has(key):
			return false
	return true


func _fail(message: String) -> bool:
	last_error = message
	return false
