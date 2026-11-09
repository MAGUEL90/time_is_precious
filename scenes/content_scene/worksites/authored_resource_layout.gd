extends RefCounted

## Binds the runtime worksite origins to the approved resource sprites in the
## authored city map. Validation is completed for the full map before a node is
## moved or hidden, so a stale or malformed mapping cannot leave a partial map.

# Resource art contracts, not a list of instances. Persistent site IDs remain
# the runtime Marker2D names; authored sprite names/paths are editor references.
# A new resource kind still needs an explicit art contract and gameplay review.
const RESOURCE_PROFILES: Dictionary = {
	"wood_log": {"source_texture": "res://assets/objects/nature/trees/poplar.png", "icon_texture": "res://assets/items/wood_log.png", "kind": "feet"},
	"clay_lump": {"source_texture": "res://assets/objects/worksites/clay_site.png", "icon_texture": "res://assets/objects/worksites/clay_site.png", "kind": "center"},
	"reed_bundle": {"source_texture": "res://assets/objects/worksites/reed_site.png", "icon_texture": "res://assets/objects/worksites/reed_site.png", "kind": "center"},
}
# Historical IDs already used in checkpoints cannot be repurposed as another
# resource type merely by changing a marker's configuration.
const PERSISTED_SITE_ITEMS: Dictionary = {
	"WoodSite": "wood_log", "WoodSiteB": "wood_log", "WoodSiteC": "wood_log",
	"WoodSiteD": "wood_log", "WoodSiteE": "wood_log",
	"ClaySiteA": "clay_lump", "ClaySiteB": "clay_lump",
	"ReedSite": "reed_bundle", "ReedSiteB": "reed_bundle",
	"StrawSite": "straw_bundle", "WaterSite": "water_jar",
}
const WORKSITE_SESSION: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")


## Returns {"ok": true, "bindings": [...], "world_ref": WeakRef, "map_ref": WeakRef}
## on success. Empty mappings are a deliberate no-op for isolated worksite fixtures.
static func bind(worksites: Node2D, authored_resource_paths: Dictionary) -> Dictionary:
	if authored_resource_paths.is_empty():
		return {"ok": true, "bindings": [], "world_ref": null, "map_ref": null}
	var markers: Node = worksites.get_node_or_null("WorksiteMarkers") if is_instance_valid(worksites) else null
	if markers == null:
		return _failure("WorksiteMarkers is missing.")
	var authored_world: Node2D = worksites.get_node_or_null("../../AuthoredMap/YSortWorld") as Node2D
	if authored_world == null:
		return _failure("The authored YSortWorld is missing.")
	var map_root: Node = authored_world.get_parent().get_parent()
	var catalog: Dictionary = {}
	for marker: Node in markers.get_children():
		var site_id: String = str(marker.name)
		if not marker is Marker2D or not _valid_site_id(site_id) or catalog.has(site_id):
			return _failure("The runtime resource site ID or marker is invalid: " + site_id)
		var session = WORKSITE_SESSION.new()
		if marker.has_method("configure_session"):
			marker.configure_session(session)
		if PERSISTED_SITE_ITEMS.has(site_id) and str(session.item_id) != str(PERSISTED_SITE_ITEMS[site_id]):
			return _failure("The existing runtime site has the wrong resource type: " + site_id)
		if RESOURCE_PROFILES.has(str(session.item_id)):
			catalog[site_id] = RESOURCE_PROFILES[str(session.item_id)]
	if authored_resource_paths.size() != catalog.size():
		return _failure("The authored resource map must bind every configured wood, clay, and reed site exactly once.")

	var mapped_sites: Dictionary = {}
	var path_keys: Dictionary = {}
	var node_ids: Dictionary = {}
	var plan: Array[Dictionary] = []
	for raw_site_id: Variant in authored_resource_paths:
		if typeof(raw_site_id) != TYPE_STRING and typeof(raw_site_id) != TYPE_STRING_NAME:
			return _failure("A resource mapping key is not a site ID.")
		var site_id: String = str(raw_site_id)
		if not catalog.has(site_id) or mapped_sites.has(site_id):
			return _failure("Unexpected or duplicated authored resource site: " + site_id)
		mapped_sites[site_id] = true
		var raw_path: Variant = authored_resource_paths[raw_site_id]
		if typeof(raw_path) not in [TYPE_NODE_PATH, TYPE_STRING]:
			return _failure("The authored path is invalid for " + site_id)
		var path_text: String = str(raw_path)
		var source_path := NodePath(path_text)
		if source_path.is_empty() or source_path.is_absolute() or source_path.get_subname_count() != 0 or path_keys.has(path_text):
			return _failure("The authored path is invalid or duplicated for " + site_id)
		path_keys[path_text] = true
		var authored: Node = worksites.get_node_or_null(source_path)
		if not authored is Sprite2D:
			return _failure("The authored target is not a Sprite2D: " + site_id)
		var source: Sprite2D = authored as Sprite2D
		var spec: Dictionary = catalog[site_id]
		if not authored_world.is_ancestor_of(source) or not _shares_world_canvas(source, authored_world):
			return _failure("The resource sprite must remain within the authored YSortWorld canvas: " + site_id)
		if node_ids.has(source.get_instance_id()):
			return _failure("An authored Sprite2D is mapped more than once.")
		node_ids[source.get_instance_id()] = true

		var site: Node2D = markers.get_node_or_null(NodePath(site_id)) as Node2D
		var icon: Sprite2D = site.get_node_or_null("ResourceIcon") as Sprite2D
		if icon == null:
			return _failure("The runtime ResourceIcon is missing: " + site_id)
		if not _validate_sprite(source, str(spec.source_texture), site_id + " authored"):
			return _failure("The authored texture layout is unsupported: " + site_id)
		if not _validate_sprite(icon, str(spec.icon_texture), site_id + " runtime"):
			return _failure("The runtime icon layout is unsupported: " + site_id)
		if not _valid_transform(site.global_transform) or not _valid_transform(site.get_parent().global_transform):
			return _failure("The runtime site transform is unsupported: " + site_id)
		if str(spec.kind) == "feet":
			if source.flip_h or source.flip_v or not _same_basis(source.global_transform, site.global_transform):
				return _failure("The authored tree basis differs from its runtime grove: " + site_id)
		elif source.flip_h != icon.flip_h or source.flip_v != icon.flip_v \
			or not _same_basis(source.global_transform, icon.global_transform):
			return _failure("The authored resource basis differs from its runtime icon: " + site_id)

		var authored_image: Image = source.texture.get_image()
		var authored_bounds: Rect2i = authored_image.get_used_rect()
		if authored_bounds.size == Vector2i.ZERO:
			return _failure("The authored texture has no opaque pixels: " + site_id)
		var target_pixel: Vector2
		if str(spec.kind) == "feet":
			target_pixel = Vector2((authored_bounds.position.x + authored_bounds.end.x) * 0.5, authored_bounds.end.y)
		else:
			target_pixel = Vector2(authored_bounds.position) + Vector2(authored_bounds.size) * 0.5
		var target_global: Vector2 = _pixel_to_global(source, target_pixel)
		var marker_global: Vector2
		if str(spec.kind) == "feet":
			marker_global = target_global
		else:
			var icon_image: Image = icon.texture.get_image()
			var icon_bounds: Rect2i = icon_image.get_used_rect()
			if icon_bounds.size == Vector2i.ZERO:
				return _failure("The runtime icon has no opaque pixels: " + site_id)
			var icon_center := Vector2(icon_bounds.position) + Vector2(icon_bounds.size) * 0.5
			var icon_global: Vector2 = _pixel_to_global(icon, icon_center)
			marker_global = site.global_position + target_global - icon_global
		plan.append({"site_id": site_id, "site_ref": weakref(site), "source_ref": weakref(source),
			"original_visible": source.visible, "target_global": marker_global})

	# No state is changed until every entry is valid.
	for record: Dictionary in plan:
		var site_node: Node2D = record.site_ref.get_ref() as Node2D
		var source_node: Sprite2D = record.source_ref.get_ref() as Sprite2D
		site_node.global_position = record.target_global
		source_node.hide()
	return {"ok": true, "bindings": plan, "world_ref": weakref(authored_world), "map_ref": weakref(map_root)}


