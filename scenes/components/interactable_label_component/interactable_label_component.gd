class_name InteractableLabelComponent extends Control

const INTERACT_TEXT: String = "E"
const VISIBLE_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
const PLAYER_GAP: float = 4.0
const ART_GAP: float = 4.0

@export var position_offset: Vector2 = Vector2(-8, -30)
@onready var label: Label = $NinePatchRect/Label
var _art_target: WeakRef

# Lifecycle

func _ready() -> void:
	size = Vector2(16, 16)
	position = position_offset
	label.text = INTERACT_TEXT

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _art_target == null:
		return
	var target: CanvasItem = _art_target.get_ref() as CanvasItem
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	place_above_art(target)
	var bounds: Rect2 = get_viewport().get_visible_rect().grow(-4.0)
	var screen_box: Rect2 = get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	var shift := Vector2(
		clampf(screen_box.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - screen_box.size.x)) - screen_box.position.x,
		clampf(screen_box.position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - screen_box.size.y)) - screen_box.position.y
	)
	if not shift.is_zero_approx():
		var parent_item: CanvasItem = get_parent() as CanvasItem
		if parent_item != null:
			position += parent_item.get_global_transform_with_canvas().affine_inverse().basis_xform(shift)


# Public API

func set_text(_new_text: String) -> void:
	label.text = INTERACT_TEXT

## Anchor E to the visual top edge, even when the art has transparent margins
## or its owner is scaled. Worksites and the City Storage board share this gap.
func place_above_art(art_node: CanvasItem) -> void:
	if art_node == null:
		return
	_art_target = weakref(art_node)
	var art: Rect2 = VISIBLE_BOUNDS.measure(art_node)
	if not art.has_area():
		return
	var current: Rect2 = get_global_transform() * Rect2(Vector2.ZERO, size)
	var shift := Vector2(art.get_center().x - current.get_center().x,
		art.position.y - ART_GAP - current.end.y)
	var parent_item: CanvasItem = get_parent() as CanvasItem
	if parent_item == null:
		return
	position += parent_item.get_global_transform().affine_inverse().basis_xform(shift)
	position_offset = position

## Crowded resource/storage art can be several tiles from the accessible feet.
## Keep those contextual prompts beside the player while their owner is focused.
func place_above_player(player: Player) -> void:
	_place_by_player(player, false)

func place_below_player(player: Player) -> void:
	_place_by_player(player, true)

func _place_by_player(player: Player, below: bool) -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	var visual: Node = player.get_node_or_null("PlayerVisual")
	if visual == null:
		return
	var art: Rect2 = VISIBLE_BOUNDS.measure(visual)
	if not art.has_area():
		return
	var current: Rect2 = get_global_transform() * Rect2(Vector2.ZERO, size)
	var shift := Vector2(art.get_center().x - current.get_center().x,
		(art.end.y + PLAYER_GAP - current.position.y) if below else (art.position.y - PLAYER_GAP - current.end.y))
	var parent_item: CanvasItem = get_parent() as CanvasItem
	if parent_item == null:
		return
	position += parent_item.get_global_transform().affine_inverse().basis_xform(shift)
	position_offset = position
