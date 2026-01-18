class_name ProcessBatch extends Node

enum BatchStatus {QUEUE, RUNNING, DONE, FAILED} # status khusus proses

var batch_id: String = ""
var process_id: String = ""
var input_item_id: String = ""
var output_item_id: String = ""
var quantity: int = 0
var start_total_time_minutes: int = 0
var duration_minutes: int = 0
var slot_index: int = -1
var progress_minutes: int = 0
var status: int = BatchStatus.QUEUE


# INI HINT, BARIS KE BERAPA AKU ?
