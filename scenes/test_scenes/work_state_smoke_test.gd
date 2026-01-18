class_name WorkStateSmokeTest extends Node2D

# Smoke test WorkState: job selesai -> wet bricks -> drying -> dry bricks

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	randomize() # supaya failure chance (kalau dipakai) tidak selalu sama

	_print_header()

func check_nodes() -> bool:
	var ok: bool = true
	ok = ok and has_node("/root/Inventory")
	ok = ok and has_node("/root/WorkManager")
	ok = ok and has_node("/root/ProcessManager")
	return ok

func _setup_process_data() -> void:
	var process_manager: Node = get_node("/root/ProcessManager")
	
	# Registrasi station kalau belum
	if process_manager.has_method("register_station"):
		process_manager.call("register_station", "drying_yard", 3)
	
	# Buat ProcessData secara runtime untuk tes
	var drying_process: Resource = ProcessData.new()
	drying_process.process_id = "drying_mudbrick" # id proses
	drying_process.display_name = "Drying Mudbrick" # tampilan nama
	drying_process.input_item_id = "wet_mudbrick" # input
	drying_process.output_item_id = "sun_dried_mudbrick" # output
	drying_process.base_duration_minutes = 60 # dipercepat untuk test 60 menit
	drying_process.required_station_id = "drying_yard" # butuh drying yard
	
	# Cuaca mempengaruhi durasi (opsional)
	if "weather_speed_multiplier" in drying_process:
		drying_process.weather_speed_multiplier = {"clear": 1.0, "cloudy": 1.2, "storm": 2.0}
	
	# Daftarkan proses, auto-pull ON, batch size 20
	if process_manager.has_method("register_process"):
		process_manager.call("register_process", drying_process, true, 20) # auto-pull wet_mudbrick

func _print_header() -> void:
	pass
