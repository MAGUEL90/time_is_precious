extends Node

## Verifies the live scene's temporary new-game composition and legacy source.
const WORKSITES: PackedScene = preload("res://scenes/content_scene/worksites/main_map_worksites.tscn")
const SESSION = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const AUTHORED_MAP: String = "res://scenes/map_authoring/new_map_authoring.tscn"
const EXPECTED: Dictionary = {
	"ClaySiteA": "clay_lump", "ClaySiteB": "clay_lump", "WaterSite": "water_jar",
	"ReedSite": "reed_bundle", "WoodSite": "wood_log", "WoodSiteB": "wood_log",
	"WoodSiteC": "wood_log", "WoodSiteD": "wood_log", "WoodSiteE": "wood_log",
	"StrawSite": "straw_bundle",
}
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var original_map_hash: String = FileAccess.get_sha256(AUTHORED_MAP)
	var scene: Node = WORKSITES.instantiate()
	var markers: Node = scene.get_node("WorksiteMarkers")
	var counts: Dictionary = {}
	_check(markers.get_child_count() == EXPECTED.size(), "The scene has nine requested resource sites and one legacy straw compatibility site.")
	for marker: Node in markers.get_children():
		var id: String = str(marker.name)
		_check(EXPECTED.has(id), "The scene contains only known resource-site identities.")
		var session = SESSION.new()
		if marker.has_method("configure_session"):
			marker.configure_session(session)
		_check(EXPECTED.get(id) == session.item_id, "The site provides its declared resource: " + id)
		counts[session.item_id] = int(counts.get(session.item_id, 0)) + 1
	_check(counts == {"clay_lump": 2, "water_jar": 1, "reed_bundle": 1, "wood_log": 5, "straw_bundle": 1}, "The playable scene has five wood sites, two clay sites, one reed site, and the existing straw/water sites.")
	var mapping: Dictionary = scene.get("authored_resource_paths")
	_check(mapping.size() == 8 and mapping.has("WoodSiteE") and mapping.has("ClaySiteB") and mapping.has("ReedSite") and not mapping.has("ReedSiteB"),
		"The authored map links exactly the eight requested wood, clay, and reed site identities.")
	var authored_scene: PackedScene = load(AUTHORED_MAP) as PackedScene
	var authored: Node = authored_scene.instantiate() if authored_scene != null else null
	_check(authored != null and authored.has_node("YSortWorld/Poplar5") and not authored.has_node("YSortWorld/Poplar6"),
		"The authored map keeps Poplar5 and removes only the accidental Poplar6 overlap.")
	if authored != null:
		authored.free()
	_check(not original_map_hash.is_empty() and FileAccess.get_sha256(AUTHORED_MAP) == original_map_hash, "Loading the authored map does not change its source bytes.")
	scene.free()
	print("InitialSiteCatalogTest ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
