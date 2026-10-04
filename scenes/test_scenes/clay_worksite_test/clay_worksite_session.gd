extends RefCounted

# Approved test balance, deliberately local to the playable fixture.
const MINUTES_PER_CLAY: int = 10
const INITIAL_STOCK: int = 72
const DURATIONS: Array[int] = [180, 360, 540]
const WORKER_CAPACITY: int = 2 # Small worksite; Player occupies one slot.
const ITEM_ID: String = "clay_lump"

# Defaults retain the existing Clay Site contract; authored markers may override.
var item_id: String = ITEM_ID
var minutes_per_unit: float = MINUTES_PER_CLAY
var daily_stock_min: int = -1
var daily_stock_max: int = -1
var stock: int = INITIAL_STOCK
var working: bool = false
var participants: Array[String] = []
var reserved_slots: Callable
var last_result: Dictionary = {}
var _plan: Dictionary = {}
var _result: Dictionary = {}
var _drop_output: Callable
var _cancelled: bool = false
var _settling: bool = false
var _productive_minutes: float = 0.0

func toggle_participant(id: String) -> bool:
	if working or id != "player":
		return false
	if participants.has(id):
		participants.erase(id)
		return true
	if participants.size() >= WORKER_CAPACITY or not participant_unavailable_reason(id).is_empty():
		return false
	participants.append(id)
	return true

func participant_unavailable_reason(id: String) -> String:
	if id == "player":
		return ""
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null:
		return "Unavailable"
	if worker.is_reserved():
		return "Working"
	var citizen: CitizenData = worker.get_linked_citizen()
	if citizen != null and not citizen.can_be_assigned():
		return "Unavailable"
	return ""

func preview(requested_minutes: int, player: Player) -> Dictionary:
	var clay: ItemData = ItemDatabase.get_item_data(item_id)
	var capacity: int = 0
	if clay != null and clay.weight > 0.0:
		capacity = maxi(int(floor(Inventory.get_remaining_capacity() / clay.weight)), 0)
	var count: int = participants.size()
	var forecast: Dictionary = _forecast(requested_minutes, player)
	var units: int = int(forecast.units) if count > 0 else 0
	var minutes: int = int(forecast.minutes) if count > 0 else 0
	var includes_player: bool = participants.has("player")
	var reason: String = ""
	if participants.is_empty():
		reason = "Choose someone to work."
	elif participants != ["player"]:
		reason = "Use Daily for workers."
	elif reserved_slots.is_valid() and int(reserved_slots.call()) >= WORKER_CAPACITY:
		reason = "Worksite capacity is full."
	elif working:
		reason = "Workers are gathering."
	elif not requested_minutes in DURATIONS:
		reason = "Choose 3, 6 or 9 hours."
	elif stock <= 0:
		reason = "Site depleted."
	elif not is_instance_valid(player) or player.is_queued_for_deletion():
		reason = "Player unavailable."
	elif includes_player and (player.is_sleeping or player.is_collapsing or player.has_critical_condition()):
		reason = "Recover before working."
	elif SceneTransition.is_transitioning or TimeComponentManager.is_paused or working:
		reason = "Work unavailable right now."
	if reason.is_empty():
		for id: String in participants:
			if not participant_unavailable_reason(id).is_empty():
				reason = "Selected worker is unavailable."
				break
	return {"units": units, "minutes": minutes, "duration": requested_minutes, "energy_start": forecast.energy_start, "energy_end": forecast.energy_end, "stock": stock, "reason": reason,
		"to_bag": mini(units, capacity) if includes_player else 0,
		"to_ground": maxi(units - capacity, 0) if includes_player else units,
		"worker_capacity": WORKER_CAPACITY, "worker_count": participants.size(),
		"includes_player": includes_player, "manual_only": participants == ["player"], "working": working}

func execute(requested_minutes: int, player: Player, owner_node: Node, drop_output: Callable = Callable()) -> Dictionary:
	var result: Dictionary = {"units": 0, "minutes": 0, "interrupted": false, "to_bag": 0, "to_ground": 0}
	if (not participants.has("player") or not is_instance_valid(owner_node)
		or owner_node.is_queued_for_deletion() or not owner_node.is_inside_tree()
		or not is_instance_valid(player) or player.is_queued_for_deletion()):
		return result
	if not _begin(requested_minutes, player, drop_output):
		return result
	result = _result
	# Time skip uses the existing minute signals; never apply needs a second time.
	# Recheck each minute because those signals may initiate collapse/scene changes.
	for minute_index: int in range(int(_plan.duration)):
		if _cancelled:
			result.interrupted = true
			break
		if stock <= 0:
			break
		# Check validity here, before passing either object to the typed helper.
		# A minute listener may free the Player or detach/free this fixture.
		if (not is_instance_valid(owner_node) or owner_node.is_queued_for_deletion()
			or not owner_node.is_inside_tree() or not is_instance_valid(player)
			or player.is_queued_for_deletion()):
			cancel()
			result.interrupted = true
			break
		if _interrupted(player, owner_node):
			result.interrupted = true
			break
		# Advancement emits signals synchronously. Record this minute first so a
		# cancel from one of those signals stores the elapsed time accurately.
		result.minutes += 1
		TimeComponentManager.advance_minutes(1)
		# cancel() can run synchronously from a minute signal during the call above.
		# Its refund is final; do not earn or settle those units a second time.
		if _cancelled:
			result.interrupted = true
			break
		if (not is_instance_valid(owner_node) or owner_node.is_queued_for_deletion()
			or not owner_node.is_inside_tree() or not is_instance_valid(player)
			or player.is_queued_for_deletion()):
			cancel()
			result.interrupted = true
			break
		if _interrupted(player, owner_node):
			result.interrupted = true
			break
		_earn_completed_work(player)
	if not _cancelled:
		_finish()
	return result

