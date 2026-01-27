class_name WorkStateBootStrap extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Hubungkan event waktu ke WorkManager dan ProcessManager
	if has_node("/root/TimeComponentManager"):
		var time_component_manager: Node = get_node("/root/TimeComponentManager")
		if time_component_manager.has_signal("time_changed"):
			time_component_manager.connect("time_changed", Callable(self, "_on_time_changed"))

	# Registrasi station dasar jika ProcessManager tersedia
	if has_node("/root/ProcessManager"):
		var process_manager: Node = get_node("/root/ProcessManager")
		if process_manager.has_method("register_station"):
			process_manager.call("register_station", "drying_yard", 3)
	
		# arahkan proses ambil & taruh item ke workshop jika ada # supaya drying chain jalan dari workshop
		if has_node("/root/WorkShopStorage"):
			var workshop_storage: Node = get_node("/root/WorkShopStorage") # workshop storage
			if process_manager.has_method("set_source_item_store"):
				process_manager.call("set_source_item_store", workshop_storage) # input proses dari workshop
			if process_manager.has_method("set_output_item_store"):
				process_manager.call("set_output_item_store", workshop_storage) # output proses ke workshop
			

func _on_time_changed(day: int, hour: int, minute: int, weather: String) -> void:
	# Lempar event waktu ke WorkManager
	if has_node("/root/WorkManager"):
		var work_manager: Node = get_node("/root/WorkManager")
		if work_manager.has_method("on_time_changed"):
			work_manager.call("on_time_changed", day, hour, minute)

	# Lempar event waktu ke ProcessManager
	if has_node("/root/ProcessManager"):
		var process_manager: Node = get_node("/root/ProcessManager")
		if process_manager.has_method("on_time_changed"):
			process_manager.call("on_time_changed", day, hour, minute)
	# Update cuaca di ProcessManager jika method tersedia
		if process_manager.has_method("set_weather_key"):
			process_manager.call("set_weather_key", weather)

	
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
