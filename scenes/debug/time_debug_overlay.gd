extends CanvasLayer

## Development-only controls, separate from the gameplay HUD and menus.
const SPEEDS: Array[int] = [1, 10, 60]
const THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
const CONSTRUCTION_STATE: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")

var speed_multiplier: int = 1
var panel: PanelContainer
var status_label: Label
var speed_buttons: Array[Button] = []
var step_buttons: Array[Button] = []
var materials_button: Button
var materials_status: Label
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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_QUOTELEFT:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if can_advance() and speed_multiplier > 1:
		# The normal clock still advances its own minutes. Add the remaining rate
		# through the same minute/day signals without accelerating movement/physics.
		_extra_minutes += delta * (speed_multiplier - 1) / maxf(TimeComponentManager.seconds_per_minute, 0.001)
		while _extra_minutes >= 1.0 and can_advance():
			_extra_minutes -= 1.0
			TimeComponentManager.advance_one_minute()
			TimeComponentManager.day_cycle()
	else:
		_extra_minutes = 0.0
	_refresh_controls()

func can_advance() -> bool:
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	return is_instance_valid(player) and player.can_move and not player.is_sleeping and not player.is_collapsing

func set_speed(multiplier: int) -> void:
	if not SPEEDS.has(multiplier):
		return
	speed_multiplier = multiplier
	_extra_minutes = 0.0
	_refresh_controls()

func step_minutes(minutes: int) -> void:
	if minutes <= 0 or not can_advance():
		return
	# Check after each minute so a modal/collapse/transition can stop a jump.
	for _minute in range(minutes):
		if not can_advance():
			break
		TimeComponentManager.advance_minutes(1)
	_extra_minutes = 0.0
	_refresh_controls()

func give_build_materials() -> bool:
	if not OS.is_debug_build() or not can_supply_materials():
		return false
	# Top up one build, preserving surplus and checking the whole kit before
	# mutation so a full bag cannot receive a partial set or exceed capacity.
	var missing: Dictionary = {}
	for item_id: String in CONSTRUCTION_STATE.REQUIREMENTS:
		if Inventory.get_item_data(item_id) == null:
			materials_status.text = "Item unavailable: " + item_id
			return false
		var quantity: int = maxi(int(CONSTRUCTION_STATE.REQUIREMENTS[item_id]) - int(Inventory.items.get(item_id, 0)), 0)
		if quantity > 0:
			missing[item_id] = quantity
	if Inventory.get_bulk_item_total_weight(missing) > Inventory.get_remaining_capacity():
		materials_status.text = "Bag full. Free space for build materials."
		return false
	Inventory.add_bulk_item(missing)
	materials_status.text = "Ready: Wood 6 / Clay 12 / Reed 8"
	return true

func can_supply_materials() -> bool:
	# Unlike time controls, explicit supplies can fill a paused build menu's
	# missing materials. Its Inventory signal refreshes requirements immediately.
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	return is_instance_valid(player) and not SceneTransition.is_transitioning and not player.is_sleeping and not player.is_collapsing

func _create_controls() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = THEME
	add_child(root)
	var toggle := _button("Debug `")
	toggle.position = Vector2(6, 6)
	toggle.size = Vector2(52, 16)
	toggle.pressed.connect(func(): panel.visible = not panel.visible)
	root.add_child(toggle)
	panel = PanelContainer.new()
	panel.position = Vector2(6, 26)
	panel.custom_minimum_size = Vector2(180, 0)
	panel.visible = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.16, 0.12, 0.08, 0.96)
	background.border_color = Color(0.77, 0.61, 0.35)
	background.set_border_width_all(1)
	background.content_margin_left = 8
	background.content_margin_right = 8
	background.content_margin_top = 6
	background.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", background)
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
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
	materials_button = _button("Build materials")
	materials_button.tooltip_text = "Top up Inventory for one workshop: 6 Wood Logs, 12 Clay Lumps, 8 Reed Bundles."
	materials_button.pressed.connect(give_build_materials)
	column.add_child(materials_button)
	materials_status = _label("")
	materials_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(materials_status)
	column.add_child(_label("Close: Debug button / `"))

func _button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 16)
	button.add_theme_font_size_override("font_size", 8)
	button.focus_mode = Control.FOCUS_NONE
	return button

func _label(caption: String) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 8)
	return label

func _refresh_controls() -> void:
	if status_label == null:
		return
	var available: bool = can_advance()
	var status := "Day %d  %02d:%02d  x%d%s" % [TimeComponentManager.current_day, TimeComponentManager.current_hour,
		TimeComponentManager.current_minute, speed_multiplier, "  PAUSED" if not available else ""]
	if status != _last_status:
		status_label.text = status
		_last_status = status
	for index in range(speed_buttons.size()):
		speed_buttons[index].set_pressed_no_signal(SPEEDS[index] == speed_multiplier)
	for button in step_buttons:
		button.disabled = not available
	materials_button.disabled = not can_supply_materials()
