extends Node

## Verifies the live scene's temporary new-game composition and legacy source.
const WORKSITES: PackedScene = preload("res://scenes/content_scene/worksites/main_map_worksites.tscn")
const SESSION = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const AUTHORED_MAP: String = "res://scenes/map_authoring/new_map_authoring.tscn"
const EXPECTED: Dictionary = {
	"ClaySiteA": "clay_lump", "ClaySiteB": "clay_lump", "WaterSite": "water_jar",
	"ReedSite": "reed_bundle", "ReedSiteB": "reed_bundle", "WoodSite": "wood_log",
	"WoodSiteB": "wood_log", "WoodSiteC": "wood_log", "StrawSite": "straw_bundle",
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
	_check(markers.get_child_count() == EXPECTED.size(), "The scene has eight requested sites and one legacy straw compatibility site.")
	for marker: Node in markers.get_children():
		var id: String = str(marker.name)
		_check(EXPECTED.has(id), "The scene contains only known resource-site identities.")
		var session = SESSION.new()
		if marker.has_method("configure_session"):
			marker.configure_session(session)
		_check(EXPECTED.get(id) == session.item_id, "The site provides its declared resource: " + id)
		counts[session.item_id] = int(counts.get(session.item_id, 0)) + 1
	_check(counts == {"clay_lump": 2, "water_jar": 1, "reed_bundle": 2, "wood_log": 3, "straw_bundle": 1}, "The playable scene has the requested composition plus the legacy straw exception.")
	_check(not original_map_hash.is_empty() and FileAccess.get_sha256(AUTHORED_MAP) == original_map_hash, "The authored map is unchanged.")
	scene.free()
	print("InitialSiteCatalogTest ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
