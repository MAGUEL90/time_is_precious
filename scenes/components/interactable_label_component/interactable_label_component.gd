class_name InteractableLabelComponent extends Control

const INTERACT_TEXT: String = "E"
const VISIBLE_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
const PLAYER_GAP: float = 4.0
const ART_GAP: float = 2.0

@export var position_offset: Vector2 = Vector2(-8, -30)
@onready var label: Label = $NinePatchRect/Label

# Lifecycle

func _ready() -> void:
	size = Vector2(16, 16)
	position = position_offset
	label.text = INTERACT_TEXT


# Public API

func set_text(_new_text: String) -> void:
	label.text = INTERACT_TEXT

## Anchor E to the visual top edge, even when the art has transparent margins
## or its owner is scaled. Worksites and the City Storage board share this gap.
func place_above_art(art_node: CanvasItem) -> void:
	if art_node == null:
		return
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
