extends BaseGameDialogueBalloon
## Workshop-only anchor; keep native wall dialogue art, typewriter and responses.
const VISUAL_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
var anchor_player: Node2D
const PLAYER_GAP: float = 8.0
func position_chat_box() -> void:
	if not is_instance_valid(anchor_player):
		super.position_chat_box()
		return
	var visual: Node = anchor_player.get_node_or_null("PlayerVisual")
	var bounds: Rect2 = VISUAL_BOUNDS.measure(visual if visual!=null else anchor_player)
	if not bounds.has_area():
		super.position_chat_box()
		return
	var player_screen: Rect2 = get_viewport().get_canvas_transform()*bounds
	var parent_transform: Transform2D = chat_box_root.get_parent().get_global_transform_with_canvas()
	var screen_size: Vector2 = (parent_transform*Rect2(Vector2.ZERO,chat_box_root.size)).size
	var desired := Vector2(player_screen.get_center().x-screen_size.x*0.5,player_screen.end.y+PLAYER_GAP)
	var viewport_size: Vector2 = get_dialogue_viewport_size()
	# At the lower edge, place above instead of covering the player when space permits.
	var above: float = player_screen.position.y-PLAYER_GAP-screen_size.y
	if desired.y+screen_size.y>viewport_size.y-screen_margin and above>=screen_margin:
		desired.y = above
	var maximum := Vector2(maxf(screen_margin,viewport_size.x-screen_size.x-screen_margin),maxf(screen_margin,viewport_size.y-screen_size.y-screen_margin))
	desired = desired.clamp(Vector2.ONE*screen_margin,maximum)
	chat_box_root.position = (parent_transform.affine_inverse()*desired).round()