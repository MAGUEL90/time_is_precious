extends RefCounted

## Advance paid work through actual 07:00–15:00 shifts and physical routes.
static func work_minutes(amount: int, visuals: Node2D, ids: Array[String]) -> bool:
	var was_paused: bool = TimeComponentManager.is_paused
	TimeComponentManager.is_paused = false
	while amount > 0:
		var minute: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
		if minute < 7 * 60 or minute >= 15 * 60:
			var wait: int = 7 * 60 - minute if minute < 7 * 60 else 1440 - minute + 7 * 60
			if not TimeComponentManager.advance_minutes(wait):
				TimeComponentManager.is_paused = was_paused
				return false
			continue
		var arrived: bool = false
		for _frame: int in range(4000):
			arrived = true
			for id: String in ids:
				var worker: WorkerData = WorkerDatabase.get_worker_data(id)
				if worker == null or not worker.physical_approach.get("arrived", false):
					arrived = false
			if arrived:
				break
			visuals.plot_presence.update(visuals, 0.1)
		if not arrived:
			TimeComponentManager.is_paused = was_paused
			return false
		var step: int = mini(amount, 15 * 60 - minute)
		if not TimeComponentManager.advance_minutes(step):
			TimeComponentManager.is_paused = was_paused
			return false
		amount -= step
	TimeComponentManager.is_paused = was_paused
	return true