## Re-hide only if this binding still belongs to the exact authored world passed
## by the caller. Parking the live worksite under CitySave must never capture or
## shift its origin again.
static func hide_for_world(binding: Dictionary, authored_world: Node) -> bool:
	if not bool(binding.get("ok", false)) or binding.get("world_ref") == null:
		return false
	if binding.world_ref.get_ref() != authored_world:
		return false
	for record: Dictionary in binding.bindings:
		var source: Sprite2D = record.source_ref.get_ref() as Sprite2D
		if is_instance_valid(source):
			source.hide()
	return true


## Restore only each bound placeholder's original local visibility value.
static func restore(binding: Dictionary) -> void:
	if not bool(binding.get("ok", false)):
		return
	for record: Dictionary in binding.bindings:
		var source: Sprite2D = record.source_ref.get_ref() as Sprite2D
		if is_instance_valid(source):
			source.visible = bool(record.original_visible)


static func _valid_site_id(site_id: String) -> bool:
	# Match the save adapter's ID alphabet. Never derive identity from tree order,
	# coordinates, display names, or an authored sprite's hierarchy.
	return not site_id.is_empty() and site_id.length() <= 128 \
		and ("id_" + site_id.replace("-", "_")).is_valid_identifier()


static func _shares_world_canvas(source: Sprite2D, authored_world: Node2D) -> bool:
	var ancestor: Node = source.get_parent()
	while ancestor != authored_world:
		if ancestor == null or ancestor is CanvasLayer or ancestor is Viewport:
			return false
		ancestor = ancestor.get_parent()
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "bindings": [], "world_ref": null, "map_ref": null}


static func _validate_sprite(sprite: Sprite2D, expected_texture_path: String, label: String) -> bool:
	if sprite == null or sprite.texture == null or sprite.texture.resource_path != expected_texture_path:
		return false
	if sprite.region_enabled or sprite.hframes != 1 or sprite.vframes != 1 or sprite.frame != 0:
		return false
	var image: Image = sprite.texture.get_image()
	if image == null or image.get_width() <= 0 or image.get_height() <= 0 or image.get_used_rect().size == Vector2i.ZERO:
		return false
	return _valid_transform(sprite.global_transform)


static func _valid_transform(transform: Transform2D) -> bool:
	var determinant: float = transform.x.cross(transform.y)
	return is_finite(transform.origin.x) and is_finite(transform.origin.y) \
		and is_finite(determinant) and absf(determinant) > 0.000001


static func _same_basis(left: Transform2D, right: Transform2D) -> bool:
	return left.x.is_equal_approx(right.x) and left.y.is_equal_approx(right.y)


static func _pixel_to_global(sprite: Sprite2D, pixel: Vector2) -> Vector2:
	var size: Vector2 = sprite.texture.get_size()
	var point := pixel
	if sprite.flip_h:
		point.x = size.x - point.x
	if sprite.flip_v:
		point.y = size.y - point.y
	if sprite.centered:
		point -= size * 0.5
	point += sprite.offset
	return sprite.to_global(point)
