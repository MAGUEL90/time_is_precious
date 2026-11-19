extends Node2D
## Presentation copy of the player's shared busy animation.
const PLAYER_VISUAL := preload("res://scenes/player_visual/player_visual.tscn")
var actor: PlayerVisual

func configure(visual: PlayerVisual) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	actor = PLAYER_VISUAL.instantiate()
	actor.body_id = visual.body_id
	actor.head_id = visual.head_id
	actor.hand_id = visual.hand_id
	actor.clothes_id = visual.clothes_id
	actor.hair_id = visual.hair_id
	actor.accessory_id = visual.accessory_id
	add_child(actor)
	var direction := visual.current_direction if visual.current_direction in ["left", "right"] else "right"
	var busy_animation := "%s_busy_%s" % [actor.body_id, direction]
	actor.body_sprite.sprite_frames.set_animation_loop(busy_animation, false)
	actor.body_sprite.animation_finished.connect(_on_busy_finished.bind(direction), CONNECT_ONE_SHOT)
	actor.play_visual("busy", direction)

func _on_busy_finished(direction: String) -> void:
	if is_instance_valid(actor) and actor.current_action == "busy":
		actor.play_visual("idle", direction)
