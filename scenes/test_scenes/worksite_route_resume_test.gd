extends SceneTree
var checks: int = 0
var failures: int = 0
func _initialize(): run.call_deferred()
func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(message)
	return ok
func run():
	var qa: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/")
	if qa.is_empty() or not ProjectSettings.globalize_path("user://").replace("\\", "/").begins_with(qa + "/"):quit(1);return
	print("QA_USER_DIR=",ProjectSettings.globalize_path("user://"))
	var city=load("res://scenes/content_scene/content_scene.tscn").instantiate()
	root.add_child(city);current_scene=city
	root.get_node("TimeComponentManager").set_process(false)
	for i in range(20):await physics_frame
	var work=city.get_node("YSortWorld/WorkerRuntime")
	work.get_node("WorkerVisuals").set_process(false)
	var router=work.road_router
	var requests:Array=[]
	for i in range(8):requests.append(work.begin_site_approach_route(Vector2(170,-145),work.site_slot_destination(&"WoodSitePoplar35", i%2),&"WoodSitePoplar35"))
	var frames:int=0
	var max_usec:int=0
	var pending_seen:bool=false
	while frames<1200:
		await process_frame
		var started=Time.get_ticks_usec()
		var all_done=true
		for request in requests:
			work.step_site_approach_route(request)
			if request.status=="pending":all_done=false;pending_seen=true
		max_usec=maxi(max_usec,Time.get_ticks_usec()-started)
		check(router.frame_operations<=router.FRAME_OPERATIONS,"Shared operation budget")
		frames+=1
		if all_done:break
	check(pending_seen and frames>1,"Requests continued across frames")
	for request in requests:
		check(request.status=="found","Concurrent request completes")
		if request.status!="found":continue
		check(request.path[-1].is_equal_approx(request.target),"Exact target")
		for i in range(1,request.path.size()):check(work.worksite_navigation.segment_clear(request.path[i-1],request.path[i]),"Safe segment")
	check(router.final_leg_searches_started<=2,"One final-leg search per Poplar work point")
	check(router.fallback_searches_started==0,"No timeout-induced duplicate fallback")
	check(router.final_leg_cache_hits>=6,"Workers share final-leg searches/results")
	print("ASYNC_FRAMES=",frames," MAX_FRAME_ROUTE_USEC=",max_usec," LEG_SEARCHES=",router.final_leg_searches_started," CACHE_HITS=",router.final_leg_cache_hits," FALLBACKS=",router.fallback_searches_started)
	var stale=work.begin_site_approach_route(Vector2(170,-145),work.site_slot_destination(&"WoodSitePoplar35",0),&"WoodSitePoplar35")
	stale.step(1,Time.get_ticks_usec()+100000)
	var original=work.worksite_navigation.polygons.duplicate()
	work.worksite_navigation.replace_polygons(original)
	stale.step(10,Time.get_ticks_usec()+100000)
	check(stale.status=="invalidated" and stale.path.is_empty(),"Geometry change invalidates pending request")
	var plain=load("res://scenes/content_scene/worksites/worksite_road_router.gd").new()
	var fallback=plain.begin_route(Vector2(170,-145),Vector2(180,-145),work.worksite_navigation,work.worksite_navigation)
	while fallback.status=="pending":
		await process_frame
		plain.step_route(fallback)
	check(fallback.status=="found" and plain.fallback_searches_started==1,"Roadless scene retains safe fallback")
	var blocked=plain.begin_route(Vector2(170,-145),Vector2(-10000,-10000),work.worksite_navigation,work.worksite_navigation)
	blocked.step(100,Time.get_ticks_usec()+100000)
	check(blocked.status=="unreachable" and blocked.path.is_empty(),"Blocked target never yields partial path")
	print("ASYNC_ROUTE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
