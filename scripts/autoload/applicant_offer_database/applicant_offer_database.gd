extends Node

const OFFERS_PATH: String = "res://resources/applicants"

var offers_by_id: Dictionary[String, ApplicantOfferData] = {}
var is_loaded: bool = false

func _ready() -> void:
	if not is_loaded:
		_load_all_offers(OFFERS_PATH)


func _load_all_offers(path: String) -> void:
	offers_by_id.clear()
	is_loaded = false
	
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("ApplicantOfferDatabase: failed to open offers path: %s" % path)
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
		
		var offer_path: String = path.path_join(file_name)
		var offer_res: Resource = load(offer_path)
		if not offer_res is ApplicantOfferData:
			push_warning("ApplicantOfferDatabase: %s is not an ApplicantOfferData resource." % offer_path)
			file_name = dir.get_next()
			continue
		
		var offer_data: ApplicantOfferData = offer_res as ApplicantOfferData
		var resolved_id: String = offer_data.offer_id.strip_edges()
		if resolved_id == "":
			resolved_id = file_name.trim_suffix(".tres")
			offer_data.offer_id = resolved_id
		
		if offers_by_id.has(resolved_id):
			var existing_offer: ApplicantOfferData = offers_by_id[resolved_id]
			push_error(
				"ApplicantOfferDatabase: duplicate offer id '%s' between %s and %s." % [
					resolved_id,
					existing_offer.resource_path,
					offer_path
				]
			)
			file_name = dir.get_next()
			continue
		
		offers_by_id[resolved_id] = offer_data
		file_name = dir.get_next()
	
	dir.list_dir_end()
	is_loaded = true

func get_offer_data(offer_id: String) -> ApplicantOfferData:
	return offers_by_id.get(offer_id, null)

func get_all_offers() -> Array:
	return offers_by_id.values()

func reload_offers() -> void:
	_load_all_offers(OFFERS_PATH)
	
func has_offer_data(offer_id: String) -> bool:
	return offers_by_id.has(offer_id)
