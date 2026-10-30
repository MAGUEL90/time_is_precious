extends RefCounted

## Versioned main-city checkpoint. Explicit owners, no arbitrary script/path loading.
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const WORKSITES = preload("res://scenes/new_scenes/save_game/city_save_worksites.gd")
const PICKUP: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")
const PALMS = preload("res://scenes/new_scenes/save_game/city_save_palms.gd")
const SOURCES = preload("res://scenes/new_scenes/save_game/city_save_pickup_sources.gd")
const VERSION: int = 8
const HOME_PATH: String = "res://scenes/player_home_interior/player_home_interior.tscn"
const GROUPS: Dictionary = {
	"clock": ["current_day", "current_hour", "current_minute", "current_weather", "_timer"],
	"player": ["global_position", "fatigue", "hunger", "focus", "current_experience", "last_sleep_day", "last_collapse_day", "total_collapse_count"],
	"inventory": ["items", "max_load"],
	"city_storage": ["items", "units", "food_portions", "_unit_sequence"],
	"stock": ["food_supply", "clothing_supply", "treasury_shekel", "shelter_capacity"],
	"citizens": ["citizens_by_id"],
	"workers": ["workers_by_id", "dismissed_workers"],
	"needs": ["last_food_fulfilled_count", "last_food_unfulfilled_count", "last_clothing_fulfilled_count", "last_clothing_unfulfilled_count", "last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count", "last_processed_day", "last_food_processed_day", "last_clothing_processed_day", "clothing_allocations", "last_needs_results"],
	"immigration": ["pending_immigrants", "immigration_pressure"],
	"generator": ["counter_id"],
	"dialogue": ["intro_seen"],
	"workshop_storage": ["items", "claimable_outputs", "unpaid_claims_ledger", "max_load", "_next_fee_sequence", "_next_output_lot_sequence", "output_lots"],
	"work": ["active_orders", "service_fee_by_order", "service_fee_currency_by_order", "_last_total_minutes"],
	"process": ["stations", "current_weather_key", "_last_total_minutes", "_auto_pull_batch_size"],
	"facilities": ["facility_levels"],
	"city": ["level", "progress", "last_daily", "last_event", "last_awarded_day", "_last_breach_id"],
	"raid": ["notification_seen_keys", "phase", "wall_hp", "wall_level", "watchtower_built", "_work_base_max_hp", "_latest_minute", "_attack_at", "_departure_at", "_party", "_expedition_sequence", "_composition_stage", "_elapsed", "_hits", "_start_hp", "_attack_strength", "_report", "_report_sequence", "_work_kind", "_work_remaining", "_work_total", "_work_restore_hp", "_work_paid", "last_work_message", "_breach_at", "_next_loot_at", "_loot_weight", "_stolen", "_retreat_reason", "_breach_losses"],
	"merchant": ["_stock", "_offers", "_demand", "_budget", "_visit_day", "_latest_minute", "_present"]
}
const PLOT_FIELDS: Array[String] = ["order_id", "phase", "clearing_remaining", "clearing_by_player", "worker_ids", "started_at", "completes_at", "_latest_time", "payroll_work_remainder"]
var error: String = ""
var prepared: Dictionary = {}
var prepared_location: String = "city"
var _sites = WORKSITES.new()
var _sources = SOURCES.new()
var _legacy_palms = PALMS.new()

func owners(map: Node) -> Dictionary:
	return {"clock": TimeComponentManager, "player": map.get_node("YSortWorld/Player"),
		"inventory": Inventory, "city_storage": WorkStateRuntime.get_node("CityToolStorage"),
		"stock": CityStockManager, "citizens": CitizenManager, "workers": WorkerDatabase,
		"needs": CitizenNeedsManager, "immigration": ImmigrationManager, "generator": CitizenGenerator,
		"dialogue": BaseDialogueManager, "workshop_storage": WorkShopStorage, "work": WorkManager,
		"process": ProcessManager, "facilities": WorkshopFacilityManager,
		"city": WorkStateRuntime.get_node("CityProgression"), "raid": WorkStateRuntime.get_node("CityRaid"),
		"merchant": WorkStateRuntime.get_node("CommonTravelingMerchant")}

func worksite(map: Node) -> Node:
	var local: Node = map.get_node_or_null("YSortWorld/WorkerRuntime")
	if local != null:
		return local
	var store: Node = WorkStateRuntime.get_node_or_null("CitySave")
	return store.parked_worksite if store != null else null

func is_home(map: Node) -> bool:
	return is_instance_valid(map) and map.scene_file_path == HOME_PATH

func plots(map: Node) -> Dictionary:
	if is_home(map):
		return WorkStateRuntime.get_node("CitySave").city_plots
	var result: Dictionary = {}
	for plot: Node in map.get_tree().get_nodes_in_group("workshop_plots"):
		if map.is_ancestor_of(plot):
			result[str(plot.construction.name)] = plot.construction
	return result

