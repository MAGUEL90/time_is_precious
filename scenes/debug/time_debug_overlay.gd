extends CanvasLayer

## Development-only controls, separate from the gameplay HUD and menus.
const SPEEDS: Array[int] = [1, 10, 60]
const THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
const PANEL_ATLAS: Texture2D = preload("res://assets/ui/ui_base/base_24.06.2026.png")
const CONSTRUCTION_STATE: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const PRODUCTION_JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const PRODUCTION_RECIPE_COUNT: int = 2
const DRYING_YARD_ID: String = "drying_yard"
const DRYING_YARD_UPGRADE_LEVELS: Array[int] = [1, 2]
const DRYING_YARD_OUTPUT_ITEM_ID: String = "sun_dried_mudbrick"
const PERSONAL_SHEKEL_TARGET: int = 100
const WORKER_GUARD_SATISFACTION: float = 0.5
const WORKER_GUARD_RELIABILITY: float = 0.9
const DEBUG_INVENTORY_CAPACITY: float = 500.0
const INVENTORY_BASE_META: StringName = &"debug_inventory_base_capacity"

var speed_multiplier: int = 1
var panel: PanelContainer
var status_label: Label
var speed_buttons: Array[Button] = []
var step_buttons: Array[Button] = []
var materials_button: Button
var shekel_button: Button
var production_button: Button
var raid_journey_button: Button
var raid_journey_label: Label
var raid_reset_button: Button
var wall_materials_button: Button
var worker_guard_check_button: CheckButton
var player_guard_check_button: CheckButton
var inventory_capacity_button: CheckButton
var materials_status: Label
var worker_guard_enabled: bool = false
var _extra_minutes: float = 0.0
var _last_status: String = ""

func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_create_controls()
	_refresh_controls()
	_refresh_player_guard_button()

func _exit_tree() -> void:
	if TimeComponentManager.time_changed.is_connected(_on_time_changed):
		TimeComponentManager.time_changed.disconnect(_on_time_changed)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_QUOTELEFT:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var effective_speed: int = get_effective_speed()
	if can_advance() and effective_speed > 1:
		# The normal clock still advances its own minutes. Add the remaining rate
		# through the same minute/day signals without accelerating movement/physics.
		_extra_minutes += delta * (effective_speed - 1) / maxf(TimeComponentManager.seconds_per_minute, 0.001)
		while _extra_minutes >= 1.0 and can_advance() and not _raid_is_active():
			_extra_minutes -= 1.0
			TimeComponentManager.advance_one_minute()
			TimeComponentManager.day_cycle()
		if _raid_is_active():
			_extra_minutes = 0.0
	else:
		_extra_minutes = 0.0
	_refresh_controls()

func can_advance() -> bool:
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	return is_instance_valid(player) and player.can_move and not player.is_sleeping and not player.is_collapsing

func _raid_is_active() -> bool:
	var state: Node = _get_raid_state()
	if not is_instance_valid(state):
		return false
	if state.has_method("is_raid_active"):
		return bool(state.call("is_raid_active"))
	return str(state.get("phase")) in ["attacking", "looting"]

func get_effective_speed() -> int:
	# Preserve the chosen debug speed for automatic restoration after combat.
	return 1 if _raid_is_active() else speed_multiplier

func set_speed(multiplier: int) -> void:
	if not SPEEDS.has(multiplier) or _raid_is_active():
		return
	speed_multiplier = multiplier
	_extra_minutes = 0.0
	_refresh_controls()

func step_minutes(minutes: int) -> void:
	if minutes <= 0 or not can_advance() or _raid_is_active():
		return
	# Check after each minute so a modal/collapse/transition can stop a jump.
	for _minute in range(minutes):
		if not can_advance() or _raid_is_active():
			break
		TimeComponentManager.advance_minutes(1)
	_extra_minutes = 0.0
	_refresh_controls()

func give_build_materials() -> bool:
	return _top_up_inventory(
		CONSTRUCTION_STATE.REQUIREMENTS,
		"Ready: Wood 6 / Clay 12 / Reed 8",
		"Bag full. Free space for build materials."
	)

func give_shekel() -> bool:
	return _top_up_inventory(
		{"shekel": PERSONAL_SHEKEL_TARGET},
		"Ready: 100 Shekel in Inventory.",
		"Bag full. Free space for Shekel."
	)

