extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var user_path=ProjectSettings.globalize_path("user://").replace("\\", "/")
 var isolated_root=OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/").trim_suffix("/")
 if isolated_root.is_empty() or not isolated_root.is_absolute_path() or not user_path.begins_with(isolated_root+"/"): push_error("Wrong QA profile"); quit(1); return
 var city=load("res://scenes/content_scene/content_scene.tscn").instantiate(); root.add_child(city); current_scene=city
 var clock=root.get_node("TimeComponentManager"); clock.set_process(false)
 for i in range(30): await physics_frame
 var inventory=root.get_node("Inventory"); var citizens=root.get_node("CitizenManager"); var db=root.get_node("WorkerDatabase"); var store=root.get_node("WorkStateRuntime/CitySave")
 var applicant=citizens.get_citizen("initial_workshop_laborer")
 print("FIXTURE applicant=",applicant," existing_worker=",db.get_worker_data("initial_workshop_laborer")," map=",store.map," user=",user_path)
 if applicant==null: quit(1); return
 applicant.satisfaction=0.99; applicant.employment_status=applicant.EmploymentStatus.APPLICANT
 inventory.add_item("shekel",9)
 var worker=db.hire_applicant("initial_workshop_laborer",1,9)
 if worker==null: push_error("Hire failed"); quit(1); return
 var runtime=city.get_node("YSortWorld/WorkerRuntime"); var visuals=runtime.get_node("WorkerVisuals"); visuals.set_process(false); runtime.daily.tool_requirement=Callable()
 var reed=runtime.get_node("WorksiteMarkers/ReedSite")
 if not runtime.daily.toggle(&"ReedSite",worker.worker_id) or not runtime.daily.start(&"ReedSite",runtime._drop_daily_output.bind(reed)): push_error("Assign failed"); quit(1); return
 visuals._process(0.05)
 var expected=worker.physical_approach.duplicate(true)
 if expected.is_empty() or expected.arrived: push_error("Not in transit"); quit(1); return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://reed_reassign_save_fixture"))
 store.disk.path="user://reed_reassign_save_fixture/checkpoint.json"
 if not store.save_checkpoint(): push_error("QA save failed: "+store.last_error); quit(1); return
 print("REED_CHECKPOINT_SAVED target=",expected.target)
 if not store.load_checkpoint(): push_error("QA load failed: "+store.last_error); quit(1); return
 worker=db.get_worker_data("initial_workshop_laborer")
 if worker==null or worker.physical_approach.target!=expected.target or worker.physical_approach.arrived: push_error("Restored approach mismatch"); quit(1); return
 for frame in range(500):
  await process_frame
  visuals._process(0.05)
  if worker.physical_approach.get("arrived",false): break
 if not worker.physical_approach.get("arrived",false): push_error("Restored worker cannot reach reed"); quit(1); return
 print("REED_SAVE_LOAD_ARRIVAL_PASS target=",worker.physical_approach.target)
 if not store.save_checkpoint(): push_error("QA save at work failed: "+store.last_error); quit(1); return
 if not store.load_checkpoint(): push_error("QA reload at work failed: "+store.last_error); quit(1); return
 worker=db.get_worker_data("initial_workshop_laborer")
 visuals._process(0.05)
 var actor=visuals.actors.get(worker.worker_id)
 if actor==null or not actor.has_meta("reed_pond_exit"): push_error("Exit context was not restored"); quit(1); return
 if not runtime.daily.withdraw(&"ReedSite",worker.worker_id): push_error("Withdraw after reload failed"); quit(1); return
 var clay=runtime.get_node("WorksiteMarkers/ClaySiteA")
 if not runtime.daily.toggle(&"ClaySiteA",worker.worker_id) or not runtime.daily.start(&"ClaySiteA",runtime._drop_daily_output.bind(clay)): push_error("Clay reassignment failed"); quit(1); return
 if not store.save_checkpoint(): push_error("Save after reassignment failed "+store.last_error); quit(1); return
 if not store.load_checkpoint(): push_error("Load after reassignment failed "+store.last_error); quit(1); return
 worker=db.get_worker_data("initial_workshop_laborer")
 for frame in range(700):
  await process_frame
  visuals._process(0.05)
  if worker.physical_approach.get("arrived",false): print("REED_REASSIGNED_SAVE_LOAD_PASS frame=",frame," target=",worker.physical_approach.target); quit(0); return
 push_error("Restored reassigned worker did not reach clay "+str(worker.physical_approach)); quit(1)