func busy_reason(map: Node) -> String:
	if not is_instance_valid(map) or not map.is_inside_tree():
		return "Return to the city first."
	if not is_instance_valid(worksite(map)):
		return "Return to the city first."
	var nodes: Dictionary = owners(map)
	var p: Player = nodes.player
	if SceneTransition.is_transitioning or map.get_tree().paused or TimeComponentManager.is_paused or not p.can_move or p.is_sleeping or p.is_collapsing or p.current_npc_dialogue != null or p.inventory_is_open or p.claim_menu_is_open:
		return "Finish the current interaction first."
	var inventory_ui: Node = map.get_node_or_null("InventoryUI")
	if inventory_ui != null and inventory_ui.is_inventory_action_busy:
		return "Finish the inventory action first."
	var nightmare: Node = map.get_node_or_null("YSortWorld/NightmareWorld")
	if nightmare != null and nightmare.get("is_active") == true:
		return "Finish the nightmare first."
	if worksite(map)._working:
		return "Finish gathering first."
	if nodes.city_storage._transfer_in_progress or nodes.merchant._trading or nodes.raid._advancing or nodes.raid._resolving or nodes.raid._starting_work or nodes.raid._refund_pending:
		return "Wait for the current transaction."
	if WorkerDatabase._payroll_settling:
		return "Wait for payroll settlement."
	if CitizenNeedsManager._processing_daily_needs or CitizenNeedsManager._processing_food or CitizenNeedsManager._processing_clothing:
		return "Wait for daily settlement."
	for plot: Node in plots(map).values():
		if plot._starting or plot.clearing_by_player:
			return "Finish clearing first."
	return ""

func capture(map: Node) -> Dictionary:
	error = ""
	var nodes: Dictionary = owners(map)
	var raw: Dictionary = {}
	for key: String in GROUPS:
		raw[key] = fields(nodes[key], GROUPS[key])
	# Icons are authored presentation, never file-controlled resources.
	raw.raid = _without_icons(raw.raid)
	raw["rng"] = {"raid": _rng(nodes.raid._rng), "merchant": _rng(nodes.merchant._request_rng), "immigration": _rng(ImmigrationManager.rng)}
	raw["plots"] = {}
	for id: String in plots(map):
		raw.plots[id] = fields(plots(map)[id], PLOT_FIELDS)
	raw["work_sources"] = _store_tokens(WorkManager.source_item_store_by_order_id, nodes)
	raw["work_outputs"] = _store_tokens(WorkManager.output_item_store_by_order_id, nodes)
	raw["order_plots"] = {}
	for id: String in WorkManager.active_orders:
		raw.order_plots[id] = str(WorkManager.active_orders[id].get_meta("visual_plot_id", ""))
	raw["initial_cart_supplied"] = bool(nodes.city_storage.get_meta("initial_worksite_cart_supplied", false))
	raw["city_drops"] = _capture_city_drops(map)
	raw["pickup_sources"] = _sources.capture()
	if not _sources.validate(raw.pickup_sources):
		error = "Invalid pickup source state."
	raw["worksites"] = _sites.capture(worksite(map))
	if not _sites.error.is_empty():
		error = _sites.error
	if error.is_empty() and not _validate_approaches(raw, map):
		return {}
	if not error.is_empty():
		return {}
	_without_transient_worker_assignments(raw)
	var values = VALUES.new()
	var payload: Variant = values.encode(raw)
	if not values.error.is_empty():
		error = values.error
		return {}
	return {"schema_version": VERSION, "scenario": "city_mvp", "location": "home" if is_home(map) else "city", "state": payload}

