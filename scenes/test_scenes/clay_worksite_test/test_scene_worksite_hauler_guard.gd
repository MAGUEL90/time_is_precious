extends Node

const DAILY = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd")
const HAULING = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd")
const SESSION = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const SITE: StringName = &"GuardSite"
const LEGACY_HAULER: String = "guard_legacy_hauler"
const NEW_HAULER: String = "guard_new_hauler"
const LABORER: String = "guard_laborer"

class Destination extends RefCounted:
	var quantity: int = 0
	func get_arrival_position() -> Vector2:
		return Vector2(30, 0)
	func accepts_cargo(_item_id: String, amount: int) -> bool:
		return amount > 0
	func try_deliver_at_position(_position: Vector2, cargo: Dictionary) -> bool:
		quantity += int(cargo.quantity)
		cargo.quantity = 0
		return true

var failures: int = 0
var available: int = 3
var schedule
var hauling
var destination: Destination

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	_set_time(420)
	_add_worker(LEGACY_HAULER, WorkerData.Profession.HAULER)
	_add_worker(NEW_HAULER, WorkerData.Profession.HAULER)
	_add_worker(LABORER, WorkerData.Profession.LABORER)
	var session = SESSION.new()
	session.stock = 100
	session.minutes_per_unit = 10.0
	schedule = DAILY.new()
	schedule.setup({SITE: session})
	hauling = HAULING.new()
	destination = Destination.new()
	hauling.speed = 10.0
	hauling.origin_provider = func(_site: StringName, _id: String) -> Vector2: return Vector2.ZERO
	hauling.assigned_destination_provider = func(_path: NodePath): return destination
	hauling.output_count = func(_site: StringName) -> int: return available
	hauling.take_output = _take_output
	schedule.hauling = hauling
	schedule.hauler_ready = func(_site: StringName, _count: int) -> String: return ""

	_expect(schedule.allow_haulers, "The default preserves existing fixture behavior.")
	_expect(schedule.select_hauler(SITE, LEGACY_HAULER, NodePath("OldStorage"), "Old storage", 3), "The existing policy permits a Hauler draft.")
	_expect(schedule.start(SITE, _drop), "The existing policy permits a Hauler assignment.")
	_advance(1)
	_expect(hauling.routes.has(LEGACY_HAULER) and hauling.routes[LEGACY_HAULER].phase == "outbound" and hauling.routes[LEGACY_HAULER].cargo.quantity == 3, "A pre-existing shipment is in flight.")

	schedule.allow_haulers = false
	hauling.routes[LEGACY_HAULER].legacy_final = true
	hauling.routes[LEGACY_HAULER].removing = true
	hauling.payroll_unpaid_minutes_provider = func(_id: String, from_minute: int, to_minute: int) -> int: return to_minute - from_minute
	_expect(not schedule.unavailable(NEW_HAULER).is_empty(), "A new Hauler is unavailable for the restricted map.")
	_expect(not schedule.toggle(SITE, NEW_HAULER), "Direct toggle cannot assign a Hauler.")
	_expect(not schedule.select_hauler(SITE, NEW_HAULER, NodePath("CityStorageArea/DeliveryPoint"), "City Storage", 3), "The Hauler API cannot bypass the map restriction.")
	_expect(schedule.selected[SITE].is_empty() and schedule.hauler_setups.is_empty(), "Rejected requests leave the draft unchanged.")

	# An open draft can outlive a policy change; direct state injection also
	# exercises the final start guard without depending on the selection UI.
	schedule.selected[SITE].append(NEW_HAULER)
	schedule.hauler_setups[NEW_HAULER] = {"destination_path": NodePath("CityStorageArea/DeliveryPoint"), "destination_name": "City Storage", "daily_target": 3}
	_expect(not schedule.start_reason(SITE).is_empty(), "A stale Hauler draft has an unavailable preview.")
	_expect(not schedule.start(SITE, _drop), "A stale Hauler draft cannot start.")
	_expect(not WorkerDatabase.get_worker_data(NEW_HAULER).is_reserved() and not hauling.routes.has(NEW_HAULER), "A failed start creates no worker reservation or route.")
	_expect(schedule.toggle(SITE, NEW_HAULER) and schedule.hauler_setups.is_empty(), "A stale draft can still be removed.")

	_expect(schedule.toggle(SITE, LABORER), "Laborer selection is unchanged.")
	_expect(schedule.start(SITE, _drop), "A Laborer can join while a legacy route is in flight.")
	_advance(3)
	_expect(destination.quantity == 3 and hauling.routes[LEGACY_HAULER].cargo.quantity == 0, "The final legacy route delivers once even when the old contract is unpaid.")
	_expect(schedule.withdraw(SITE, LEGACY_HAULER), "An existing Hauler assignment can still be withdrawn.")
	_advance(3)
	_expect(not hauling.routes.has(LEGACY_HAULER) and not WorkerDatabase.get_worker_data(LEGACY_HAULER).is_reserved(), "The legacy return leg finishes and releases its worker.")
	_expect(destination.quantity == 3 and schedule.jobs[SITE].ids == [LABORER], "Release neither repeats the delivery nor removes the Laborer.")

	schedule.cleanup()
	for id: String in [LEGACY_HAULER, NEW_HAULER, LABORER]:
		WorkerDatabase.workers_by_id.erase(id)
	print("WorksiteHaulerGuardTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _add_worker(id: String, profession: WorkerData.Profession) -> void:
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = id
	worker.profession = profession
	worker.satisfaction = 0.8
	WorkerDatabase.workers_by_id[id] = worker

func _set_time(total: int) -> void:
	TimeComponentManager.current_day = total / 1440
	TimeComponentManager.current_hour = (total % 1440) / 60
	TimeComponentManager.current_minute = total % 60

func _advance(minutes: int) -> void:
	for _index: int in range(minutes):
		_set_time(schedule.now() + 1)
		schedule.tick()

func _take_output(_site: StringName, maximum: int) -> int:
	var count: int = mini(available, maximum)
	available -= count
	return count

func _drop(_quantity: int) -> bool:
	return true

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
