class_name BaseCharacterVisual extends Node2D

@export var body_variant := "light"
@export var clothes_variant := "clay_worn_wrap"
@export var head_variant := "head"
@export var hair_variant := "hair"
@export var hand_variant := "light"
@export var accessories_variant := "default"

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var clothes_sprite: AnimatedSprite2D = $ClothesSprite
@onready var head_sprite: AnimatedSprite2D = $HeadSprite
@onready var hand_sprite: AnimatedSprite2D = $HandSprite
@onready var hair_sprite: AnimatedSprite2D = $HairSprite
@onready var accessories_sprite: AnimatedSprite2D = $AccessoriesSprite

var walk_anim_speed: float = 6.0
var idle_anim_speed: float = 1.0

var current_action: String = ""
var current_direction: String = ""

func play_visual(action: String, direction: String) -> void:
	
	if current_action == action and current_direction == direction:
		return
	
	current_action = action
	current_direction = direction
	
	var anim_suffix := "%s_%s" % [action, direction]
	
	var playback_speed: float = idle_anim_speed if action == "idle" else walk_anim_speed
	var body_anim: String = "%s_%s" % [body_variant, anim_suffix]
	var clothes_anim: String = "%s_%s" % [clothes_variant, anim_suffix]
	var head_anim: String = "%s_%s" % [head_variant, anim_suffix]
	var hair_anim: String = "%s_%s" % [hair_variant, anim_suffix]
	var hand_anim: String = "%s_%s" % [hand_variant, anim_suffix]
	
	_play_layer(body_sprite, body_anim,"", playback_speed)
	_play_layer(clothes_sprite, clothes_anim, "default", playback_speed)
	_play_layer(head_sprite, head_anim, "", playback_speed)
	_play_layer(hair_sprite, hair_anim, "", playback_speed)
	
	if action == "idle":
		_hide_layer(hand_sprite)
	
	else:
		_play_layer(hand_sprite, hand_anim, "", playback_speed)
	
	accessories_sprite.visible = false

func _play_layer(layer: AnimatedSprite2D, 
				anim_name: String, 
				fallback_anim: String, 
				playback_speed: float = -1.0) -> bool:
	
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

func _has_playable_animation(layer: AnimatedSprite2D, anim_name: String) -> bool:
	if layer == null:
		return false
	
	return (
		layer.sprite_frames != null
		and layer.sprite_frames.has_animation(anim_name)
		and layer.sprite_frames.get_frame_count(anim_name) > 0
	)

func _hide_layer(layer: AnimatedSprite2D) -> void:
	layer.stop()
	layer.visible = false
