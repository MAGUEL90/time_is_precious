extends Node

## Isolated presentation probe: no checkpoint is opened or written.
## The lab phase reproduces its nonfinite switch after the authored city starts.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const SITE_IDS: Array[String] = ["ClaySiteA", "ClaySiteB", "WoodSite", "ReedSite", "StrawSite", "WaterSite"]
const READY_LABELS: Dictionary = {
	"ClaySiteA": false, "ClaySiteB": false, "WoodSite": false,
	"ReedSite": false, "StrawSite": true, "WaterSite": true,
}
var failures: int = 0
var checks: int = 0
var city: Node
var work: Node
var player: Player
var original: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _settle() -> void:
	for _frame: int in range(3):
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	var root: String = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	var expected: String = OS.get_environment("TIP_QA_PROFILE_ROOT").simplify_path().trim_suffix("/")
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path()
	_check(root.is_absolute_path() and root == expected and user_path.begins_with(root + "/"),
		"Use a dedicated XDG_DATA_HOME matching TIP_QA_PROFILE_ROOT")
	if failures != 0:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	city = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await _settle()
	work = city.get_node("YSortWorld/WorkerRuntime")
	player = city.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	_check(work.finite_resource_sites, "The playable authored city uses finite sites")
	for id: String in SITE_IDS:
		var site: Node2D = work.get_node_or_null("WorksiteMarkers/" + id) as Node2D
		_check(site != null, "The authored city contains " + id)
		if site == null:
			continue
		var icon: Sprite2D = site.get_node("ResourceIcon") as Sprite2D
		var particles: CPUParticles2D = site.get_node("ReadyParticles") as CPUParticles2D
		original[id] = {"site_position": site.global_position, "icon_position": icon.position,
			"icon_offset": icon.offset, "icon_texture": icon.texture,
			"particle_position": particles.position, "stock": int(work.sites[StringName(id)].stock)}
		if id == "ReedSite":
			var cut: Sprite2D = site.get_node("CuttedReed") as Sprite2D
			original[id]["cut_position"] = cut.position
			original[id]["cut_texture"] = cut.texture
		if id == "WoodSite":
			var trees: Array = []
			var stumps: Array = []
			for index: int in range(4):
				var tree: Sprite2D = site.get_node("WoodGrove/Tree%d" % index) as Sprite2D
				var stump: Sprite2D = site.get_node("WoodGrove/Stump%d" % index) as Sprite2D
				trees.append({"position": tree.position, "texture": tree.texture})
				stumps.append({"position": stump.position, "texture": stump.texture})
			original[id]["trees"] = trees
			original[id]["stumps"] = stumps
	if original.size() != SITE_IDS.size():
		get_tree().quit(1)
		return
	await _move_far()
	work._process(0.0)
	_check(work._highlighted_site == null, "Moving away leaves no worksite focused")
	_check_all_ready_labels("ready after _process")
	work._hide_prompts()
	_check_all_ready_labels("ready after _hide_prompts")
	for id: String in ["ClaySiteA", "ClaySiteB"]:
		var site: Node2D = work.get_node("WorksiteMarkers/" + id) as Node2D
		player._set_current_interactable(null)
		player.global_position = site.global_position + Vector2(20, 0)
		await _settle()
		player._refresh_current_interactable()
		work._process(0.0)
		_check(work._highlighted_site == site and site.get_node("InteractPrompt").visible,
			id + " owns E from its sampled collision-free focus position")
		_check(not site.get_node("Label").visible, id + " label stays hidden while focused")
		var other_id: String = "ClaySiteB" if id == "ClaySiteA" else "ClaySiteA"
		_check(not work.get_node("WorksiteMarkers/" + other_id + "/Label").visible,
			other_id + " label stays hidden while the other clay site is focused")
		work._hide_prompts()
		_check(not site.get_node("InteractPrompt").visible, id + " E hides when prompts are cleared")
		_check_all_ready_labels("after clearing " + id + " focus")
	await _move_far()
	for id: String in SITE_IDS:
		await _cycle(id, "finite")
	# The lab starts with the real city, then disables its normal finite policy
	# while directly applying the same depleted/ready presentation transitions.
	work.finite_resource_sites = false
	for id: String in ["ClaySiteB", "WoodSite", "ReedSite", "StrawSite", "WaterSite"]:
		await _cycle(id, "lab_nonfinite")
	work.finite_resource_sites = true
	print("WorksiteLabelLifecycleAudit: ", "PASS" if failures == 0 else "FAIL",
		" checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _move_far() -> void:
	player._set_current_interactable(null)
	player.global_position = Vector2(2000, 2000)
	await _settle()
	player._refresh_current_interactable()

func _check_all_ready_labels(context: String) -> void:
	for id: String in SITE_IDS:
		var label: Label = work.get_node("WorksiteMarkers/" + id + "/Label") as Label
		_check(not label.text.is_empty(), id + " retains its inspector name: " + context)
		_check(label.visible == bool(READY_LABELS[id]), id + " ready label is correct: " + context)

func _cycle(id: String, mode: String) -> void:
	var session = work.sites[StringName(id)]
	var site: Node2D = work.get_node("WorksiteMarkers/" + id) as Node2D
	var stock_before: int = int(original[id].stock)
	_check(stock_before > 0, id + " has a ready reserve for " + mode)
	session.stock = 0
	work._set_site_depleted_presentation(StringName(id), true)
	await _settle()
	work._process(0.0)
	_check(not site.get_node("Label").visible, id + " depleted label stays hidden after _process: " + mode)
	_check_art(site, id, true, mode)
	work._hide_prompts()
	_check(not site.get_node("Label").visible, id + " depleted label stays hidden after _hide_prompts: " + mode)
	session.stock = stock_before
	work._set_site_depleted_presentation(StringName(id), false)
	await _settle()
	work._process(0.0)
	_check(site.get_node("Label").visible == bool(READY_LABELS[id]), id + " ready label restores after _process: " + mode)
	_check_art(site, id, false, mode)
	work._hide_prompts()
	_check(site.get_node("Label").visible == bool(READY_LABELS[id]), id + " ready label restores after _hide_prompts: " + mode)
	_check(int(session.stock) == stock_before, id + " fixture restores its original in-memory stock: " + mode)
	print("WORKSITE_LABEL_CYCLE ", JSON.stringify({"site": id, "mode": mode, "ready_label": site.get_node("Label").visible}))

func _check_art(site: Node2D, id: String, depleted: bool, mode: String) -> void:
	var label: Label = site.get_node("Label") as Label
	var icon: Sprite2D = site.get_node("ResourceIcon") as Sprite2D
	var particles: CPUParticles2D = site.get_node("ReadyParticles") as CPUParticles2D
	var state: String = "depleted" if depleted else "ready"
	var context: String = id + " " + mode + " " + state
	_check(site.global_position == original[id].site_position, context + " keeps site location")
	_check(icon.position == original[id].icon_position and icon.offset == original[id].icon_offset
		and icon.texture == original[id].icon_texture, context + " keeps icon asset and placement")
	_check(not label.text.is_empty(), context + " retains its label text")
	_check(particles.position == original[id].particle_position and particles.visible == not depleted
		and particles.emitting == not depleted, context + " preserves ready particle behavior and placement")
	_check(icon.visible == (not depleted and id != "WoodSite"), context + " retains the expected icon visibility")
	if id == "ReedSite":
		var cut: Sprite2D = site.get_node("CuttedReed") as Sprite2D
		_check(cut.visible == depleted and cut.position == original[id].cut_position
			and cut.texture == original[id].cut_texture, context + " preserves cut-reed asset and placement")
	elif id == "WoodSite":
		for index: int in range(4):
			var tree: Sprite2D = site.get_node("WoodGrove/Tree%d" % index) as Sprite2D
			var stump: Sprite2D = site.get_node("WoodGrove/Stump%d" % index) as Sprite2D
			var old_tree: Dictionary = original[id].trees[index]
			var old_stump: Dictionary = original[id].stumps[index]
			_check(tree.visible == not depleted and tree.position == old_tree.position and tree.texture == old_tree.texture,
				context + " preserves tree %d" % index)
			_check(stump.visible == depleted and stump.position == old_stump.position and stump.texture == old_stump.texture,
				context + " preserves stump %d" % index)
