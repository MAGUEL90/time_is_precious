extends CanvasLayer

const SHOW_STATUS_ACTION: StringName = &"show_player_status"

const DRAWER_OPEN_Y: float = -60.0
const DRAWER_CLOSED_Y: float = 24.0
const OPEN_DURATION: float = 0.14
const CLOSE_DURATION: float = 0.10

const CONDITION_CRITICAL_COLOR: Color = Color(1.0, 0.55, 0.48, 1.0)
const CONDITION_CRITICAL_DIM_COLOR: Color = Color(0.65, 0.28, 0.25, 1.0)
# The empty track is dark; a red tint keeps zero visible without filling the bar.
const CONDITION_CRITICAL_TRACK_TINT: Color = Color(1.8, 0.6, 0.6, 1.0)
const CONDITION_WARNING_REMAINING_PERCENT: int = 20
const CONDITION_BLINK_HALF_PERIOD: float = 1.2
const GAMEPLAY_THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")

@onready var status_drawer: Control = $Root/StatusDrawer
@onready var fatigue_indicator: HBoxContainer = $Root/ConditionRow/FatigueIndicator
@onready var hunger_indicator: HBoxContainer = $Root/ConditionRow/HungerIndicator
@onready var fatigue_bar: TextureProgressBar = $Root/ConditionRow/FatigueIndicator/Bar
@onready var hunger_bar: TextureProgressBar = $Root/ConditionRow/HungerIndicator/Bar
@onready var experience_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/ExperienceIndicator/Bar

var player_ref: Player = null
var nightmare_world_ref: NightmareWorld = null
var drawer_tween: Tween
var condition_tweens: Dictionary = {}
var fatigue_label: Label
var hunger_label: Label
var shekel_label: Label
var shekel_panel: PanelContainer

# Lifecycle

func _ready() -> void:
	_setup_shekel_display()
	_setup_status_text()
	_set_drawer_y(DRAWER_CLOSED_Y)
	status_drawer.hide()
	_setup_nightmare_visibility()
	BaseDialogueManager.dialogue_activated.connect(_on_dialogue_started)

	player_ref = get_tree().get_first_node_in_group("player") as Player

	if player_ref == null:
		push_warning("BottomHUD could not find player.")
		return

	player_ref.condition_changed.connect(_on_condition_changed)
	player_ref.experience_changed.connect(_on_experience_changed)

	_on_condition_changed()
	_on_experience_changed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and is_node_ready():
		_reset_drawer()
		_hide_condition_labels()

# Input handling

func _setup_shekel_display() -> void:
	var panel := PanelContainer.new()
	shekel_panel = panel
	panel.name = "ShekelPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.theme = GAMEPLAY_THEME
	var panel_style: StyleBox = GAMEPLAY_THEME.get_stylebox("normal", "HudShortcutButton").duplicate()
	panel_style.content_margin_left = 3
	panel_style.content_margin_right = 3
	panel_style.content_margin_top = 2
	panel_style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", panel_style)
	$Root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -54
	panel.offset_right = -6
	panel.offset_top = -20
	panel.offset_bottom = -6
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(8, 8)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = preload("res://assets/ui/ui_icon/small_shekel_8x8.png")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	shekel_label = Label.new()
	shekel_label.theme_type_variation = &"HudLabelShortcut"
	shekel_label.add_theme_font_size_override("font_size", 6)
	shekel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shekel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shekel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shekel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(shekel_label)
	Inventory.items_changed.connect(_refresh_shekel_display)
	_refresh_shekel_display()

func _refresh_shekel_display() -> void:
	shekel_label.text = str(Inventory.items.get("shekel", 0))
	var text_width: float = ceilf(shekel_label.get_theme_font("font").get_string_size(shekel_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, shekel_label.get_theme_font_size("font_size")).x)
	# Keep a compact default while allowing long balances to grow toward the left.
	shekel_panel.offset_left = -6.0 - maxf(48.0, text_width + 17.0)

func _input(event: InputEvent) -> void:
	# A modal may consume the release before unhandled input receives it.
	if event.is_action_released(SHOW_STATUS_ACTION) and status_drawer.visible:
		_animate_drawer(DRAWER_CLOSED_Y, CLOSE_DURATION)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(SHOW_STATUS_ACTION):
		_animate_drawer(DRAWER_OPEN_Y, OPEN_DURATION)
		get_viewport().set_input_as_handled()

# Player status presentation

