extends SceneTree
func _initialize(): run.call_deferred()
func fail(msg): push_error(msg); quit(1)
func run():
 var path=ProjectSettings.globalize_path("user://").replace("\\", "/")
 var qa_root=OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/").trim_suffix("/")
 if qa_root.is_empty() or not qa_root.is_absolute_path() or not path.begins_with(qa_root+"/"): fail("not QA");return
 var city=load("res://scenes/content_scene/content_scene.tscn").instantiate();root.add_child(city);current_scene=city
 for i in range(10): await physics_frame
 var works=city.get_node("YSortWorld/WorkerRuntime")
 for i in range(6,39):
  if not works.sites.has("WoodSitePoplar%d"%i): fail("unbound authored poplar");return
 for i in range(7):
  if not works.sites.has("WoodSiteBorder%d"%i): fail("unbound border tree");return
 var map=city.get_node("AuthoredMap/YSortWorld")
 var authored_count=0
 for node in map.get_children():
  if node is Sprite2D and str(node.name).begins_with("Poplar"): authored_count+=1
 var active_count=0
 for marker in works.get_node("WorksiteMarkers").get_children():
  if marker.get("item_id")!="wood_log": continue
  if not works.is_world_site_available(marker.name):
   var col=marker.get_node_or_null("ResourceBase/CollisionPolygon2D")
   if marker.visible or (col!=null and not col.disabled): fail("retired site still visible or solid");return
   continue
  active_count+=1
  var first=works.site_slot_destination(marker.name,0);var second=works.site_slot_destination(marker.name,1)
  if first.distance_to(second)<10 or not works.worksite_navigation.is_clear(first) or not works.worksite_navigation.is_clear(second): fail("unsafe worker slots: "+str(marker.name));return
 if active_count!=authored_count: fail("authored trees differ from active worksites");return
 print("ACTIVE_TREES_AND_SLOTS_PASS count=",active_count)
 var store=root.get_node("WorkStateRuntime/CitySave");var snapshot=store.snapshot
 var doc=snapshot.capture(city)
 if doc.is_empty(): fail("capture failed "+snapshot.error);return
 if not snapshot.prepare(doc.duplicate(true),city): fail("current save invalid "+snapshot.error);return
 var codec=load("res://scenes/new_scenes/save_game/city_save_values.gd").new()
 var prior_layout=doc.duplicate(true)
 var prior_raw=codec.decode(prior_layout.state)
 for i in range(33,39): prior_raw.worksites.sites.erase("WoodSitePoplar%d"%i)
 prior_layout.state=codec.encode(prior_raw)
 if not snapshot.prepare(prior_layout,city): fail("prior layout save rejected "+snapshot.error);return
 print("PRIOR_LAYOUT_SAVE_ACCEPTED")
 var previous=doc.duplicate(true)
 var raw=codec.decode(previous.state)
 for i in range(6,39): raw.worksites.sites.erase("WoodSitePoplar%d"%i)
 for i in range(7): raw.worksites.sites.erase("WoodSiteBorder%d"%i)
 previous.state=codec.encode(raw)
 if not snapshot.prepare(previous,city): fail("previous save rejected "+snapshot.error);return
 print("PRE_FOREST_SAVE_ACCEPTED; user=",path)
 var partial=doc.duplicate(true);var partial_raw=codec.decode(partial.state);partial_raw.worksites.sites.erase("WoodSitePoplar6");partial.state=codec.encode(partial_raw)
 if snapshot.prepare(partial,city): fail("partial registry accepted");return
 var unknown=previous.duplicate(true);var unknown_raw=codec.decode(unknown.state);unknown_raw.worksites.sites["UnknownWood"]={"stock":24};unknown.state=codec.encode(unknown_raw)
 if snapshot.prepare(unknown,city): fail("unknown registry accepted");return
 print("PARTIAL_AND_UNKNOWN_REJECTED");quit(0)