func set_large_inventory(enabled: bool) -> bool:
	if not OS.is_debug_build() or not can_supply_materials():
		_refresh_inventory_capacity_button()
		return false
	if enabled:
		if not Inventory.has_meta(INVENTORY_BASE_META):
			Inventory.set_meta(INVENTORY_BASE_META, Inventory.max_load)
		Inventory.max_load = maxf(DEBUG_INVENTORY_CAPACITY, float(Inventory.get_meta(INVENTORY_BASE_META)))
	else:
		if Inventory.has_meta(INVENTORY_BASE_META):
			var original_capacity: float = float(Inventory.get_meta(INVENTORY_BASE_META))
			if Inventory.get_total_inventory_weight() > original_capacity:
				materials_status.text = "Unload to %.0f before restoring capacity." % original_capacity
				_refresh_inventory_capacity_button()
				return false
			Inventory.max_load = original_capacity
			Inventory.remove_meta(INVENTORY_BASE_META)
	# Keep capacity and its original value on Inventory for scene-to-scene continuity.
	# Only this explicit debug action changes it; restarting the game resets it.
	Inventory.items_changed.emit()
	materials_status.text = "Inventory capacity: %.0f" % Inventory.max_load
	_refresh_inventory_capacity_button()
	return true

func _refresh_inventory_capacity_button() -> void:
	if inventory_capacity_button != null:
		inventory_capacity_button.set_pressed_no_signal(Inventory.has_meta(INVENTORY_BASE_META))

func give_production_materials() -> bool:
	return _top_up_inventory(
		_get_production_material_targets(),
		"Production kit ready: 2 recipes + yard upgrades.",
		"Bag full. Free space for production materials."
	)

func set_worker_guard(enabled: bool) -> void:
	if not OS.is_debug_build():
		return
	worker_guard_enabled = enabled
	var time_signal: Signal = TimeComponentManager.time_changed
	if enabled:
		if not time_signal.is_connected(_on_time_changed):
			time_signal.connect(_on_time_changed)
		_restore_hired_worker_performance()
	else:
		if time_signal.is_connected(_on_time_changed):
			time_signal.disconnect(_on_time_changed)
	if worker_guard_check_button != null:
		worker_guard_check_button.set_pressed_no_signal(enabled)

func set_player_guard(enabled: bool) -> void:
	if not OS.is_debug_build():
		return
	var player: Player = _get_player()
	if not is_instance_valid(player):
		return
	player.debug_disable_player_needs = enabled
	player.debug_disable_fatigue = enabled
	if enabled and player.has_method("_reset_debug_needs"):
		player.call("_reset_debug_needs")
	_refresh_player_guard_button()

func give_wall_materials() -> bool:
	if not OS.is_debug_build() or not can_advance():
		return false
	var state: Node = _get_raid_state()
	if not is_instance_valid(state) or not is_instance_valid(state.storage):
		return false
	var quote: Dictionary = state.get_work_quote()
	var available: Dictionary = state.storage.get_available_items()
	var missing: Dictionary = {}
	for id: String in quote.materials:
		var amount: int = maxi(0, int(quote.materials[id]) - int(available.get(id, 0)))
		if amount > 0:
			missing[id] = amount
	if missing.is_empty():
		return false
	var result: bool = state.storage.refund_materials(missing)
	if result:
		materials_status.text = "Wall materials added to City Storage (debug)."
	_refresh_controls()
	return result

func dispatch_raid_journey() -> bool:
	if not OS.is_debug_build() or not can_advance():
		return false
	var state: Node = _get_raid_state()
	if not is_instance_valid(state):
		return false
	var dispatched: bool = state.dispatch_debug_party()
	_refresh_controls()
	return dispatched

func reset_wall_test() -> bool:
	if not OS.is_debug_build():
		_set_raid_error("Wall reset is debug only.")
		return false
	if not can_advance():
		_set_raid_error("Resume gameplay and wake the player first.")
		return false
	var raid_state: Node = _get_raid_state()
	if not is_instance_valid(raid_state) or not raid_state.has_method("get_status"):
		_set_raid_error("Raid controls are not ready.")
		return false
	var status_value: Variant = raid_state.call("get_status")
	if not status_value is Dictionary:
		_set_raid_error("Raid controls are not ready.")
		return false
	var raid_status: Dictionary = status_value
	if str(raid_status.get("phase", "")) in ["attacking", "looting"]:
		_set_raid_error("A raid is already underway.")
		return false
	if int(raid_status.get("level", 0)) <= 0 or int(raid_status.get("hp", 0)) <= 0:
		_set_raid_error("Rebuild the wall before resetting HP.")
		return false
	if int(raid_status.get("hp", 0)) >= int(raid_status.get("max_hp", 0)):
		_set_raid_error("Wall HP is already full.")
		return false
	if not raid_state.has_method("reset_debug_wall"):
		_set_raid_error("Wall reset is not available.")
		return false
	if not bool(raid_state.call("reset_debug_wall")):
		_set_raid_error("Could not reset wall HP.")
		_refresh_controls()
		return false
	materials_status.text = "Wall HP restored for testing."
	_refresh_controls()
	return true

