extends RefCounted

signal gathered(id: String, quantity: int)

# Scene-local standing assignments. Shares the existing world clock and site stock.
const SHIFT_START: int = 7 * 60
const SHIFT_END: int = 15 * 60
const DAILY_LIMIT: int = SHIFT_END - SHIFT_START
var sites: Dictionary = {}
var jobs: Dictionary = {}
var selected: Dictionary = {}
var hauler_setups: Dictionary = {}
var minutes_by_worker: Dictionary = {}
var ledger_day: int = -1
var last_tick: int = -1
var last_stock_day: int = -1
# No unapproved scarcity range: configure these only after balancing approval.
var stock_min: int = 72
var stock_max: int = 72
var rng := RandomNumberGenerator.new()
var journey_provider: Callable
var hauling
var hauler_ready: Callable
var tool_requirement: Callable

func is_hauler(id: String) -> bool:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	return worker != null and worker.profession == WorkerData.Profession.HAULER

func start_reason(site_id: StringName) -> String:
	var count: int = 0
	for id: String in selected[site_id]:
		if is_hauler(id):
			if not hauler_setups.has(id):
				return "Choose Hauler storage and daily target."
			count += 1
	if count > 0:
		if hauling == null or not hauler_ready.is_valid():
			return "Hauler destination is not configured."
		return str(hauler_ready.call(site_id, count))
	return ""

func _hauler_eligible(id: String) -> bool:
	if hauling != null and hauling.target_reached(id, now() / 1440):
		return false
	for site_id in jobs:
		var job: Dictionary = jobs[site_id]
		if job.ids.has(id):
			return now() >= int(job.starts[id]) and now() % 1440 >= SHIFT_START and now() % 1440 < SHIFT_END and now() >= arrival_time(site_id, id, now() / 1440)
	return false

func _site_depleted(site_id: StringName) -> bool:
	return sites[site_id].stock <= 0

func departure_time(site_id: StringName, id: String, day: int) -> int:
	if journey_provider.is_valid():
		return int(floor(journey_provider.call(site_id, id, day).start))
	return arrival_time(site_id, id, day)

func arrival_time(_site_id: StringName, _id: String, day: int) -> int:
	return day * 1440 + SHIFT_START

func setup(site_sessions: Dictionary) -> void:
	sites = site_sessions
	last_tick = now()
	last_stock_day = TimeComponentManager.current_day
	rng.randomize()
	for key in sites:
		selected[key] = []

func now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func unavailable(id: String) -> String:
	if id == "player":
		return "Hourly only"
	for job: Dictionary in jobs.values():
		if job.ids.has(id):
			return "Assigned to a worksite"
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null:
		return "Unavailable"
	if worker.is_reserved():
		return "Working"
	if tool_requirement.is_valid():
		var requirement: String = str(tool_requirement.call(id))
		if not requirement.is_empty():
			return requirement
	var citizen: CitizenData = worker.get_linked_citizen()
	return "Unavailable" if citizen != null and not citizen.can_be_assigned() else ""

func toggle(site_id: StringName, id: String) -> bool:
	var ids: Array = selected[site_id]
	if ids.has(id):
		ids.erase(id)
		hauler_setups.erase(id)
		return true
	if ids.size() + reserved_count(site_id) >= 2 or not unavailable(id).is_empty():
		return false
	ids.append(id)
	return true

func select_hauler(site_id: StringName, id: String, destination_path: NodePath, destination_name: String, daily_target: int) -> bool:
	if not is_hauler(id) or destination_path.is_empty() or daily_target <= 0 or selected[site_id].has(id):
		return false
	if not toggle(site_id, id):
		return false
	hauler_setups[id] = {"destination_path": destination_path, "destination_name": destination_name, "daily_target": daily_target}
	return true

func discard_setup(site_id: StringName) -> void:
	for id: String in selected[site_id]:
		hauler_setups.erase(id)
	selected[site_id] = []

func withdraw(site_id: StringName, id: String) -> bool:
	if not jobs.has(site_id) or not jobs[site_id].ids.has(id):
		return false
	_settle(site_id)
	if is_hauler(id) and hauling != null and not hauling.withdraw(id):
		return true
	_finish_withdraw(site_id, id)
	return true

func _finish_withdraw(site_id: StringName, id: String) -> void:
	_release_worker(jobs[site_id], id)
	jobs[site_id].ids.erase(id)
	if jobs[site_id].ids.is_empty():
		jobs.erase(site_id)

