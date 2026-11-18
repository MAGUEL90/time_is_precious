extends SceneTree
var failures:int=0
var checks:int=0
func _initialize():run.call_deferred()
func check(ok:bool,message:String)->bool:
	checks+=1
	if not ok:failures+=1;push_error(message)
	return ok
func run():
	var qa:String=OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\","/")
	if qa.is_empty() or not ProjectSettings.globalize_path("user://").replace("\\","/").begins_with(qa+"/"):quit(1);return
	print("QA_USER_DIR=",ProjectSettings.globalize_path("user://"))
	var city=load("res://scenes/content_scene/content_scene.tscn").instantiate();root.add_child(city);current_scene=city
	var clock=root.get_node("TimeComponentManager");clock.set_process(false)
	for i in range(20):await physics_frame
	var works=city.get_node("YSortWorld/WorkerRuntime");var visuals=works.get_node("WorkerVisuals");visuals.set_process(false)
	var db=root.get_node("WorkerDatabase")
	var citizen=root.get_node("CitizenManager").get_citizen("initial_workshop_laborer");citizen.satisfaction=0.99
	root.get_node("Inventory").add_item("shekel",9)
	var worker=db.hire_applicant(citizen.citizen_id,1,9)
	if not check(worker!=null,"Hire existing QA citizen"):quit(1);return
	var marker=works.get_node("WorksiteMarkers/WoodSitePoplar35")
	check(works.daily.toggle(&"WoodSitePoplar35",worker.worker_id) and works.daily.start(&"WoodSitePoplar35",works._drop_daily_output.bind(marker)),"Poplar35 assignment")
	var initial:Vector2=worker.physical_approach.position
	visuals._process(0.05)
	check(visuals.site_paths[worker.worker_id].has("request"),"Worker retains pending request")
	check(not worker.physical_approach.arrived and worker.physical_approach.position==initial,"Pending does not move or arrive")
	check(works.daily.jobs[&"WoodSitePoplar35"].stats[worker.worker_id].output==0,"Pending does not produce")
	var store=root.get_node("WorkStateRuntime/CitySave");store.disk.path="user://resume/pending.json"
	var before=store.snapshot.capture(city)
	check(store.save_checkpoint() and store.load_checkpoint(),"Save/load while pending: "+store.last_error)
	check(store.snapshot.capture(city)==before,"Save/load conserves complete snapshot")
	worker=db.get_worker_data(citizen.citizen_id)
	check(visuals.site_paths.is_empty(),"Transient requests not persisted")
	var arrived:bool=false
	var moving_saved:bool=false
	for i in range(1600):
		await process_frame
		visuals._process(0.05)
		if not moving_saved and worker.physical_approach.position.distance_to(initial)>4 and not worker.physical_approach.arrived:
			store.disk.path="user://resume/moving.json"
			check(store.save_checkpoint() and store.load_checkpoint(),"Moving roundtrip")
			worker=db.get_worker_data(citizen.citizen_id);moving_saved=true
		if worker.physical_approach.arrived:arrived=true;break
	check(moving_saved and arrived,"Worker walks and arrives after restored pending search")
	store.disk.path="user://resume/working.json"
	check(store.save_checkpoint() and store.load_checkpoint(),"Working roundtrip")
	clock.advance_minutes(30);visuals._process(0.05)
	check(works.daily.jobs[&"WoodSitePoplar35"].stats[citizen.citizen_id].output>0,"Wood produced only after arrival")
	check(works.daily.withdraw(&"WoodSitePoplar35",citizen.citizen_id),"Withdraw assignment")
	check(not visuals.site_paths.has(citizen.citizen_id),"Withdrawal releases route request")
	print("ROUTE_WORKER checks=",checks," failures=",failures)
	quit(1 if failures else 0)
