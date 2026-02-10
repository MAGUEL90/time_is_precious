class_name WorkStateSmokeTest extends Node2D

var started: bool = false

# Smoke test WorkState: job selesai -> wet bricks -> drying -> dry bricks

func _ready() -> void:
	
	randomize() # supaya failure chance (kalau dipakai) tidak selalu sama
	
	#if has_node("/root/TimeComponentManager"):
		#var time_component_manager: Node = get_node("/root/TimeComponentManager")
		#if time_component_manager.has_method("toggle_pause"):
			#time_component_manager.call("toggle_pause")

func _check_nodes() -> bool:
	var ok: bool = true
	ok = ok and has_node("/root/Inventory")
	ok = ok and has_node("/root/WorkManager")
	ok = ok and has_node("/root/ProcessManager")
	ok = ok and has_node("/root/WorkShopStorage")
	return ok

func _setup_process_data() -> void:
	var process_manager: ProcessManager = get_node("/root/ProcessManager")
	var workshop_storage: WorkShopStorage = get_node("/root/WorkShopStorage")
	
	# Registrasi station kalau belum
	if process_manager.has_method("register_station"):
		process_manager.call("register_station", "drying_yard", 3)
	
	# Buat ProcessData secara runtime untuk tes
	var drying_process: ProcessData = ProcessData.new()
	drying_process.process_id = "drying_mudbrick" # id proses
	drying_process.display_name = "Drying Mudbrick" # tampilan nama
	drying_process.input_item_id = "wet_mudbrick" # input
	drying_process.output_item_id = "sun_dried_mudbrick" # output
	drying_process.base_duration_minutes = 60 # dipercepat untuk test 60 menit
	drying_process.required_station_id = "drying_yard" # butuh drying yard
	
	# Cuaca mempengaruhi durasi (opsional)
	drying_process.weather_speed_multiplier = {"clear": 1.0, "cloudy": 1.2, "storm": 2.0}
	
	# Daftarkan proses, auto-pull ON, batch size 20
	if process_manager.has_method("register_process"):
		process_manager.call("register_process", drying_process, true, 20) # auto-pull wet_mudbrick
	# penting: auto-pull harus melihat wet_mudbrick di workshop, bukan di inventory player
	if process_manager.has_method("set_source_item_store"):
		process_manager.call("set_source_item_store", workshop_storage)
	if process_manager.has_method("set_output_item_store"):
		process_manager.call("set_output_item_store", workshop_storage)

func _setup_job_and_inventory() -> void:
	var inventory: Inventory = get_node("/root/Inventory")
	
	# Siapkan input agar job bisa start (contoh item)
	# Kamu boleh ganti id item sesuai yang kamu pakai di project
	if inventory.has_method("add_item"):
		inventory.call("add_item", "clay_lump", 10)
		inventory.call("add_item", "straw_bundle", 10)
		inventory.call("add_item", "water_jar", 10)

func _run_simulation() -> void:
	var work_manager: WorkManager = get_node("/root/WorkManager")
	# var inventory: Node = get_node("/root/Inventory")
	
	# Buat JobData runtime (mudbrick making) untuk tes
	var mudbrick_job: JobData = JobData.new()
	mudbrick_job.job_id = "mudbrick_make"
	mudbrick_job.display_name = "Mudbrick Making"
	mudbrick_job.base_duration_minutes = 60 # durasi job 10 menit untuk test
	mudbrick_job.inputs = {"clay_lump": 3, "straw_bundle": 3, "water_jar": 3}
	mudbrick_job.outputs = {"wet_mudbrick": 60}  # output intermediate 60 bata basah

	# Mulai job sebagai PLAYER
	var order_id: String = ""
	if work_manager.has_method("start_job"):
		# worker_kind 0 diasumsikan PLAYER
		order_id = str(work_manager.call(
			"start_job", 
			mudbrick_job, 
			WorkOrder.Worker_Type.NPC, 
			"npc_01", null, Inventory, null, 0))
	
	print("Start_order_id: ", order_id)
	
	_print_workshop("WorkShop Storage After Job Done (expect workshop storage wet_mudbrick = 60)") # cek workshop, bukan inventory
	_print_inventory("Inventory After Job Done (should NOT receive wet_mudbrick)") # bandingkan inventory (harusnya tidak bertambah)

func _call_time(day: int, hour: int, minute: int) -> void:
	if has_node("/root/WorkManager"):
		var work_manager: WorkManager = get_node("/root/WorkManager")
		if work_manager.has_method("on_time_changed"):
			work_manager.call("on_time_changed", day, hour, minute)
	
	if has_node("/root/ProcessManager"):
		var process_manager: ProcessManager = get_node("/root/ProcessManager")
		if process_manager.has_method("on_time_changed"):
			process_manager.call("on_time_changed", day, hour, minute)

func _print_inventory(label: String) -> void:
	var inventory: Inventory = get_node("/root/Inventory")
	if inventory.items:
		print("----", label, "----")
		print(inventory.items)
	#print("----", label, "----") # print selalu supaya kelihatan walau kosong
	#print(inventory.items) # tampilkan dict inventory

func _print_workshop(label: String) -> void:
	# print isi workshop storage untuk memastikan output masuk ke sini 
	# debug utama pemisahan inventory vs workshop
	if not has_node("/root/WorkShopStorage"):
		print("----", label, "----")
		print("WorkShopStorage tidak ditemukan di /root (pastikan sudah Autoload & namanya benar).") # info error yang jelas
		return
	
	var workshop_storage: Node = get_node("/root/WorkShopStorage") # ambil autoload workshop
	var workshop_items: Dictionary = workshop_storage.get("items") if workshop_storage != null else {} # ambil dict items workshop
	print("----", label, "----")
	print("Workshop_storage items: ", workshop_items) # tampilkan stok workshop
	var claimables: Array = workshop_storage.get("claimable_outputs") if workshop_storage != null else [] # ambil escrow list
	print("Claimable outputs count: ", claimables.size()) # jumlah output yang bisa ditebus
	if claimables.size() > 0:
		print("Claimable[0]: ", claimables[0]) # tampilkan 1 contoh agar kelihatan fee + items

func _print_header() -> void:
	print("====================================")
	print("WorkStateSmokeTest START")
	print("====================================")

func _start_test(worker_id: String) -> void:
	_print_header()
	
	if not _check_nodes():
		push_error("SmokeTest: node autoload belum lengkap. Cek /root Inventory, WorkManager, ProcessManager, WorkShopStorage.")
		return
	
	if worker_id and started: return
	
	started = true
	
	_setup_process_data()
	_setup_job_and_inventory()
	_run_simulation()
