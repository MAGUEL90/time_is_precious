class_name InteractableLabelComponent extends Control

const INTERACT_TEXT: String = "E"
const VISIBLE_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
const PLAYER_GAP: float = 4.0

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

## Crowded resource/storage art can be several tiles from the accessible feet.
## Keep those contextual prompts beside the player while their owner is focused.
func place_above_player(player: Player) -> void:
	_place_by_player(player, false)

func place_below_player(player: Player) -> void:
	_place_by_player(player, true)

## Choose a nearby open spot when a worksite is surrounded by captions and art.
## Candidate bounds and obstacles are in world space, before camera scaling.
func place_near_player(player: Player, obstacles: Array[Rect2]) -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	var visual: Node = player.get_node_or_null("PlayerVisual")
	if visual == null:
		return
	var art: Rect2 = VISIBLE_BOUNDS.measure(visual)
	if not art.has_area():
		return
	var current: Rect2 = get_global_transform() * Rect2(Vector2.ZERO, size)
	var width: float = current.size.x
	var height: float = current.size.y
	var above: float = art.position.y - PLAYER_GAP - height
	var side_y: float = art.position.y + (art.size.y - height) * 0.5
	var left: float = art.position.x - PLAYER_GAP - width
	var right: float = art.end.x + PLAYER_GAP
	var centered: float = art.get_center().x - width * 0.5
	var candidates: Array[Vector2] = [
		Vector2(centered, above), Vector2(left, above), Vector2(right, above),
		Vector2(left, side_y), Vector2(right, side_y),
		Vector2(centered, above - height * 0.5),
		Vector2(left, art.position.y), Vector2(right, art.position.y),
		Vector2(left, art.end.y - height), Vector2(right, art.end.y - height),
		Vector2(left, above - height - PLAYER_GAP),
		Vector2(right, above - height - PLAYER_GAP),
		Vector2(centered, above - height - PLAYER_GAP),
		Vector2(left, art.end.y + PLAYER_GAP),
		Vector2(right, art.end.y + PLAYER_GAP)
	]
	# A few pixel shifts matter in the packed city: the authored storage label,
	# roof and resource art leave narrow gaps around the same player pose.
	for dx: int in [-8, -4, 0, 4, 8]:
		for dy: int in [-16, -12, -8, -4, 0]:
			candidates.append(Vector2(centered + dx, above + dy))
	for side_x: float in [left - 8.0, left - 4.0, left, right, right + 4.0, right + 8.0]:
		for dy: int in [-12, -8, -4, 0, 4, 8, 12]:
			candidates.append(Vector2(side_x, side_y + dy))
	var selected: Vector2 = candidates[0]
	var lowest_score: float = INF
	for index: int in range(candidates.size()):
		var box := Rect2(candidates[index], current.size)
		var score: float = box.get_center().distance_to(art.get_center()) + float(index) * 0.2
		if box.position.y >= art.end.y:
			score += 20.0
		for obstacle: Rect2 in obstacles:
			var overlap: Rect2 = box.intersection(obstacle.grow(0.5))
			if overlap.has_area():
				score += overlap.get_area() * 100.0
		if score < lowest_score:
			lowest_score = score
			selected = candidates[index]
	var parent_item: CanvasItem = get_parent() as CanvasItem
	if parent_item == null:
		return
	position += parent_item.get_global_transform().affine_inverse().basis_xform(selected - current.position)
	position_offset = position

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