func progress_rows(site_id: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if jobs.has(site_id):
		for id: String in jobs[site_id].ids:
			var worker: WorkerData = WorkerDatabase.get_worker_data(id)
			var stats: Dictionary = jobs[site_id].stats[id]
			rows.append({"id": id, "name": worker.get_resolved_display_name() if worker != null else id,
				"days": stats.days.size(), "output": stats.output,
				"hauler": is_hauler(id), "removing": hauling != null and hauling.routes.has(id) and hauling.routes[id].removing})
			if is_hauler(id) and hauling != null and hauling.routes.has(id):
				rows[-1].merge({"daily_target": hauling.routes[id].daily_target,
					"delivered_today": hauling.delivered_on_day(id, now() / 1440),
					"destination_name": hauling.routes[id].destination_name})
	return rows

func start(site_id: StringName, drop: Callable) -> bool:
	var ids: Array = selected[site_id]
	if ids.is_empty() or sites[site_id].working or not start_reason(site_id).is_empty():
		return false
	var existing: Array = jobs[site_id].ids if jobs.has(site_id) else []
	if ids.size() + existing.size() > 2:
		return false
	for id: String in ids:
		if not existing.has(id) and not unavailable(id).is_empty():
			return false
	if not jobs.has(site_id):
		jobs[site_id] = {"ids": [], "order": "daily_%d_%s" % [get_instance_id(), site_id],
			"drop": drop, "units": 0, "progress": {}, "starts": {}, "stats": {}}
	var job: Dictionary = jobs[site_id]
	for id: String in ids:
		if not job.ids.has(id):
			job.ids.append(id)
			job.progress[id] = 0
			job.starts[id] = (TimeComponentManager.current_day + 1) * 1440 + SHIFT_START
			job.stats[id] = {"days": [], "output": 0}
			# Busy reserves this standing assignment even outside its daily shift.
			WorkerDatabase.get_worker_data(id).start_work(job.order, "clay_daily")
			if is_hauler(id) and hauling != null:
				hauling.begin(id, site_id, now(), hauler_setups[id])
				hauler_setups.erase(id)
	_sync_activities()
	selected[site_id] = []
	return true

func start_day_text(site_id: StringName) -> String:
	var days: Array[int] = []
	var ids: Array = selected[site_id].duplicate()
	if jobs.has(site_id):
		ids.append_array(jobs[site_id].ids)
	for id: String in ids:
		var day: int = TimeComponentManager.current_day + 1
		if jobs.has(site_id) and jobs[site_id].starts.has(id):
			day = int(jobs[site_id].starts[id]) / 1440
		if not days.has(day):
			days.append(day)
	days.sort()
	var labels: PackedStringArray = []
	for day: int in days:
		labels.append("Day %d" % day)
	return "Start work: " + " / ".join(labels)

func reserved_count(site_id: StringName) -> int:
	return jobs[site_id].ids.size() if jobs.has(site_id) else 0

func active_count(site_id: StringName) -> int:
	var minute: int = now() % 1440
	if minute < SHIFT_START or minute >= SHIFT_END or sites[site_id].stock <= 0:
		return 0
	var count: int = 0
	if jobs.has(site_id):
		for id: String in jobs[site_id].ids:
			if not is_hauler(id) and activity(site_id, id) == WorkerData.WorkStatus.WORKING:
				count += 1
	return count

func activity(site_id: StringName, id: String) -> WorkerData.WorkStatus:
	if not jobs.has(site_id) or not jobs[site_id].ids.has(id):
		return WorkerData.WorkStatus.IDLE
	if is_hauler(id) and hauling != null and hauling.routes.has(id):
		var visual: Dictionary = hauling.get_visual(id, float(now()))
		if visual.get("moving", false):
			return WorkerData.WorkStatus.TRAVELLING
	var first_day: int = int(jobs[site_id].starts[id]) / 1440
	if now() < departure_time(site_id, id, first_day):
		return WorkerData.WorkStatus.RESTING
	var minute: int = now() % 1440
	if now() >= departure_time(site_id, id, TimeComponentManager.current_day) and minute < SHIFT_START:
		return WorkerData.WorkStatus.TRAVELLING
	if minute < SHIFT_START or minute >= SHIFT_END:
		return WorkerData.WorkStatus.RESTING
	if now() < arrival_time(site_id, id, TimeComponentManager.current_day):
		return WorkerData.WorkStatus.TRAVELLING
	if ledger_day == TimeComponentManager.current_day and int(minutes_by_worker.get(id, 0)) >= DAILY_LIMIT:
		return WorkerData.WorkStatus.RESTING
	if is_hauler(id):
		if hauling != null and hauling.target_reached(id, now() / 1440):
			return WorkerData.WorkStatus.RESTING
		return WorkerData.WorkStatus.WAITING_FOR_RESOURCES
	if sites[site_id].stock <= 0:
		return WorkerData.WorkStatus.WAITING_FOR_RESOURCES
	return WorkerData.WorkStatus.WORKING

func _sync_activities() -> void:
	for site_id in jobs:
		var job: Dictionary = jobs[site_id]
		for id: String in job.ids:
			var worker: WorkerData = WorkerDatabase.get_worker_data(id)
			if worker != null:
				worker.set_work_activity(job.order, activity(site_id, id))

func status(site_id: StringName) -> String:
	if not jobs.has(site_id):
		return ""
	var first_start: int = int(jobs[site_id].starts.values().min())
	if now() < first_start:
		return "Scheduled for Day %d, 07:00" % (first_start / 1440)
	var minute: int = now() % 1440
	if minute < SHIFT_START or minute >= SHIFT_END:
		return "Resting until 07:00"
	if sites[site_id].stock <= 0:
		return "Waiting for resources. Returning tomorrow."
	for id: String in jobs[site_id].ids:
		if activity(site_id, id) == WorkerData.WorkStatus.TRAVELLING:
			return "Workers travelling to worksite."
	return "Daily work active: 07:00 - 15:00"

func tick() -> void:
	var current: int = now()
	if current <= last_tick:
		return
	# The clock emits every elapsed minute, including explicit time skips.
	var interval: int = current - 1
	var day: int = interval / 1440
	var minute: int = interval % 1440
	last_tick = current
	if ledger_day != day:
		minutes_by_worker.clear()
		ledger_day = day
	if minute >= SHIFT_START and minute < SHIFT_END:
		for site_id in jobs.keys():
			var job: Dictionary = jobs[site_id]
			var session = sites[site_id]
			for id: String in job.ids:
				if is_hauler(id):
					continue
				if interval < int(job.starts[id]):
					continue
				if interval < arrival_time(site_id, id, day):
					continue
				if session.stock <= 0 or int(minutes_by_worker.get(id, 0)) >= DAILY_LIMIT:
					continue
				minutes_by_worker[id] = int(minutes_by_worker.get(id, 0)) + 1
				job.progress[id] = int(job.progress.get(id, 0)) + 1
				if int(job.progress[id]) >= session.MINUTES_PER_CLAY:
					job.progress[id] -= session.MINUTES_PER_CLAY
					session.stock -= 1
					job.units += 1
					job.stats[id].output += 1
					if not job.stats[id].days.has(day):
						job.stats[id].days.append(day)
					gathered.emit(id, 1)
					_settle(site_id)
			if session.stock <= 0 or minute == SHIFT_END - 1:
				_settle(site_id)
				job.progress.clear()
	# Replace only unharvested natural stock; ground output is never rerolled.
	var current_day: int = current / 1440
	if current_day != last_stock_day:
		for session in sites.values():
			session.stock = rng.randi_range(stock_min, stock_max)
		last_stock_day = current_day
	if hauling != null:
		hauling.tick(current, _hauler_eligible, _site_depleted)
		for site_id in jobs.keys():
			for id: String in jobs[site_id].ids.duplicate():
				if is_hauler(id) and hauling.finished(id):
					_finish_withdraw(site_id, id)
	_sync_activities()

func _settle(site_id: StringName) -> void:
	var job: Dictionary = jobs[site_id]
	var units: int = int(job.units)
	if units > 0 and job.drop.is_valid() and job.drop.call(units):
		job.units = 0

func _release_worker(job: Dictionary, id: String) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker != null:
		worker.finish_work(job.order)
	job.progress.erase(id)
	job.starts.erase(id)
	job.stats.erase(id)

func cleanup() -> void:
	for job: Dictionary in jobs.values():
		for id: String in job.ids:
			_release_worker(job, id)
	jobs.clear()
	hauler_setups.clear()
	journey_provider = Callable()
	hauler_ready = Callable()
	tool_requirement = Callable()
	if hauling != null:
		hauling.routes.clear()
		hauling = null