func prepare(document: Dictionary, map: Node) -> bool:
	error = ""
	prepared = {}
	prepared_location = "city"
	# Version 1 was a city-only manual checkpoint. Its state fields stay intact.
	var version: Variant = document.get("schema_version")
	if (version != 1 and version != 2 and version != 3 and version != 4 and version != 5 and version != 6 and version != 7 and version != VERSION) or document.get("scenario") != "city_mvp" or not document.has("state"):
		return fail("Unsupported checkpoint version.")
	if version == 1:
		if document.size() != 3:
			return fail("Invalid legacy checkpoint header.")
	else:
		if document.size() != 4 or document.get("location") not in ["city", "home"]:
			return fail("Invalid checkpoint location.")
		prepared_location = document.location
	var values = VALUES.new()
	values.allow_legacy_worker_fields = version < 5
	values.allow_legacy_contract_fields = version < 7
	values.allow_legacy_approach_field = version < 8
	var raw: Variant = values.decode(document.state)
	if not values.error.is_empty() or not raw is Dictionary:
		return fail("Invalid checkpoint values. " + values.error)
	var nodes: Dictionary = owners(map)
	if raw.size() != GROUPS.size() + (9 if version >= 3 else 8):
		return fail("Incomplete checkpoint.")
	if version < 7:
		if not raw.get("raid") is Dictionary or raw.raid.has("notification_seen_keys"):
			return fail("Invalid legacy notification state.")
		raw.raid["notification_seen_keys"] = {}
	for key: String in GROUPS:
		if not _valid_fields(raw.get(key), nodes[key], GROUPS[key]):
			return fail("Invalid " + key + " state.")
	for key: String in ["rng", "plots", "work_sources", "work_outputs", "order_plots", "worksites"]:
		if not raw.get(key) is Dictionary:
			return fail("Missing " + key + ".")
	if version < 6:
		# Earlier plots did not accumulate partial paid-team minutes.
		for plot: Variant in raw.plots.values():
			if not plot is Dictionary or plot.has("payroll_work_remainder"):
				return fail("Invalid legacy workshop plot.")
			plot["payroll_work_remainder"] = 0
	if not raw.get("city_drops") is Array:
		return fail("Missing dropped inventory items.")
	for drop: Variant in raw.city_drops:
		if not _record(drop, {"item_id": TYPE_STRING, "quantity": TYPE_INT, "position": TYPE_VECTOR2}):
			return fail("Invalid dropped inventory item.")
		if ItemDatabase.get_item_data(drop.item_id) == null or drop.quantity <= 0 or drop.position.length() > 100000:
			return fail("Invalid dropped item quantity or position.")
	if not raw.get("initial_cart_supplied") is bool:
		return fail("Invalid initial supplies.")
	if not _validate_core(raw, map) or not _validate_people(raw) or not _validate_work(raw, map) or not _validate_records(raw):
		return false
	if not _sites.validate(raw.worksites, worksite(map), raw.workers.workers_by_id, raw.workers.dismissed_workers):
		return fail(_sites.error)
	if not _validate_approaches(raw, map):
		return false
	if version >= 4:
		if not _sources.validate(raw.get("pickup_sources")):
			return fail("Invalid pickup source state.")
	else:
		if raw.has("pickup_sources") or not _sources.validate(_sources.capture()):
			return fail("Invalid legacy pickup source state.")
		var migrated: Dictionary = {}
		if version == 3:
			if not _legacy_palms.validate(raw.get("date_palms")):
				return fail("Invalid legacy date palm state.")
			migrated = raw.date_palms
			raw.erase("date_palms")
		elif raw.has("date_palms"):
			return fail("Invalid legacy date palm state.")
		# Legacy files cannot describe newly registered sources. Initialize only
		# those missing histories on apply; never infer depletion from Inventory.
		raw["pickup_sources"] = migrated
	_without_transient_worker_assignments(raw)
	prepared = raw
	return true

func _without_transient_worker_assignments(raw: Dictionary) -> void:
	# Workshop selector drafts have no persistent owner. Keep actual reservations,
	# but do not restore an idle citizen as ASSIGNED to a selection that was not saved.
	# Copy the affected resources: capture/validation must never release a live draft.
	var people: Dictionary = raw.citizens.citizens_by_id.duplicate()
	for id: String in raw.workers.workers_by_id:
		var worker: WorkerData = raw.workers.workers_by_id[id]
		var citizen: CitizenData = people.get(id)
		if citizen == null or citizen.employment_status != CitizenData.EmploymentStatus.ASSIGNED:
			continue
		if worker.is_reserved() or worker.current_work_status != WorkerData.WorkStatus.IDLE:
			continue
		var restored_citizen: CitizenData = citizen.duplicate()
		restored_citizen.employment_status = CitizenData.EmploymentStatus.HIRED
		people[id] = restored_citizen
	raw.citizens = raw.citizens.duplicate()
	raw.citizens.citizens_by_id = people

func apply_prepared(map: Node, reopen_hub: bool = true) -> void:
	# No yields, gameplay commands, or signals until every owner is restored.
	var nodes: Dictionary = owners(map)
	for key: String in GROUPS:
		assign_fields(nodes[key], prepared[key])
	_sources.restore(prepared.pickup_sources)
	_restore_rng(nodes.raid._rng, prepared.rng.raid)
	_restore_rng(nodes.merchant._request_rng, prepared.rng.merchant)
	_restore_rng(ImmigrationManager.rng, prepared.rng.immigration)
	var plot_nodes: Dictionary = plots(map)
	for id: String in plot_nodes:
		assign_fields(plot_nodes[id], prepared.plots[id])
	_restore_stores(WorkManager.source_item_store_by_order_id, prepared.work_sources, nodes)
	_restore_stores(WorkManager.output_item_store_by_order_id, prepared.work_outputs, nodes)
	for id: String in WorkManager.active_orders:
		var order: WorkOrder = WorkManager.active_orders[id]
		if order.job_id == "mudbrick_make":
			order.job_icon = preload("res://resources/job_data/mudbrick_make.tres").icon
		if not prepared.order_plots[id].is_empty():
			order.set_meta("visual_plot_id", prepared.order_plots[id])
	nodes.city_storage.set_meta("initial_worksite_cart_supplied", prepared.initial_cart_supplied)
	_sites.restore(prepared.worksites, worksite(map))
	_restore_city_drops(prepared.city_drops, map)
	_restore_party_icons(nodes.raid._party, nodes.raid.config.party_profile)
	_restore_party_icons(nodes.raid._report, nodes.raid.config.party_profile)
	nodes.player.velocity = Vector2.ZERO
	PlayerRuntimeState.capture(nodes.player)
	TimeComponentManager.set_block_signals(true)
	TimeComponentManager.day_cycle(true)
	TimeComponentManager.environment.color = TimeComponentManager._target_environment_color
	TimeComponentManager.set_block_signals(false)
	var ui: RaidUI = nodes.raid.get_node("RaidUI")
	ui._last_phase = nodes.raid.phase
	ui._last_shown_report_id = int(nodes.raid._report.get("id", -1))
	ui.show_last_raid = false
	ui._clear_inspected_raiders(false)
	nodes.raid.set_process(nodes.raid.is_raid_active())
	# Ledger cursors were restored with the clock; this refresh emits no elapsed minute/day.
	TimeComponentManager.emit_time_signal()
	_sources.refresh()
	Inventory.items_changed.emit()
	nodes.city_storage.changed.emit()
	CitizenNeedsManager.needs_changed.emit()
	nodes.city.changed.emit()
	nodes.raid.changed.emit()
	nodes.merchant.changed.emit()
	for plot: Node in plot_nodes.values():
		plot.changed.emit()
	nodes.player.condition_changed.emit()
	nodes.player.experience_changed.emit()
	if reopen_hub:
		ui.open_details()