func _on_condition_changed() -> void:
	var fatigue_remaining: int = 100 - player_ref.get_fatigue_percent()
	var hunger_remaining: int = 100 - player_ref.get_hunger_percent()

	_update_condition_bar(fatigue_bar, fatigue_remaining)
	_update_condition_bar(hunger_bar, hunger_remaining)

func _on_experience_changed() -> void:
	experience_bar.max_value = player_ref.experience_required
	experience_bar.value = player_ref.current_experience

func _update_condition_bar(bar: TextureProgressBar, remaining: int) -> void:
	bar.value = remaining
	if remaining > CONDITION_WARNING_REMAINING_PERCENT:
		bar.tint_under = Color.WHITE
		if condition_tweens.has(bar):
			condition_tweens[bar].kill()
			condition_tweens.erase(bar)
		bar.modulate = Color.WHITE
		return
	if condition_tweens.has(bar):
		return
	bar.tint_under = CONDITION_CRITICAL_TRACK_TINT
	bar.modulate = CONDITION_CRITICAL_COLOR
	var tween: Tween = create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(bar, "modulate", CONDITION_CRITICAL_DIM_COLOR, CONDITION_BLINK_HALF_PERIOD)
	tween.tween_property(bar, "modulate", CONDITION_CRITICAL_COLOR, CONDITION_BLINK_HALF_PERIOD)
	condition_tweens[bar] = tween

func _make_status_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.theme = GAMEPLAY_THEME
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _setup_status_text() -> void:
	var names := HBoxContainer.new()
	names.name = "StatusNames"
	names.position = Vector2(0, -10)
	names.add_theme_constant_override("separation", 2)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var experience_label: Label = _make_status_label("EXP")
	experience_label.custom_minimum_size.x = 38
	names.add_child(experience_label)
	status_drawer.add_child(names)

	fatigue_label = _make_condition_hover_label("Energy", Vector2(4, 19))
	hunger_label = _make_condition_hover_label("Belly", Vector2(44, 19))
	var fatigue_icon: Control = fatigue_indicator.get_node("Icon")
	var hunger_icon: Control = hunger_indicator.get_node("Icon")
	fatigue_icon.mouse_entered.connect(fatigue_label.show)
	fatigue_icon.mouse_exited.connect(fatigue_label.hide)
	hunger_icon.mouse_entered.connect(hunger_label.show)
	hunger_icon.mouse_exited.connect(hunger_label.hide)

func _make_condition_hover_label(title: String, at: Vector2) -> Label:
	var label: Label = _make_status_label(title)
	label.position = at
	label.size = Vector2(38, 10)
	label.add_theme_color_override("font_shadow_color", Color(0.12, 0.08, 0.04, 1.0))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.hide()
	$Root.add_child(label)
	return label

func _hide_condition_labels() -> void:
	if fatigue_label != null:
		fatigue_label.hide()
	if hunger_label != null:
		hunger_label.hide()

func _on_dialogue_started() -> void:
	_reset_drawer()
	_hide_condition_labels()

# Drawer animation

func _animate_drawer(target_y: float, duration: float) -> void:
	if drawer_tween != null:
		drawer_tween.kill()
	status_drawer.show()

	drawer_tween = create_tween()
	drawer_tween.set_trans(Tween.TRANS_QUAD)
	drawer_tween.set_ease(Tween.EASE_OUT)
	drawer_tween.tween_method(
		_set_drawer_y,
		status_drawer.offset_top,
		target_y,
		duration
	)
	if target_y == DRAWER_CLOSED_Y:
		drawer_tween.tween_callback(status_drawer.hide)

func _set_drawer_y(value: float) -> void:
	status_drawer.offset_top = roundf(value)
	status_drawer.offset_bottom = roundf(value) + 16.0

func _reset_drawer() -> void:
	if drawer_tween != null:
		drawer_tween.kill()
	_set_drawer_y(DRAWER_CLOSED_Y)
	status_drawer.hide()

# Nightmare visibility

func _setup_nightmare_visibility() -> void:
	nightmare_world_ref = (
		get_tree().get_first_node_in_group("nightmare_world")
		as NightmareWorld
	)

	if nightmare_world_ref == null:
		show()
		set_process_unhandled_input(true)
		return

	nightmare_world_ref.nightmare_active_changed.connect(
		_on_nightmare_active_changed
	)
	_on_nightmare_active_changed(nightmare_world_ref.is_active)

func _on_nightmare_active_changed(active: bool) -> void:
	visible = not active
	set_process_unhandled_input(not active)

	if active:
		_reset_drawer()
		_hide_condition_labels()
