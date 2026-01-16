class_name WorkManager extends Node


var active_orders: Dictionary[String, WorkOrder] = {}
var _last_total_minutes: int = -1

func on_time_changed(day: int, hour: int, minute: int) -> void:
	var now_total: int = (day * 24 * 60) + (hour * 60) + minute
	if _last_total_minutes <= 0:
		_last_total_minutes = now_total
		return
		
		var delta: int = now_total - _last_total_minutes
		_last_total_minutes = now_total
		
		if delta <= 0:
			return
		
		_tick(now_total)

func _tick(now_total_minutes: int) -> void:
	pass
