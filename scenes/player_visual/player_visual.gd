class_name PlayerVisual extends Node2D

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var clothes_sprite: AnimatedSprite2D = $ClothesSprite
@onready var head_sprite: AnimatedSprite2D = $HeadSprite
@onready var hand_sprite: AnimatedSprite2D = $HandSprite
@onready var hair_sprite: AnimatedSprite2D = $HairSprite
@onready var accessories_sprite: AnimatedSprite2D = $AccessoriesSprite

@export_category("Visual Variants")
@export_enum("dark", "light", "tan", "warm") var body_id: String = "light"
@export_enum("default", "clay_worn_wrap", "plain_worn_wrap") var clothes_id: String = "default"
@export_enum("dark", "light", "tan", "warm") var head_id: String = "light"
@export_enum("default", "player_hair") var hair_id: String = "player_hair"
@export_enum("dark", "light", "tan", "warm") var hand_id: String = "light"
@export_enum("default", "farmer_hat") var accessory_id: String = "default"

@export_category("Playback")
@export var walk_anim_speed: float = 6.0
@export var idle_anim_speed: float = 1.0
@export var pickup_anim_speed: float = 8.0
@export var faint_anim_speed: float = 5.0

var current_action: String = ""
var current_direction: String = ""
var is_action_locked: bool = false
var wood_work_pose: Node2D

# Playback API

func play_visual(action: String, direction: String) -> void:
	if is_instance_valid(wood_work_pose) and wood_work_pose.visible:
		if action != "faint":
			return
		wood_work_pose.hide()
		is_action_locked = false
	if is_action_locked and action != "pickup" and action != "faint":
		return

	if current_action == action and current_direction == direction:
		return

	current_action = action
	current_direction = direction

	var anim_suffix := "%s_%s" % [action, direction]

	var playback_speed: float = _get_playback_speed(action)
	var body_anim: String = "%s_%s" % [body_id, anim_suffix]
	var clothes_anim: String = "%s_%s" % [clothes_id, anim_suffix]
	var head_anim: String = "base_%s_%s" % [head_id, anim_suffix]
	var hair_anim: String = "%s_%s" % [hair_id, anim_suffix]
	var hand_anim: String = "%s_%s" % [hand_id, anim_suffix]
	var accessory_anim: String = "%s_%s" % [accessory_id, anim_suffix]

	_play_layer(body_sprite, body_anim, "", playback_speed)
	_play_optional_layer(clothes_sprite, clothes_id, clothes_anim, playback_speed)
	_play_layer(head_sprite, head_anim, "", playback_speed)
	_play_optional_layer(hair_sprite, hair_id, hair_anim, playback_speed)

	if action == "idle":
		_hide_layer(hand_sprite)
	else:
		_play_layer(hand_sprite, hand_anim, "", playback_speed)

	_play_optional_layer(accessories_sprite, accessory_id, accessory_anim, playback_speed)


func begin_wood_work(direction: String, presentation_parent: Control = null) -> void:
	if not is_instance_valid(wood_work_pose):
		wood_work_pose = preload("res://scenes/worker_visual/work_2_axe_pose.gd").new()
		wood_work_pose.name = "WoodWorkPose"
		wood_work_pose.process_mode = Node.PROCESS_MODE_ALWAYS
		wood_work_pose.hide()
		add_child(wood_work_pose)
	var hair_texture: Texture2D = null
	if hair_id == "player_hair":
		hair_texture = hair_sprite.sprite_frames.get_frame_texture("player_hair_idle_right", 0)
	var head_texture: Texture2D = head_sprite.sprite_frames.get_frame_texture("base_%s_idle_right" % head_id, 0)
	wood_work_pose.configure(body_id, head_id, hand_id, hair_id, hair_texture, head_texture)
	for layer: AnimatedSprite2D in [body_sprite, clothes_sprite, head_sprite, hand_sprite, hair_sprite, accessories_sprite]:
		layer.hide()
	current_action = "chop_wood"
	current_direction = direction
	is_action_locked = true
	wood_work_pose.start(direction)
	if presentation_parent != null:
		wood_work_pose.reparent(presentation_parent, false)
		wood_work_pose.position = (presentation_parent.size * 0.5).round()
		wood_work_pose.scale *= 2.0

