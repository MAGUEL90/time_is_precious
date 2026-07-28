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

var current_action: String = ""
var current_direction: String = ""
var is_action_locked: bool = false

# Playback API

func play_visual(action: String, direction: String) -> void:
	if is_action_locked and action != "pickup":
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


func play_pickup(direction: String) -> void:
	is_action_locked = true
	play_visual("pickup", direction)

	var animation_name: String = "%s_pickup_%s" % [body_id, direction]
	var duration: float = _get_animation_duration(body_sprite, animation_name)
	await get_tree().create_timer(duration).timeout

	is_action_locked = false
	play_visual("idle", direction)


# Playback Timing

func _get_playback_speed(action: String) -> float:
	match action:
		"idle":
			return idle_anim_speed
		"pickup":
			return pickup_anim_speed
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
