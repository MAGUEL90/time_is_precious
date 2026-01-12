class_name WorkOrder extends Node


var order_id: String = ""
var job_id: String = ""
enum worker_type {PLAYER, NPC}
var worker_id: String = ""
var start_time_total_minutes: int = 0
var end_time_total_minutes: int = 0
var inputs_snapshot
var outputs_snapshot
var tool_used_instance_id

enum status {QUEUED, RUNNING, DONE, FAILED}

# INI HINT, BARIS KE BERAPA AKU
