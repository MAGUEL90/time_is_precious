class_name WorkOrder extends Node


enum Worker_Type {PLAYER, NPC}
enum Status {QUEUED, RUNNING, DONE, FAILED}


var worker_kind: int = Worker_Type.NPC # menyimpan jenis worker (player/NPC)
var current_status: int = Status.QUEUED
var order_id: String = ""
var job_id: String = ""
var worker_id: String = ""
var start_time_total_minutes: int = 0
var end_time_total_minutes: int = 0
var inputs_snapshot: Dictionary = {} # snapshot input untuk debugging/save
var outputs_snapshot: Dictionary = {} # snapshot output untuk debugging/save
var tool_used_instance_id = "" # id tool instance (kalau kamu pakai sistem tool instance)

# INI HINT, BARIS KE BERAPA AKU ?
