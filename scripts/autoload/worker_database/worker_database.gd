extends Node

const WORKERS_PATH: String = "res://resources/worker_data"

var workers_by_id: Dictionary[String, WorkerData] = {}
var is_loaded: bool = false

func _ready() -> void:
	if not is_loaded:
		_load_all_workers(WORKERS_PATH)


func _load_all_workers(path: String) -> void:
	workers_by_id.clear()
	is_loaded = false
	
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("WorkerDatabase: failed to open workers path: %s" % path)
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			file_name = dir.get_next()
			continue
		
		if not file_name.ends_with(".tres"):
			file_name = dir.get_next()
			continue
		
		var worker_path: String = path.path_join(file_name)
		var worker_res: Resource = load(worker_path)
		if not worker_res is WorkerData:
			push_warning("WorkerDatabase: %s is not a WorkerData resource." % worker_path)
			file_name = dir.get_next()
			continue
		
		var worker_data: WorkerData = worker_res as WorkerData
		var resolved_id: String = worker_data.worker_id.strip_edges()
		if resolved_id == "":
			resolved_id = file_name.trim_suffix(".tres")
			worker_data.worker_id = resolved_id
		
		if workers_by_id.has(resolved_id):
			var existing_worker: WorkerData = workers_by_id[resolved_id]
			push_error(
				"WorkerDatabase: duplicate worker id '%s' between %s and %s." % [
					resolved_id,
					existing_worker.resource_path,
					worker_path
				]
			)
			file_name = dir.get_next()
			continue
		
		workers_by_id[resolved_id] = worker_data
		file_name = dir.get_next()
	
	dir.list_dir_end()
	is_loaded = true

func get_worker_data(worker_id: String) -> WorkerData:
	return workers_by_id.get(worker_id, null)

func get_all_workers() -> Array:
	return workers_by_id.values()

func reload_workers() -> void:
	_load_all_workers(WORKERS_PATH)
	
func has_worker_data(worker_id: String) -> bool:
	return workers_by_id.has(worker_id)
