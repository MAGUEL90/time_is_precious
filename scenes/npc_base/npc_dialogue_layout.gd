extends Node

## Places NPC dialogue and its choices centered above the bottom toolbar.
var balloon: BaseGameDialogueBalloon

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1

func _process(_delta: float) -> void:
	if not is_instance_valid(balloon):
		return
	var scene: Node = get_tree().current_scene
	if not is_instance_valid(scene):
		return
	var hud: Node = scene.find_child("BottomHUD", true, false)
	var bar: Control = hud.get_node_or_null("Root/BottomBar") as Control if is_instance_valid(hud) else null
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var bottom_limit: float = viewport.end.y - 16.0
	if bar != null and bar.is_visible_in_tree():
		bottom_limit = bar.get_global_rect().position.y - 4.0
	for control: Control in [balloon.chat_box_root, balloon.responses_menu]:
		if not control.is_visible_in_tree():
			continue
		control.global_position = Vector2(
			roundf(viewport.get_center().x - control.size.x * 0.5),
			roundf(maxf(viewport.position.y + 4.0, bottom_limit - control.size.y))
		)