func end_wood_work() -> void:
	if not is_instance_valid(wood_work_pose):
		return
	var was_visible: bool = wood_work_pose.visible
	wood_work_pose.hide()
	if wood_work_pose.get_parent() != self:
		wood_work_pose.reparent(self, false)
	wood_work_pose.position = Vector2.ZERO
	wood_work_pose.scale = Vector2.ONE
	if not was_visible:
		return
	is_action_locked = false
	current_action = ""
	play_visual("idle", current_direction)

func play_pickup(direction: String) -> void:
	is_action_locked = true
	play_visual("pickup", direction)

	var animation_name: String = "%s_pickup_%s" % [body_id, direction]
	var duration: float = _get_animation_duration(body_sprite, animation_name)
	await get_tree().create_timer(duration).timeout

	# Collapse may replace pickup before this timer finishes.
	if current_action != "pickup":
		return
	is_action_locked = false
	play_visual("idle", direction)

func play_faint(direction: String) -> void:
	is_action_locked = true
	play_visual("faint", direction)

	var animation_name: String = "%s_faint_%s" % [body_id, direction]
	var duration: float = _get_animation_duration(
		body_sprite,
		animation_name
	)

	await get_tree().create_timer(duration).timeout

	is_action_locked = false

# Playback Timing

func _get_playback_speed(action: String) -> float:
	match action:
		"idle":
			return idle_anim_speed
		"pickup":
			return pickup_anim_speed
		"faint":
			return faint_anim_speed
		_:
			return walk_anim_speed


func _get_animation_duration(layer: AnimatedSprite2D, anim_name: String) -> float:
	if not _has_playable_animation(layer, anim_name):
		return 0.25

	var frame_count: int = layer.sprite_frames.get_frame_count(anim_name)
	var speed: float = layer.sprite_frames.get_animation_speed(anim_name)
	if speed <= 0.0:
		return 0.25

	return float(frame_count) / speed


# Layer Playback

func _play_layer(
	layer: AnimatedSprite2D,
	anim_name: String,
	fallback_anim: String,
	playback_speed: float = -1.0
) -> bool:
	var resolved_speed: float = playback_speed if playback_speed >= 0.0 else walk_anim_speed

	if _has_playable_animation(layer, anim_name):
		layer.sprite_frames.set_animation_speed(anim_name, resolved_speed)
		layer.play(anim_name)
		layer.set_frame_and_progress(0, 0.0)
		layer.visible = true
		return true

	if fallback_anim != "" and _has_playable_animation(layer, fallback_anim):
		layer.sprite_frames.set_animation_speed(fallback_anim, resolved_speed)
		layer.play(fallback_anim)
		layer.set_frame_and_progress(0, 0.0)
		layer.visible = true
		return true

	_hide_layer(layer)
	return false


func _play_optional_layer(
	layer: AnimatedSprite2D,
	layer_id: String,
	anim_name: String,
	playback_speed: float = -1.0
) -> void:
	if _is_default_option(layer_id):
		_hide_layer(layer)
		return

	_play_layer(layer, anim_name, "", playback_speed)


func _hide_layer(layer: AnimatedSprite2D) -> void:
	layer.stop()
	layer.visible = false


# Animation Validation

func _has_playable_animation(layer: AnimatedSprite2D, anim_name: String) -> bool:
	return (
		layer.sprite_frames != null
		and layer.sprite_frames.has_animation(anim_name)
		and layer.sprite_frames.get_frame_count(anim_name) > 0
	)


func _is_default_option(layer_id: String) -> bool:
	return layer_id == "" or layer_id == "default" or layer_id == "none"
