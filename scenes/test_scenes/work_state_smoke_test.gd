class_name WorkStateSmokeTest extends Node2D

var started: bool = false

var inventory: Inventory = Inventory
var work_manager: WorkManager = WorkManager
var workshop_storage: WorkShopStorage = WorkShopStorage
var process_manager: ProcessManager = ProcessManager

const DRYING_PROCESS: ProcessData = preload(
	"res://resources/process_data/drying_mudbrick.tres"
)

# Smoke test WorkState: job selesai -> wet bricks -> drying -> dry bricks

func _ready() -> void:
	randomize() # supaya failure chance (kalau dipakai) tidak selalu sama

func _setup_process_data() -> void:
	# Bangun Drying Yard level 3 agar semua slot tersedia di smoke test.
	WorkshopFacilityManager.set_facility_level("drying_yard", 3)
	
	# Gunakan data proses yang sama dengan gameplay. Drying tetap manual.
	if process_manager.has_method("register_process"):
		process_manager.call("register_process", DRYING_PROCESS)
	# penting: auto-pull harus melihat wet_mudbrick di workshop, bukan di inventory player
	if process_manager.has_method("set_source_item_store"):
		process_manager.call("set_source_item_store", workshop_storage)
	if process_manager.has_method("set_output_item_store"):
		process_manager.call("set_output_item_store", workshop_storage)

func _setup_job_and_inventory() -> void:
	
	# Siapkan input agar job bisa start (contoh item)
	# Kamu boleh ganti id item sesuai yang kamu pakai di project
	if inventory.has_method("add_item"):
		inventory.call("add_item", "clay_lump", 10)
		inventory.call("add_item", "straw_bundle", 10)
		inventory.call("add_item", "water_jar", 10)
		inventory.call("add_item", "shekel", 10)

func _run_simulation() -> void:
	
	# Buat JobData runtime (mudbrick making) untuk tes
	var mudbrick_job: JobData = JobData.new()
	mudbrick_job.job_id = "mudbrick_make"
	mudbrick_job.display_name = "Mudbrick Making"
	mudbrick_job.base_duration_minutes = 30 # durasi job 10 menit untuk test
	mudbrick_job.inputs = {"clay_lump": 3, "straw_bundle": 3, "water_jar": 3}
	mudbrick_job.outputs = {"wet_mudbrick": 20}

	# Mulai job sebagai PLAYER
	var order_id: String = ""
	if work_manager.has_method("start_job"):
		order_id = str(work_manager.call(
			"start_job", 
			mudbrick_job, 
			WorkOrder.Worker_Type.NPC, 
			"worker_laborer_01", null, Inventory, null, 5)) # service fee test 5r
	
	print("Start_order_id: ", order_id)
	
	
func _call_time(day: int, hour: int, minute: int) -> void:
	if work_manager.has_method("on_time_changed"):
		work_manager.call("on_time_changed", day, hour, minute)
	
	if process_manager.has_method("on_time_changed"):
		process_manager.call("on_time_changed", day, hour, minute)

func _print_inventory(label: String) -> void:
	if inventory.items:
		print("----", label, "----")
		print(inventory.items)
	#print("----", label, "----") # print selalu supaya kelihatan walau kosong
	#print(inventory.items) # tampilkan dict inventory

func _print_workshop(label: String) -> void:
	# print isi workshop storage untuk memastikan output masuk ke sini 
	# debug utama pemisahan inventory vs workshop
	if not workshop_storage:
		print("----", label, "----")
		print("WorkShopStorage tidak ditemukan di /root (pastikan sudah Autoload & namanya benar).") # info error yang jelas
		return
	
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
	
	if worker_id and started: return
	
	started = true
	
	_setup_process_data()
	_setup_job_and_inventory()
	_run_simulation()