func _get_raid_state() -> Node:
	if not is_instance_valid(WorkStateRuntime):
		return null
	return WorkStateRuntime.get_node_or_null("CityRaid")

func _set_raid_error(message: String) -> void:
	if is_instance_valid(materials_status):
		materials_status.text = message

func _top_up_inventory(target_items: Dictionary, success_message: String, capacity_message: String) -> bool:
	if not OS.is_debug_build() or not can_supply_materials():
		return false
	# Calculate and validate the complete deficit first so a failed grant never
	# mutates only part of the requested kit or pushes Inventory over capacity.
	var missing: Dictionary = {}
	for item_id_value in target_items.keys():
		var item_id: String = str(item_id_value)
		if Inventory.get_item_data(item_id) == null:
			materials_status.text = "Item unavailable: " + item_id
			return false
		var target_quantity: int = maxi(int(target_items[item_id_value]), 0)
		var quantity: int = maxi(target_quantity - int(Inventory.items.get(item_id, 0)), 0)
		if quantity > 0:
			missing[item_id] = quantity
	if Inventory.get_bulk_item_total_weight(missing) > Inventory.get_remaining_capacity():
		materials_status.text = capacity_message
		return false
	Inventory.add_bulk_item(missing)
	materials_status.text = success_message
	return true

func _get_production_material_targets() -> Dictionary:
	var targets: Dictionary = {}
	for item_id_value in PRODUCTION_JOB.inputs.keys():
		var item_id: String = str(item_id_value)
		targets[item_id] = int(targets.get(item_id, 0)) + int(PRODUCTION_JOB.inputs[item_id_value]) * PRODUCTION_RECIPE_COUNT
	for level: int in DRYING_YARD_UPGRADE_LEVELS:
		var requirements: Dictionary = WorkshopFacilityManager.get_facility_upgrade_requirements(
			DRYING_YARD_ID,
			level
		)
		for item_id_value in requirements.keys():
			var item_id: String = str(item_id_value)
			if item_id == DRYING_YARD_OUTPUT_ITEM_ID:
				continue
			targets[item_id] = int(targets.get(item_id, 0)) + int(requirements[item_id_value])
	return targets

func _restore_hired_worker_performance() -> void:
	for worker_value in WorkerDatabase.get_all_workers():
		if not worker_value is WorkerData:
			continue
		var worker: WorkerData = worker_value as WorkerData
		worker.satisfaction = WORKER_GUARD_SATISFACTION
		worker.reliability = WORKER_GUARD_RELIABILITY
		var citizen: CitizenData = worker.get_linked_citizen()
		if citizen != null:
			citizen.satisfaction = WORKER_GUARD_SATISFACTION
			citizen.reliability = WORKER_GUARD_RELIABILITY

func _on_time_changed(_day: int, _hour: int, _minute: int, _weather: String) -> void:
	if worker_guard_enabled:
		_restore_hired_worker_performance()

func _get_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _refresh_player_guard_button() -> void:
	if player_guard_check_button == null:
		return
	var player: Player = _get_player()
	if not is_instance_valid(player):
		player_guard_check_button.set_pressed_no_signal(false)
		player_guard_check_button.disabled = true
		return
	player_guard_check_button.disabled = false
	player_guard_check_button.set_pressed_no_signal(
		player.debug_disable_player_needs and player.debug_disable_fatigue
	)

func can_supply_materials() -> bool:
	# Unlike time controls, explicit supplies can fill a paused build menu's
	# missing materials. Its Inventory signal refreshes requirements immediately.
	var player: Player = _get_player()
	return is_instance_valid(player) and not SceneTransition.is_transitioning and not player.is_sleeping and not player.is_collapsing

