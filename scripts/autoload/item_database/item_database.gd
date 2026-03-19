extends Node

const ITEMS_PATH: String = "res://resources/items"

var items_by_id: Dictionary[String, ItemData] = {}
var is_loaded: bool = false

func _ready() -> void:
	if not is_loaded:
		_load_all_items(ITEMS_PATH)
		print(items_by_id)


func _load_all_items(path: String) -> void:
	items_by_id.clear()
	is_loaded = false
	
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("ItemDatabase: failed to open items path: %s" % path)
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
		
		var item_path: String = path.path_join(file_name)
		var item_res: Resource = load(item_path)
		if not item_res is ItemData:
			push_warning("ItemDatabase: %s is not an ItemData resource." % item_path)
			file_name = dir.get_next()
			continue
		
		var item_data: ItemData = item_res as ItemData
		var resolved_id: String = item_data.id.strip_edges()
		if resolved_id == "":
			resolved_id = file_name.trim_suffix(".tres")
			item_data.id = resolved_id
		
		if items_by_id.has(resolved_id):
			var existing_item: ItemData = items_by_id[resolved_id]
			push_error(
				"ItemDatabase: duplicate item id '%s' between %s and %s." % [
					resolved_id,
					existing_item.resource_path,
					item_path
				]
			)
			file_name = dir.get_next()
			continue
		
		items_by_id[resolved_id] = item_data
		file_name = dir.get_next()
	
	dir.list_dir_end()
	is_loaded = true

func get_item_data(item_id: String) -> ItemData:
	return items_by_id.get(item_id, null)

func get_all_items() -> Array:
	return items_by_id.values()

func reload_items() -> void:
	_load_all_items(ITEMS_PATH)
	
func has_item_data(item_id: String) -> bool:
	return items_by_id.has(item_id)
