extends SceneTree

var failures: int = 0
var checks: int = 0

class HaulerDaily:
	extends RefCounted
	func is_hauler(_id: String) -> bool:
		return true

class OwnerFixture:
	extends Node2D
	var daily = HaulerDaily.new()

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var clock: Node = root.get_node("TimeComponentManager")
	var citizens: Node = root.get_node("CitizenManager")
	var workers: Node = root.get_node("WorkerDatabase")
	clock.set_process(false)
	clock.is_paused = true
	var old_citizens: Dictionary = citizens.citizens_by_id.duplicate()
	var old_workers: Dictionary = workers.workers_by_id.duplicate()
	var fixture = OwnerFixture.new()
	root.add_child(fixture)
	var owner = load("res://scenes/test_scenes/clay_worksite_test/clay_worksite_worker_visuals.gd").new()
	fixture.add_child(owner)
	owner.set_process(false)
	for tone: String in ["dark", "light", "tan", "warm"]:
		var id: String = "__native_cart_owner_" + tone
		_check(not old_citizens.has(id) and not old_workers.has(id), "Disposable owner ID does not replace an existing fixture identity.")
		if old_citizens.has(id) or old_workers.has(id):
			continue
		var citizen = load("res://resources/citizen_data/citizen_data.gd").new()
		citizen.citizen_id = id
		citizen.visual_profile = load("res://resources/visual_profile/visual_profile.gd").new()
		citizen.visual_profile.skin_tone = tone
		citizen.visual_profile.clothes_id = "clay_worn_wrap"
		citizen.visual_profile.hair_style = "brown_female_02"
		var worker_script = load("res://resources/worker_data/worker_data.gd")
		var worker = worker_script.new()
		worker.worker_id = id
		worker.profession = worker_script.Profession.HAULER
		citizens.citizens_by_id[id] = citizen
		workers.workers_by_id[id] = worker
		var actor = owner.ensure_actor(id, Vector2.ZERO)
		_check(actor != null, "Standalone Hauler owner creates the linked profile actor.")
		if actor == null:
			continue
		actor.show()
		_check(actor.skin_tone == tone and actor.hair_style == "brown_female_02" and actor.clothes_id == "clay_worn_wrap", "Owner preserves native tone, selected hair and clothing before cart playback: " + tone)
		for action: String in ["walk", "idle_cart", "push_cart", "walk", "idle"]:
			for direction: String in ["right", "left"]:
				owner._play(actor, action, direction)
				var expected_animation: String = "cart_native_core_%s_%s_%s" % [tone, action, direction] if action in ["push_cart", "idle_cart"] else "%s_%s_%s" % [tone, action, direction]
				_check(actor.body_sprite.visible and str(actor.body_sprite.animation) == expected_animation, "Actual owner keeps native body across commute/cart/departure: %s/%s/%s" % [tone, action, direction])
				if action in ["push_cart", "idle_cart"]:
					_check(actor.body_sprite.flip_h == (direction == "left") and actor.hair_sprite.flip_h == (direction == "left") and actor.clothes_sprite.flip_h == (direction == "left"), "Owner mirrors native cart layers consistently for direction.")
				_check(actor.hair_sprite.visible and actor.clothes_sprite.visible, "Selected matching hair and clay clothing remain visible through owner transitions.")
				if actor.cart_visual != null:
					_check(actor.cart_visual.visible == (action in ["push_cart", "idle_cart"]), "Cart visibility follows action without changing equipment or profile.")
				else:
					_check(action == "walk", "No cart needed before first cart action.")
				_check(citizen.visual_profile.skin_tone == tone and citizen.visual_profile.hair_style == "brown_female_02" and citizen.visual_profile.clothes_id == "clay_worn_wrap", "Linked source profile stays unchanged.")
	fixture.free()
	citizens.citizens_by_id = old_citizens
	workers.workers_by_id = old_workers
	print("CartProfileOwnerTest: %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