func _create_controls() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Local theme copy also covers tooltip text without changing the shared theme.
	var debug_theme: Theme = THEME.duplicate()
	debug_theme.default_font = THEME.get_font("font", "HudShortcutButton")
	debug_theme.default_font_size = 6
	root.theme = debug_theme
	add_child(root)
	var toggle := _button("Debug `")
	toggle.size = Vector2(52, 16)
	toggle.pressed.connect(func(): panel.visible = not panel.visible)
	root.add_child(toggle)
	toggle.name = "DebugToggle"
	toggle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	toggle.offset_left = 6
	toggle.offset_top = -22
	toggle.offset_right = 58
	toggle.offset_bottom = -6
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	panel.visible = false
	var panel_texture := AtlasTexture.new()
	panel_texture.atlas = PANEL_ATLAS
	panel_texture.region = Rect2(1, 1, 168, 134)
	var background := StyleBoxTexture.new()
	background.texture = panel_texture
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		background.set_texture_margin(side, 16)
		background.set_content_margin(side, 16)
	panel.add_theme_stylebox_override("panel", background)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 6
	panel.offset_right = 256
	panel.offset_top = -208
	panel.offset_bottom = -26
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(218, 150)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title := _label("DEBUG")
	column.add_child(title)
	status_label = _label("")
	column.add_child(status_label)
	var speeds := HBoxContainer.new()
	column.add_child(speeds)
	for value in SPEEDS:
		var button := _button("x%d" % value)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(set_speed.bind(value))
		speeds.add_child(button)
		speed_buttons.append(button)
	var steps := HBoxContainer.new()
	column.add_child(steps)
	for entry in [["+30m", 30], ["+3h", 180], ["+1d", 1440]]:
		var button := _button(entry[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(step_minutes.bind(entry[1]))
		steps.add_child(button)
		step_buttons.append(button)
	var supply_buttons := HBoxContainer.new()
	supply_buttons.add_theme_constant_override("separation", 3)
	column.add_child(supply_buttons)
	materials_button = _button("Build kit")
	materials_button.tooltip_text = "Top up Inventory for one workshop: 6 Wood Logs, 12 Clay Lumps, 8 Reed Bundles."
	materials_button.pressed.connect(give_build_materials)
	materials_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supply_buttons.add_child(materials_button)
	production_button = _button("Production")
	production_button.tooltip_text = "Top up two mudbrick recipes and non-output materials for Drying Yard levels 1 and 2."
	production_button.pressed.connect(give_production_materials)
	production_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supply_buttons.add_child(production_button)
	shekel_button = _button("100 Shekel")
	shekel_button.tooltip_text = "Top up personal Inventory to 100 Shekel."
	shekel_button.pressed.connect(give_shekel)
	shekel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(shekel_button)
	inventory_capacity_button = _check_button("Inventory 500")
	inventory_capacity_button.tooltip_text = "Increase personal capacity for testing. Unload to the original limit before switching off."
	inventory_capacity_button.toggled.connect(set_large_inventory)
	column.add_child(inventory_capacity_button)
	var guard_buttons := HBoxContainer.new()
	guard_buttons.add_theme_constant_override("separation", 3)
	column.add_child(guard_buttons)
	worker_guard_check_button = _check_button("Worker guard")
	worker_guard_check_button.tooltip_text = "Hold hired workers and linked citizens at 0.5 satisfaction / 0.9 reliability while enabled."
	worker_guard_check_button.toggled.connect(set_worker_guard)
	worker_guard_check_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guard_buttons.add_child(worker_guard_check_button)
	player_guard_check_button = _check_button("Player guard")
	player_guard_check_button.tooltip_text = "Toggle the player's authored needs and fatigue debug protection."
	player_guard_check_button.toggled.connect(set_player_guard)
	player_guard_check_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guard_buttons.add_child(player_guard_check_button)
	materials_status = _label("")
	materials_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(materials_status)
	var raid_buttons := HBoxContainer.new()
	raid_buttons.add_theme_constant_override("separation", 3)
	column.add_child(raid_buttons)
	column.move_child(raid_buttons, 4)
	raid_journey_button = _button("Send raiders")
	raid_journey_button.tooltip_text = "Start a normal party's journey. Travel and warning occur before combat. An existing journey cannot be restarted."
	raid_journey_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raid_journey_button.pressed.connect(dispatch_raid_journey)
	raid_buttons.add_child(raid_journey_button)
	raid_journey_label = _label("")
	raid_journey_label.name = "RaidJourney"
	raid_journey_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(raid_journey_label)
	column.move_child(raid_journey_label, 5)
	raid_reset_button = _button("Reset wall HP")
	raid_reset_button.name = "RaidWallReset"
	raid_reset_button.tooltip_text = "Debug only: restores a damaged built wall to full HP. Does not upgrade the wall or change the raid schedule. Unavailable during an active raid."
	raid_reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raid_reset_button.pressed.connect(reset_wall_test)
	raid_buttons.add_child(raid_reset_button)
	wall_materials_button = _button("Wall materials")
	wall_materials_button.tooltip_text = "Debug only: adds missing materials for the next wall job to City Storage."
	wall_materials_button.pressed.connect(give_wall_materials)
	column.add_child(wall_materials_button)
	column.move_child(wall_materials_button, 5)
	column.add_child(_label("Close: Debug button / `"))

func _button(caption: String) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"HudShortcutButton"
	button.text = caption
	button.custom_minimum_size = Vector2(0, 16)
	button.add_theme_font_size_override("font_size", 6)
	button.focus_mode = Control.FOCUS_NONE
	return button

func _label(caption: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HudLabelShortcut"
	label.text = caption
	label.add_theme_font_size_override("font_size", 6)
	return label

func _check_button(caption: String) -> CheckButton:
	var button := CheckButton.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 16)
	button.add_theme_font_size_override("font_size", 6)
	button.add_theme_font_override("font", THEME.get_font("font", "HudShortcutButton"))
	button.focus_mode = Control.FOCUS_NONE
	return button

func _refresh_raid_buttons(player_available: bool) -> void:
	if raid_journey_button == null or raid_reset_button == null:
		return
	var state: Node = _get_raid_state()
	var can_use: bool = OS.is_debug_build() and player_available
	wall_materials_button.disabled = not can_use
	raid_journey_button.disabled = true
	raid_reset_button.disabled = true
	raid_journey_label.text = "Build the wall to start the first journey."
	if not is_instance_valid(state):
		return
	raid_journey_button.disabled = not (can_use and state.can_dispatch_debug_party())
	var status: Dictionary = state.get_status()
	var phase: String = str(status.get("phase", ""))
	var raid_active: bool = phase in ["attacking", "looting"]
	raid_reset_button.disabled = not (can_use and status.hp > 0 and status.hp < status.max_hp and not raid_active and str(status.get("work_kind", "")).is_empty())
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	if phase == "attacking":
		raid_journey_label.text = "Raid in progress (clock x1)."
	elif phase == "looting":
		var seconds_left: float = maxf(0.0, float(status.get("loot_seconds_remaining", status.get("seconds_left", 0.0))))
		raid_journey_label.text = "Raiders looting (%ds, clock x1)." % int(ceil(seconds_left))
	elif state._attack_at >= 0 and state.config.party_profile != null:
		var remaining: int = maxi(0, state._attack_at - now)
		raid_journey_label.text = "Raid arrives in %dd %dh %dm (debug)." % [remaining / 1440, (remaining % 1440) / 60, remaining % 60]
		if state._departure_at > now:
			raid_journey_label.text = "Recovery. " + raid_journey_label.text

func _refresh_controls() -> void:
	if status_label == null:
		return
	var available: bool = can_advance()
	var raid_active: bool = _raid_is_active()
	var raid_state: Node = _get_raid_state()
	var looting: bool = is_instance_valid(raid_state) and str(raid_state.get("phase")) == "looting"
	var effective_speed: int = get_effective_speed()
	var status := "Day %d  %02d:%02d  x%d%s" % [TimeComponentManager.current_day, TimeComponentManager.current_hour,
		TimeComponentManager.current_minute, effective_speed, "  PAUSED" if not available else ("  LOOT" if looting else ("  RAID" if raid_active else ""))]
	if status != _last_status:
		status_label.text = status
		_last_status = status
	for index in range(speed_buttons.size()):
		speed_buttons[index].set_pressed_no_signal(SPEEDS[index] == effective_speed)
		speed_buttons[index].disabled = raid_active
	for button in step_buttons:
		button.disabled = not available or raid_active
	materials_button.disabled = not can_supply_materials()
	production_button.disabled = not can_supply_materials()
	shekel_button.disabled = not can_supply_materials()
	if worker_guard_check_button != null:
		worker_guard_check_button.set_pressed_no_signal(worker_guard_enabled)
	_refresh_player_guard_button()
	_refresh_inventory_capacity_button()
	_refresh_raid_buttons(available)
