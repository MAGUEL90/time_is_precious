extends SceneTree
func _initialize(): call_deferred("run")
func fail(message): push_error(message); quit(1)
func run():
 var user_path=ProjectSettings.globalize_path("user://").replace("\\", "/")
 var isolated_root=OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/").trim_suffix("/")
 if isolated_root.is_empty() or not isolated_root.is_absolute_path() or not user_path.begins_with(isolated_root+"/"): fail("Wrong QA profile"); return
 var city=load("res://scenes/content_scene/content_scene.tscn").instantiate(); root.add_child(city); current_scene=city
 var clock=root.get_node("TimeComponentManager"); clock.set_process(false); clock.is_paused=false; clock.current_day=20; clock.current_hour=11; clock.current_minute=0
 for i in range(30): await physics_frame
 var runtime=city.get_node("YSortWorld/WorkerRuntime"); var visuals=runtime.get_node("WorkerVisuals"); visuals.set_process(false); runtime.daily.tool_requirement=Callable()
 var nav=runtime.worksite_navigation; var allowed=nav.for_reed_site()
 if allowed==nav: fail("Reed-specific pond not identified"); return
 var pond1=city.get_node("AuthoredMap/Ground/Base/PondWaterBody_9_-8/CollisionShape2D")
 var pond2=city.get_node("AuthoredMap/Ground/Base/PondWaterBody_13_-13/CollisionShape2D")
 if pond1.disabled or pond2.disabled or nav.is_clear(Vector2(240,-182)) or nav.is_clear(Vector2(168,-102)) or not allowed.is_clear(Vector2(220,-168.5)) or allowed.is_clear(Vector2(168,-102)): fail("Navigation exception leaks or physics disabled"); return
 if runtime.site_navigation(&"ClaySiteA")!=nav or runtime.site_navigation(&"ReedSite")==nav: fail("Site routing scope is incorrect"); return
 var original: Array[PackedVector2Array]=nav.polygons.duplicate()
 var temporary: Array[PackedVector2Array]=original.duplicate()
 var target=Vector2(220,-168.5)
 temporary.append(PackedVector2Array([target+Vector2(-2,-2),target+Vector2(2,-2),target+Vector2(2,2),target+Vector2(-2,2)]))
 nav.replace_polygons(temporary)
 if runtime.site_navigation(&"ReedSite").is_clear(target): fail("Reed route ignored an unrelated obstacle"); quit(1); return
 nav.replace_polygons(original)
 if not runtime.site_navigation(&"ReedSite").is_clear(target): fail("Reed geometry cache did not refresh"); quit(1); return
 print("REED_SCOPED_OBSTACLE_REVISION_PASS")
 var workers=[]
 for i in range(2):
  var worker=load("res://resources/worker_data/worker_data.gd").new(); worker.worker_id="qa_reed_fix_%d"%i; worker.display_name="QA"; worker.payroll_start_day=20; worker.payroll_paid_from_day=20; worker.payroll_paid_until_day=23; worker.payroll_last_attempt_day=20; worker.payroll_period_rate=1; worker.payroll_contract_days=3; worker.payroll_paid_start_minute=20*1440+660
  root.get_node("WorkerDatabase").workers_by_id[worker.worker_id]=worker; workers.append(worker)
  if not runtime.daily.toggle(&"ReedSite",worker.worker_id): fail("Cannot assign worker %d"%i); return
 var reed=runtime.get_node("WorksiteMarkers/ReedSite")
 if not runtime.daily.start(&"ReedSite",runtime._drop_daily_output.bind(reed)): fail("Cannot start reed"); return
 var sealed: Array[PackedVector2Array]=nav.polygons.duplicate()
 var sealed_target: Vector2=workers[0].physical_approach.target
 sealed.append(PackedVector2Array([sealed_target+Vector2(-6,-6),sealed_target+Vector2(6,-6),sealed_target+Vector2(6,6),sealed_target+Vector2(-6,6)]))
 nav.replace_polygons(sealed)
 for frame in range(80):
  await process_frame
  visuals._process(0.05)
 if workers[0].physical_approach.get("arrived",false): fail("Blocked reed worker falsely arrived"); return
 nav.replace_polygons(original)
 print("REED_BLOCKED_TARGET_NOT_ARRIVED_PASS")
 for frame in range(800):
  await process_frame
  visuals._process(0.05)
  if workers[0].physical_approach.get("arrived",false) and workers[1].physical_approach.get("arrived",false): break
 for worker in workers:
  if not worker.physical_approach.get("arrived",false): fail("Worker did not arrive "+worker.worker_id+" "+str(worker.physical_approach)); return
  print("REED_WORKER_ARRIVED ",worker.worker_id," target=",worker.physical_approach.target)
 if workers[0].physical_approach.target==workers[1].physical_approach.target: fail("Worker slots overlap"); return
 clock.advance_minutes(1); visuals._process(0.05)
 if visuals.reed_inside.size()!=2 or visuals.reed_splash==null or not visuals.reed_splash.emitting: fail("Reed working presentation missing "+str(visuals.reed_inside)); return
 print("REED_TWO_WORKERS_WORKING_PASS")
 var before=int(runtime.daily.jobs[&"ReedSite"].progress.get(workers[0].worker_id,0))
 var advanced=clock.advance_minutes(15); visuals._process(0.05)
 if not advanced: fail("Could not advance work time"); return
 print("REED_PROGRESS before=",before," after=",runtime.daily.jobs[&"ReedSite"].progress.get(workers[0].worker_id,0)," stats=",runtime.daily.jobs[&"ReedSite"].stats)
 if int(runtime.daily.jobs[&"ReedSite"].stats[workers[0].worker_id].output)<=0: fail("No reed production"); return
 var reassigned=workers[1]
 if not runtime.daily.withdraw(&"ReedSite",reassigned.worker_id): fail("Reassignment withdraw failed"); return
 var clay=runtime.get_node("WorksiteMarkers/ClaySiteA")
 if not runtime.daily.toggle(&"ClaySiteA",reassigned.worker_id) or not runtime.daily.start(&"ClaySiteA",runtime._drop_daily_output.bind(clay)): fail("Reassignment start failed"); return
 for frame in range(1200):
  await process_frame
  visuals._process(0.05)
  if reassigned.physical_approach.get("owner","")=="ClaySiteA" and reassigned.physical_approach.get("arrived",false): break
 if not reassigned.physical_approach.get("arrived",false): print("REASSIGN_DEBUG normal_start=",nav.is_clear(reassigned.physical_approach.position)," normal_target=",nav.is_clear(reassigned.physical_approach.target)," cached=",visuals.site_paths.get(reassigned.worker_id,{})," exit=",visuals.reed_exit_paths.get(reassigned.worker_id,{})); fail("Reassigned worker did not leave reed and reach clay "+str(reassigned.physical_approach)); return
 print("REED_TO_CLAY_REASSIGNMENT_PASS")
 if not runtime.daily.withdraw(&"ClaySiteA",reassigned.worker_id): fail("Clay withdraw failed"); return
 if not runtime.daily.withdraw(&"ReedSite",workers[0].worker_id): fail("Reed withdraw failed"); return
 for frame in range(800):
  await process_frame
  visuals._process(0.05)
  var done=true
  for worker in workers:
   var actor=visuals.actors.get(worker.worker_id)
   if actor!=null and (actor.has_meta("reed_pond_exit") or not nav.is_clear(actor.global_position+Vector2(0,16))): done=false
  if done: break
 for worker in workers:
  var actor=visuals.actors.get(worker.worker_id)
  if actor==null: fail("Worker visual disappeared after assignment: "+worker.worker_id); return
  if actor.has_meta("reed_pond_exit") or not nav.is_clear(actor.global_position+Vector2(0,16)): fail("Worker cannot exit "+worker.worker_id+" pos="+str(actor.global_position)); return
 print("REED_WORKER_EXIT_PASS")
 print("REED_FIX_QA_PASS")
 quit()