func fields(owner: Object, names: Array) -> Dictionary:
	var result: Dictionary = {}
	for key: String in names:
		result[key] = owner.get(key)
	return result

func assign_fields(owner: Object, data: Dictionary) -> void:
	for key: String in data:
		var current: Variant = owner.get(key)
		if current is Dictionary:
			current.assign(data[key])
		elif current is Array:
			current.assign(data[key])
		else:
			owner.set(key, data[key])

func _valid_fields(data: Variant, owner: Object, names: Array) -> bool:
	if not data is Dictionary or data.size() != names.size():
		return false
	for key: String in names:
		if not data.has(key) or typeof(data[key]) != typeof(owner.get(key)):
			return false
		var current: Variant = owner.get(key)
		if current is Dictionary and current.is_typed():
			for k: Variant in data[key]:
				if typeof(k) != current.get_typed_key_builtin() or not _element_matches(data[key][k], current.get_typed_value_builtin(), current.get_typed_value_script()):
					return false
		if current is Array and current.is_typed():
			for v: Variant in data[key]:
				if not _element_matches(v, current.get_typed_builtin(), current.get_typed_script()):
					return false
	return true

func _element_matches(value: Variant, type: int, script: Variant) -> bool:
	return (type == TYPE_NIL or typeof(value) == type) and (script == null or (value is Object and value.get_script() == script))

func _rng(random: RandomNumberGenerator) -> Dictionary:
	return {"seed": random.seed, "state": random.state}

func _restore_rng(random: RandomNumberGenerator, data: Dictionary) -> void:
	random.seed = data.seed
	random.state = data.state