func _begin(minutes: int, player: Player, drop_output: Callable) -> bool:
	var plan: Dictionary = preview(minutes, player)
	if not plan.reason.is_empty():
		return false
	_plan = plan
	_productive_minutes = 0.0
	_result = {"units": 0, "minutes": 0, "interrupted": false, "to_bag": 0, "to_ground": 0}
	_drop_output = drop_output
	_cancelled = false
	_settling = false
	working = true
	return true

func _energy(fatigue: float, player: Player) -> float:
	var span: float = player.max_fatigue - player.min_fatigue
	return clampf((player.max_fatigue - fatigue) / span, 0.0, 1.0) if span > 0.0 else 0.0

func _forecast(requested_minutes: int, player: Player) -> Dictionary:
	var forecast: Dictionary = {"units": 0, "minutes": 0, "energy_start": 0.0, "energy_end": 0.0}
	if not is_instance_valid(player) or stock <= 0 or minutes_per_unit <= 0.0:
		return forecast
	var fatigue: float = player.fatigue
	forecast.energy_start = _energy(fatigue, player)
	var productive: float = 0.0
	# Read-only estimate of normal clock drain. Actual execution samples live energy.
	for index: int in range(maxi(requested_minutes, 0)):
		forecast.minutes += 1
		if player.debug_disable_player_needs:
			fatigue = player.min_fatigue
		elif not player.debug_disable_fatigue:
			fatigue = clampf(fatigue + player.fatigue_increase_per_min, player.min_fatigue, player.max_fatigue)
		if not player.debug_disable_player_needs and fatigue >= player.fatigue_critical_threshold:
			break
		productive += _energy(fatigue, player)
		forecast.units = mini(floori(productive / minutes_per_unit + 0.000000001), stock)
		if forecast.units >= stock:
			break
	forecast.energy_end = _energy(fatigue, player)
	return forecast

func _earn_completed_work(player: Player) -> void:
	_productive_minutes += _energy(player.fatigue, player)
	var earned: int = floori(_productive_minutes / minutes_per_unit + 0.000000001)
	var additional: int = mini(maxi(earned - int(_result.units), 0), stock)
	stock -= additional
	_result.units += additional

func _finish() -> void:
	if not working or _cancelled or _settling:
		return
	# Keep the session busy while callbacks run, and prevent duplicate settlement.
	_settling = true
	var result: Dictionary = _result
	# Settle completed output once, using capacity at completion, not the preview.
	var remaining: int = int(result.units)
	while bool(_plan.includes_player) and remaining > 0 and Inventory.try_add_item(item_id, 1):
		result.to_bag += 1
		remaining -= 1
	if remaining > 0:
		if _drop_output.is_valid() and _drop_output.call(remaining):
			result.to_ground = remaining
		else:
			# A removed scene cannot host drops: return undeliverable stock.
			stock += remaining
			result.units -= remaining
			result.interrupted = true
	last_result = result.duplicate()
	_clear_session()

func cancel() -> void:
	# Unsettled hourly output returns to natural stock on fixture teardown.
	if working and not _settling:
		stock += int(_result.units)
		_result.units = 0
		_result.to_bag = 0
		_result.to_ground = 0
		_result.interrupted = true
		_cancelled = true
		last_result = _result.duplicate()
		_clear_session()

func _clear_session() -> void:
	_drop_output = Callable()
	_settling = false
	working = false

func _interrupted(player: Player, owner_node: Node) -> bool:
	return (
		not is_instance_valid(owner_node) or owner_node.is_queued_for_deletion()
		or not owner_node.is_inside_tree()
		or not is_instance_valid(player) or player.is_queued_for_deletion()
		or player.is_sleeping or player.is_collapsing
		or SceneTransition.is_transitioning or TimeComponentManager.is_paused
		or (reserved_slots.is_valid() and int(reserved_slots.call()) >= WORKER_CAPACITY)
	)
