extends RefCounted

# Scene-local ownership adapter. WorkerData owns XP; CityToolStorage owns units.
var storage
var schedule
var productive_days: Dictionary = {}
var contributions: Dictionary = {}

func record_contribution(id: String, quantity: int) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null or quantity <= 0:
		return
	worker.profession_xp += quantity # Approved MVP: one XP per completed item.
	contributions[id] = int(contributions.get(id, 0)) + quantity
	if not productive_days.has(id):
		productive_days[id] = []
	if not productive_days[id].has(TimeComponentManager.current_day):
		productive_days[id].append(TimeComponentManager.current_day)

func assigned_site(id: String) -> StringName:
	for site_id in schedule.jobs:
		if schedule.jobs[site_id].ids.has(id):
			return site_id
	return &""

func is_active(id: String) -> bool:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null:
		return false
	if worker.current_work_status in [WorkerData.WorkStatus.WORKING, WorkerData.WorkStatus.TRAVELLING]:
		return true
	if schedule.hauling != null and schedule.hauling.routes.has(id) and schedule.hauling.routes[id].phase != "idle":
		return true
	return worker.is_reserved() and assigned_site(id).is_empty()

func fire(id: String) -> String:
	if WorkerDatabase.get_worker_data(id) == null:
		return "Worker unavailable."
	if is_active(id):
		return "Only idle workers can be fired."
	var citizen: CitizenData = WorkerDatabase.get_worker_data(id).get_linked_citizen()
	if citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED:
		return "Release the workshop assignment first."
	var site_id: StringName = assigned_site(id)
	if not site_id.is_empty() and not schedule.withdraw(site_id, id):
		return "Assignment could not be released."
	if not WorkerDatabase.dismiss_worker(id):
		return "Worker is still busy."
	for unit_id: String in storage.units:
		if storage.units[unit_id].worker_id == id:
			storage.release(unit_id, id)
	for selected_ids: Array in schedule.selected.values():
		selected_ids.erase(id)
	return "Worker fired. Tools returned to City Storage."

func lock_reason(id: String) -> String:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null:
		return "Worker unavailable."
	if worker.current_work_status in [WorkerData.WorkStatus.WORKING, WorkerData.WorkStatus.TRAVELLING]:
		return "Tools cannot change while working."
	var site_id: StringName = assigned_site(id)
	if not site_id.is_empty():
		var minute: int = schedule.now() % 1440
		if schedule.now() >= int(schedule.jobs[site_id].starts[id]) and minute >= schedule.SHIFT_START and minute < schedule.SHIFT_END:
			return "Tools cannot change during the work shift."
	elif worker.is_reserved():
		return "Tools are reserved by another job."
	return ""

func equip(id: String, unit_id: String) -> String:
	if WorkerDatabase.get_worker_data(id) == null:
		return "Worker unavailable."
	var reason: String = lock_reason(id)
	if not reason.is_empty():
		return reason
	if storage.units.has(unit_id):
		var slot: String = tool_slot(str(storage.units[unit_id].tool_id))
		for unit: Dictionary in storage.units.values():
			if unit.worker_id == id and tool_slot(str(unit.tool_id)) == slot:
				return "Unequip the current tool from this slot first."
	if not storage.allocate(unit_id, id):
		return "This tool is already allocated or unavailable."
	return "Tool equipped."

func unequip(id: String, unit_id: String) -> String:
	var reason: String = lock_reason(id)
	if not reason.is_empty():
		return reason
	if storage.units.has(unit_id) and storage.units[unit_id].tool_id == "cart" and not assigned_site(id).is_empty() and schedule.is_hauler(id):
		return "Remove the assignment before unequipping its required cart."
	if not storage.release(unit_id, id):
		return "Tool is not equipped by this worker."
	return "Tool returned to City Storage."

func tool_slot(tool_id: String) -> String:
	# Slot classification is independent of each worksite's required tools.
	return "hands" if tool_id == "basic_glove" else "tool"

func tools_for(id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for unit_id: String in storage.units:
		var unit: Dictionary = storage.units[unit_id]
		var owner: WorkerData = WorkerDatabase.get_worker_data(unit.worker_id)
		var required_by_assignment: bool = unit.worker_id == id and unit.tool_id == "cart" and not assigned_site(id).is_empty() and schedule.is_hauler(id)
		rows.append({"unit_id": unit_id, "name": unit.name, "tool_id": unit.tool_id,
			"slot": tool_slot(str(unit.tool_id)),
			"can_unequip": not required_by_assignment,
			"owner_name": owner.get_resolved_display_name() if owner != null else "City Storage",
			"equipped": unit.worker_id == id, "available": str(unit.worker_id).is_empty()})
	return rows

func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for worker: WorkerData in WorkerDatabase.get_all_workers():
		var id: String = worker.worker_id
		var site_id: StringName = assigned_site(id)
		var names: PackedStringArray = []
		for unit: Dictionary in storage.units.values():
			if unit.worker_id == id:
				names.append(unit.name)
		var reason: String = lock_reason(id)
		var finishing: bool = schedule.hauling != null and schedule.hauling.routes.has(id) and schedule.hauling.routes[id].removing
		var working: bool = is_active(id)
		var citizen: CitizenData = worker.get_linked_citizen()
		var profile: VisualProfile = citizen.visual_profile if citizen != null and citizen.visual_profile != null else VisualProfile.new()
		if citizen == null or citizen.visual_profile == null:
			profile.hair_style = "default"
			profile.clothes_id = "default"
		var workshop_assigned: bool = citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED
		result.append({"id": id, "name": worker.get_resolved_display_name(),
			"profession": WorkerData.Profession.keys()[worker.profession].capitalize(),
			"activity": "Finishing current trip" if finishing else worker.get_work_activity_text(),
			"location": str(site_id).replace("ClaySite", "Clay Site ") if not site_id.is_empty() else (worker.current_job_id if worker.is_reserved() else "Unassigned"),
			"productive_days": productive_days.get(id, []).size(),
			"xp": worker.profession_xp, "star": worker.profession_star,
			"contributions": int(contributions.get(id, 0)),
			"tools_text": ", ".join(names) if not names.is_empty() else "None",
			"can_remove": not site_id.is_empty() and not finishing, "tools_locked": not reason.is_empty(), "lock_reason": reason,
			"assigned": worker.is_reserved()})
		result[-1].merge({"working": working, "can_fire": not working and not workshop_assigned,
			"visual_profile": {"skin_tone": profile.skin_tone, "clothes_id": profile.clothes_id,
				"hair_style": profile.hair_style, "accessory": profile.accessory},
			"can_goto": working and not site_id.is_empty(),
			"wage": "%d Shekel / day" % worker.wage_shekel_per_day})
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.assigned != b.assigned:
			return a.assigned
		if a.xp != b.xp:
			return a.xp > b.xp
		return str(a.name) < str(b.name)
	)
	return result