func _store_tokens(stores: Dictionary, nodes: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in stores:
		var token: String = ""
		for key: String in ["inventory", "workshop_storage", "city_storage"]:
			if stores[id] == nodes[key]:
				token = key
		if token.is_empty():
			error = "Unsupported work storage."
		result[id] = token
	return result

func _restore_stores(target: Dictionary, data: Dictionary, nodes: Dictionary) -> void:
	target.clear()
	for id: String in data:
		target[id] = nodes[data[id]]

func _without_icons(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			if key == "icon":
				continue
			result[key] = _without_icons(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_without_icons(item))
		return result
	return value

func _restore_party_icons(value: Variant, profile: Resource) -> void:
	if value is Dictionary:
		if value.has("units"):
			for unit: Dictionary in value.units:
				for config: Resource in profile.unit_types:
					if str(config.id) == unit.id:
						unit["icon"] = config.icon
		for child: Variant in value.values():
			_restore_party_icons(child, profile)
	elif value is Array:
		for child: Variant in value:
			_restore_party_icons(child, profile)

func fail(message: String) -> bool:
	error = message
	return false

func _counts(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for id: Variant in value:
		if not id is String or ItemDatabase.get_item_data(id) == null or not value[id] is int or value[id] < 0:
			return false
	return true

func _validate_core(raw: Dictionary, map: Node) -> bool:
	var c: Dictionary = raw.clock
	if c.current_day < 0 or c.current_hour < 0 or c.current_hour > 23 or c.current_minute < 0 or c.current_minute > 59 or c.current_weather not in ["clear", "cloudy", "rainy", "storm"] or c._timer < 0:
		return fail("Invalid clock.")
	for k: String in ["fatigue", "hunger", "focus"]:
		if raw.player[k] < 0 or raw.player[k] > 1:
			return fail("Invalid player condition.")
	if raw.player.current_experience < 0 or raw.player.total_collapse_count < 0 or raw.player.global_position.length() > 100000:
		return fail("Invalid player state.")
	if raw.city.level < 1 or raw.city.progress < 0 or raw.city.progress > 100 or raw.city._last_breach_id < 0 or raw.city.last_awarded_day < raw.needs.last_processed_day:
		return fail("Invalid city progress.")
	for stock: Variant in [raw.inventory.items, raw.city_storage.items, raw.workshop_storage.items, raw.merchant._stock, raw.merchant._demand, raw.raid._stolen, raw.raid._work_paid]:
		if not _counts(stock):
			return fail("Unknown item or invalid stock count.")
	if raw.inventory.max_load < 0 or raw.workshop_storage.max_load < 0 or raw.merchant._budget < 0 or raw.city_storage._unit_sequence < 0:
		return fail("Invalid storage capacity or budget.")
	for v: int in raw.stock.values():
		if v < 0:
			return fail("Invalid city supplies.")
	if raw.rng.size() != 3:
		return fail("Missing random state.")
	for key: String in ["raid", "merchant", "immigration"]:
		var r: Variant = raw.rng.get(key)
		if not r is Dictionary or r.size() != 2 or not r.get("seed") is int or not r.get("state") is int:
			return fail("Invalid random state.")
	var raid: Dictionary = raw.raid
	for key: Variant in raid.notification_seen_keys:
		var value: Variant = raid.notification_seen_keys[key]
		if not key is String or not value is String or key.length() > 256 or value.length() > 256:
			return fail("Invalid notification acknowledgement.")
	if raid.phase not in ["unbuilt", "safe", "warning", "attacking", "looting", "recovery"] or raid.wall_level < 0 or raid.wall_level > 2 or raid.wall_hp < 0 or raid.wall_hp > (80 if raid.wall_level == 2 else 50):
		return fail("Invalid wall state.")
	if raid._work_kind not in ["", "build", "rebuild", "repair", "upgrade", "watchtower"] or raid._work_remaining < 0 or raid._work_remaining > raid._work_total or raid._elapsed < 0 or raid._elapsed > 60.0 or raid._loot_weight < 0 or raid._loot_weight > 10.0 or raid._hits < 0 or raid._report_sequence < 0:
		return fail("Invalid raid timers.")
	if raid._composition_stage not in [&"early", &"developing", &"advanced"]:
		return fail("Unknown raid stage.")
	if raid.phase in ["attacking", "looting"] and raid._party.is_empty():
		return fail("Active raid party missing.")
	if raid.phase == "looting" and raid._start_hp > 0 and raw.city._last_breach_id != raid._report_sequence + 1:
		return fail("Breach settlement cursor differs.")
	if not _valid_party(raid._party, owners(map).raid.config.party_profile):
		return fail("Invalid raider party.")
	if not raid._report.is_empty() and (not raid._report.get("id") is int or raid._report.id > raid._report_sequence):
		return fail("Invalid raid report.")
	for item_id: Variant in raw.city_storage.food_portions:
		var item: ItemData = ItemDatabase.get_item_data(str(item_id))
		var quantity: Variant = raw.city_storage.food_portions[item_id]
		if item == null or item.food_supply_value <= 0 or not quantity is int or quantity < 0 or quantity >= item.food_supply_value:
			return fail("Invalid opened food portions.")
	return true

func _valid_party(party: Dictionary, profile: Resource) -> bool:
	if party.is_empty():
		return true
	if not party.get("units") is Array or not party.get("attack_strength") is int or not party.get("total_count") is int or not party.get("travel_total_minutes") is int:
		return false
	var strength: int = 0
	var count: int = 0
	var days: int = 0
	var seen: Array[String] = []
	for unit: Variant in party.units:
		if not unit is Dictionary or not unit.get("id") is String or not unit.get("count") is int or unit.count <= 0 or seen.has(unit.id):
			return false
		var found: bool = false
		for config: Resource in profile.unit_types:
			if str(config.id) == unit.id and unit.get("attack") == config.attack and unit.get("travel_days") == config.travel_days:
				found = true
				strength += unit.count * config.attack
				days = maxi(days, config.travel_days)
		if not found:
			return false
		count += unit.count
		seen.append(unit.id)
	return strength == party.attack_strength and count == party.total_count and days * 1440 == party.travel_total_minutes

func _validate_people(raw: Dictionary) -> bool:
	var workers: Dictionary = raw.workers.workers_by_id
	for id: String in raw.citizens.citizens_by_id:
		var person: CitizenData = raw.citizens.citizens_by_id[id]
		if person.citizen_id != id or person.satisfaction < 0 or person.satisfaction > 1 or person.reliability < 0 or person.reliability > 1 or person.population_status < 0 or person.population_status > 3 or person.employment_status < 0 or person.employment_status > 3:
			return fail("Invalid citizen.")
	for group: Dictionary in [workers, raw.workers.dismissed_workers]:
		for id: String in group:
			var worker: WorkerData = group[id]
			if worker.worker_id != id or worker.current_work_status < 0 or worker.current_work_status > 4 or worker.profession_xp < 0:
				return fail("Invalid worker.")
			if not _valid_onboarding(worker):
				return fail("Invalid worker payroll state.")
	for id: Variant in raw.city_storage.units:
		var unit: Variant = raw.city_storage.units[id]
		if not id is String or not unit is Dictionary or not unit.get("tool_id") is String or not unit.get("worker_id") is String or not unit.get("name") is String:
			return fail("Invalid equipment unit.")
		if unit.tool_id not in ["cart", "basic_glove", "stone_hammer"] or (not unit.worker_id.is_empty() and not workers.has(unit.worker_id)):
			return fail("Equipment owner missing.")
	return true

func _validate_approaches(raw: Dictionary, map: Node) -> bool:
	var now: int = raw.clock.current_day * 1440 + raw.clock.current_hour * 60 + raw.clock.current_minute
	var native_plots: Dictionary = plots(map)
	for group: Dictionary in [raw.workers.workers_by_id, raw.workers.dismissed_workers]:
		for id: String in group:
			var worker: WorkerData = group[id]
			var approach: Dictionary = worker.physical_approach
			if not WorkerData.physical_approach_valid(approach):
				return fail("Invalid worker physical approach.")
			if approach.is_empty():
				continue
			if not raw.workers.workers_by_id.has(id) or worker.current_order_id.is_empty() or (approach.arrived and approach.arrival_minute > now):
				return fail("Worker physical approach has no active owner.")
			if approach.kind == "site":
				var job: Dictionary = raw.worksites.jobs.get(approach.owner, {})
				if job.is_empty() or not job.ids.has(id) or worker.current_order_id != job.order or not job.starts.has(id):
					return fail("Worker physical approach has no site assignment.")
				var prefix: String = "%s:%d:" % [job.order, int(job.starts[id])]
				var day_text: String = approach.task.trim_prefix(prefix)
				var first_task_day: int = int(job.starts[id]) / 1440
				var latest_task_day: int = maxi(raw.clock.current_day, first_task_day)
				if not approach.task.begins_with(prefix) or not day_text.is_valid_int() or str(int(day_text)) != day_text or int(day_text) < first_task_day or int(day_text) > latest_task_day:
					return fail("Worker physical approach has an invalid site task.")
				# A withdrawn teammate can change the current slot index. Both
				# existing authored slots remain valid for an established journey.
				# Validate before restore without consulting live job membership.
				var marker: Node2D = worksite(map).get_node_or_null("WorksiteMarkers/" + approach.owner) as Node2D
				if marker == null:
					return fail("Worker physical approach has no authored site marker.")
				var left_entry: Vector2 = marker.global_position + Vector2(-10, 8)
				var right_entry: Vector2 = marker.global_position + Vector2(10, 8)
				if worksite(map).has_method("site_slot_destination"):
					left_entry = worksite(map).site_slot_destination(StringName(approach.owner), 0)
					right_entry = worksite(map).site_slot_destination(StringName(approach.owner), 1)
				if approach.target.distance_to(left_entry) > 0.1 and approach.target.distance_to(right_entry) > 0.1:
					return fail("Worker physical approach differs from its authored site.")
				continue
			var found: bool = false
			for plot_id: String in raw.plots:
				var plot: Dictionary = raw.plots[plot_id]
				if plot.order_id != approach.owner:
					continue
				if approach.target.distance_to(native_plots[plot_id].worker_entry_position) > 0.1:
					return fail("Worker physical approach differs from its authored plot.")
				if plot.phase in ["clearing", "building"] and plot.worker_ids.has(id) and worker.current_order_id == plot.order_id and approach.task == plot.order_id + ":" + plot.phase:
					found = true
				var order: WorkOrder = raw.work.active_orders.get(approach.task)
				if order != null and order.worker_id == id and order.worker_kind == WorkOrder.Worker_Type.NPC and order.current_status == WorkOrder.Status.RUNNING and raw.order_plots.get(order.order_id) == plot.order_id and worker.current_order_id == order.order_id:
					found = true
			if not found:
				return fail("Worker physical approach has no matching workshop task.")
	return true

func _validate_work(raw: Dictionary, map: Node) -> bool:
	var plot_nodes: Dictionary = plots(map)
	if raw.plots.size() != plot_nodes.size():
		return fail("Workshop layout differs.")
	var plot_ids: Array[String] = [""]
	for id: String in plot_nodes:
		if not _valid_fields(raw.plots.get(id), plot_nodes[id], PLOT_FIELDS):
			return fail("Invalid workshop plot.")
		var p: Dictionary = raw.plots[id]
		if p.order_id != plot_nodes[id].order_id or p.phase not in ["uncleared", "clearing", "empty", "building", "built"] or p.clearing_by_player or p.clearing_remaining < 0:
			return fail("Invalid construction state.")
		if p.payroll_work_remainder < 0 or p.payroll_work_remainder >= maxi(1, p.worker_ids.size()):
			return fail("Invalid construction payroll progress.")
		plot_ids.append(p.order_id)
		for worker: Variant in p.worker_ids:
			# Finished plots retain historical team IDs after employment ends.
			# Active construction still requires a member of the hired roster.
			var archived: bool = p.phase in ["empty", "built"] and raw.workers.dismissed_workers.has(worker)
			if not worker is String or (not raw.workers.workers_by_id.has(worker) and not archived):
				return fail("Construction worker missing.")
	var orders: Dictionary = raw.work.active_orders
	if raw.order_plots.size() != orders.size():
		return fail("Missing workshop assignment.")
	for id: String in orders:
		var order: WorkOrder = orders[id]
		if order.order_id != id or order.end_time_total_minutes < order.start_time_total_minutes or not _counts(order.inputs_snapshot) or not _counts(order.outputs_snapshot) or not raw.order_plots.get(id) in plot_ids:
			return fail("Invalid work order.")
		if not order.worker_id.is_empty() and not raw.workers.workers_by_id.has(order.worker_id):
			return fail("Order worker missing.")
	for bindings: Dictionary in [raw.work_sources, raw.work_outputs]:
		for id: Variant in bindings:
			if not orders.has(id) or bindings[id] not in ["inventory", "workshop_storage", "city_storage"]:
				return fail("Invalid order storage.")
	for id: String in raw.facilities.facility_levels:
		if not WorkshopFacilityManager.has_facility(id) or raw.facilities.facility_levels[id] < 0 or raw.facilities.facility_levels[id] > WorkshopFacilityManager.get_facility_max_level(id):
			return fail("Invalid facility.")
	for id: String in raw.process.stations:
		var station: StationState = raw.process.stations[id]
		if station.station_id != id or station.slots_total != station.slots.size() or station.slots_total < 0 or station.slots_total > 100:
			return fail("Invalid process station.")
		for batch: Variant in station.slots:
			if batch == null:
				continue
			if not batch is ProcessBatch or not ProcessManager.processes.has(batch.process_id) or batch.quantity < 0 or batch.progress_minutes < 0 or batch.duration_minutes <= 0 or batch.slot_index < 0 or batch.slot_index >= station.slots.size():
				return fail("Invalid process batch.")
	return true

func _record(value: Variant, spec: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	for key: String in spec:
		if not value.has(key) or typeof(value[key]) != spec[key]:
			return false
	return true

func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not entry is String:
			return false
	return true

func _validate_records(raw: Dictionary) -> bool:
	if not raw.city.last_daily.is_empty():
		if not _record(raw.city.last_daily, {"day": TYPE_INT, "food": TYPE_INT, "clothing": TYPE_INT, "satisfaction": TYPE_INT, "wall": TYPE_INT, "total": TYPE_INT, "applied": TYPE_INT}):
			return fail("Invalid daily city ledger.")
	for id: Variant in raw.needs.clothing_allocations:
		var allocation: Variant = raw.needs.clothing_allocations[id]
		if not id is String or not _record(allocation, {"item_id": TYPE_STRING, "issued_day": TYPE_INT, "expires_day": TYPE_INT}):
			return fail("Invalid clothing allocation.")
		if ItemDatabase.get_item_data(allocation.item_id) == null or allocation.expires_day < allocation.issued_day:
			return fail("Invalid clothing allocation.")
	for id: Variant in raw.needs.last_needs_results:
		var result: Variant = raw.needs.last_needs_results[id]
		if not id is String or not _record(result, {"evaluated": TYPE_BOOL, "day": TYPE_INT, "food": TYPE_BOOL, "clothing": TYPE_BOOL, "shelter": TYPE_BOOL, "clothing_days_left": TYPE_INT, "satisfaction": TYPE_FLOAT, "reliability": TYPE_FLOAT, "satisfaction_delta": TYPE_FLOAT, "reliability_delta": TYPE_FLOAT, "missing": TYPE_ARRAY}) or not _strings(result.missing):
			return fail("Invalid daily needs ledger.")
	for id: Variant in raw.merchant._offers:
		var offer: Variant = raw.merchant._offers[id]
		if not id is String or ItemDatabase.get_item_data(id) == null or not _record(offer, {"stock": TYPE_INT, "buy_price": TYPE_INT, "sell_price": TYPE_INT, "requested": TYPE_INT}):
			return fail("Invalid merchant offer.")
		for key: String in ["stock", "buy_price", "sell_price", "requested"]:
			if offer[key] < 0:
				return fail("Invalid merchant offer amount.")
	var report: Dictionary = raw.raid._report
	if not report.is_empty():
		if not _record(report, {"id": TYPE_INT, "outcome": TYPE_STRING, "day": TYPE_INT, "hits": TYPE_INT, "wall_damage": TYPE_INT, "stolen": TYPE_DICTIONARY, "buildings_destroyed": TYPE_DICTIONARY, "satisfaction_drop": TYPE_FLOAT, "citizens_fled": TYPE_ARRAY, "breach_seconds": TYPE_FLOAT, "looting_seconds": TYPE_FLOAT, "loot_weight": TYPE_FLOAT, "loot_capacity_weight": TYPE_FLOAT, "loot_preference": TYPE_STRING, "retreat_reason": TYPE_STRING}) or not _counts(report.stolen) or not _strings(report.citizens_fled):
			return fail("Invalid raid report details.")
		for key: Variant in report.buildings_destroyed:
			if not key is String or not report.buildings_destroyed[key] is int or report.buildings_destroyed[key] < 0:
				return fail("Invalid building losses.")
	var losses: Dictionary = raw.raid._breach_losses
	if not losses.is_empty() and (not _record(losses, {"satisfaction_drop": TYPE_FLOAT, "residents_affected": TYPE_INT, "citizens_fled": TYPE_ARRAY}) or not _strings(losses.citizens_fled)):
		return fail("Invalid breach ledger.")
	var fees: Dictionary = {}
	for fee: Dictionary in raw.workshop_storage.unpaid_claims_ledger:
		if not _record(fee, {"fee_id": TYPE_STRING, "worker_identifier": TYPE_STRING, "service_fee_shekel": TYPE_INT, "final_fee_shekel": TYPE_INT, "created_day": TYPE_INT, "due_day": TYPE_INT, "completed_total_minutes": TYPE_INT, "last_penalty_day": TYPE_INT, "is_active": TYPE_BOOL, "is_paid": TYPE_BOOL, "currency_item_id": TYPE_STRING, "fee_source_type": TYPE_STRING, "fee_source_id": TYPE_STRING}):
			return fail("Invalid workshop fee ledger.")
		if fees.has(fee.fee_id) or fee.fee_id.is_empty() or fee.final_fee_shekel < 0 or ItemDatabase.get_item_data(fee.currency_item_id) == null:
			return fail("Invalid workshop fee identity.")
		fees[fee.fee_id] = true
	for pending: Dictionary in raw.workshop_storage.claimable_outputs:
		if not _record(pending, {"items": TYPE_DICTIONARY, "service_fee_shekel": TYPE_INT, "worker_identifier": TYPE_STRING, "completed_total_minutes": TYPE_INT, "expires_total_minutes": TYPE_INT, "fee_ids": TYPE_ARRAY, "source_type": TYPE_STRING, "source_id": TYPE_STRING, "status": TYPE_STRING}) or not _counts(pending.items) or not _strings(pending.fee_ids):
			return fail("Invalid pending workshop output.")
		for id: String in pending.fee_ids:
			if not fees.has(id):
				return fail("Pending output fee missing.")
	var lots: Dictionary = {}
	for lot: Dictionary in raw.workshop_storage.output_lots:
		if not _record(lot, {"lot_id": TYPE_STRING, "items": TYPE_DICTIONARY, "fee_ids": TYPE_ARRAY, "source_type": TYPE_STRING, "source_id": TYPE_STRING, "created_total_minutes": TYPE_INT}) or not _counts(lot.items) or not _strings(lot.fee_ids):
			return fail("Invalid workshop output lot.")
		if lots.has(lot.lot_id):
			return fail("Duplicate workshop output lot.")
		lots[lot.lot_id] = true
		for id: String in lot.fee_ids:
			if not fees.has(id):
				return fail("Output lot fee missing.")
	return true

func _capture_city_drops(map: Node) -> Array:
	if is_home(map):
		return WorkStateRuntime.get_node("CitySave").city_drops.duplicate(true)
	var drops: Array = []
	# Inventory drops are direct children of the player's YSortWorld. Worksite
	# GroundOutput is owned by the worksite adapter; source views by their registered ledger.
	for node: Node in map.get_node("YSortWorld").get_children():
		if node is PickUpItem and not node.is_in_group("source_pickups") and not node.is_queued_for_deletion() and not node.is_collecting:
			drops.append({"item_id": node.item_id, "quantity": node.quantity, "position": node.position})
	return drops

func _restore_city_drops(drops: Array, map: Node) -> void:
	if is_home(map):
		WorkStateRuntime.get_node("CitySave").city_drops = drops.duplicate(true)
		return
	var parent: Node = map.get_node("YSortWorld")
	for node: Node in parent.get_children():
		if node is PickUpItem and not node.is_in_group("source_pickups"):
			node.free()
	for data: Dictionary in drops:
		var pickup: PickUpItem = PICKUP.instantiate()
		pickup.item_id = data.item_id
		pickup.quantity = data.quantity
		pickup.position = data.position
		parent.add_child(pickup)

func _valid_onboarding(worker: WorkerData) -> bool:
	var legacy: bool = worker.payroll_contract_days == 0 and worker.payroll_paid_start_minute == -1
	if worker.payroll_start_day == -1:
		return legacy and worker.payroll_paid_from_day == -1 and worker.payroll_paid_until_day == -1 and worker.payroll_period_rate == 0 and worker.payroll_last_attempt_day == -1
	if worker.payroll_start_day < 0 or worker.payroll_last_attempt_day < -1:
		return false
	if worker.payroll_last_attempt_day != -1 and worker.payroll_last_attempt_day < worker.payroll_start_day:
		return false
	if worker.payroll_paid_from_day == -1:
		return legacy and worker.payroll_paid_until_day == -1 and worker.payroll_period_rate == 0 and not worker.is_reserved()
	if worker.payroll_paid_from_day < worker.payroll_start_day or worker.payroll_period_rate <= 0 or worker.payroll_last_attempt_day < worker.payroll_paid_from_day:
		return false
	if legacy:
		return worker.payroll_paid_until_day == worker.payroll_paid_from_day + 6
	return worker.payroll_contract_days in WorkerDatabase.CONTRACT_DAYS \
		and worker.payroll_paid_until_day >= worker.payroll_paid_from_day + worker.payroll_contract_days \
		and worker.payroll_paid_until_day <= WorkerDatabase.MAX_CONTRACT_DAY \
		and worker.payroll_paid_start_minute >= worker.payroll_paid_from_day * 1440 \
		and worker.payroll_paid_start_minute < (worker.payroll_paid_from_day + 1) * 1440
