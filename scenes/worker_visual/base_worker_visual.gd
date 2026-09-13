extends Node2D

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var clothes_sprite: AnimatedSprite2D = $ClothesSprite
@onready var head_sprite: AnimatedSprite2D = $HeadSprite
@onready var accessories_sprite: AnimatedSprite2D = $AccessoriesSprite
@onready var hand_sprite: AnimatedSprite2D = $HandSprite
@onready var hair_sprite: AnimatedSprite2D = $HairSprite

@export var anim_speed: float = 3.0
@export var idle_anim_speed: float = 1.0
@export_range(1.0, 8.0, 0.25) var tired_first_frame_hold: float = 2.0
@export_range(1.0, 8.0, 0.25) var tired_last_frame_hold: float = 2.0
@export_enum("idle", "walk", "work", "push_cart", "idle_cart") var default_action: String = "idle"
@export_enum("left", "right") var default_direction: String = "right"
@export_enum("dark", "light", "tan", "warm") var skin_tone: String = "light"
@export var expression: String = "base"
@export_enum("default", "clay_worn_wrap", "plain_worn_wrap") var clothes_id: String = "clay_worn_wrap"
@export_enum("default",
			"grey_female_01", "grey_female_02", "grey_female_03",
			"grey_male_01", "grey_male_02", "grey_male_03",
			"red_female_01", "red_female_02", "red_female_03",
			"red_male_01", "red_male_02", "red_male_03",
			"black_female_01", "black_female_02", "black_female_03",
			"black_male_01", "black_male_02", "black_male_03",
			"brown_female_01", "brown_female_02", "brown_female_03",
			"brown_male_01", "brown_male_02", "brown_male_03") var hair_style: String = "grey_male_01"
@export_enum("default", "farmer_hat") var accessory: String = "default"

var skin_tones: Array[String] = ["dark", "light", "tan", "warm"]
var expressions: Array[String] = ["base", "tired"]
var directions: Array[String] = ["left", "right"]
var clothes: Array[String] = ["default", "clay_worn_wrap", "plain_worn_wrap"]
var hair_styles: Array[String] = [
	"default",
	"grey_female_01", "grey_female_02", "grey_female_03",
	"grey_male_01", "grey_male_02", "grey_male_03",
	"red_female_01", "red_female_02", "red_female_03",
	"red_male_01", "red_male_02", "red_male_03",
	"black_female_01", "black_female_02", "black_female_03",
	"black_male_01", "black_male_02", "black_male_03",
	"brown_female_01", "brown_female_02", "brown_female_03",
	"brown_male_01", "brown_male_02", "brown_male_03"
	]

var accessories: Array[String] = ["default", "farmer_hat"]
var current_visual_key: String = ""
var cart_visual: AnimatedSprite2D
var _work_frame_durations: Dictionary = {}
var _cart_pose_active: bool = false

# Lifecycle

func _ready() -> void:
	body_sprite.frame_changed.connect(_sync_cart_pose_frames)
	# Playback timing belongs to this actor, not every actor sharing the scene.
	for layer: AnimatedSprite2D in [body_sprite, head_sprite, hand_sprite, clothes_sprite, hair_sprite, accessories_sprite]:
		if layer.sprite_frames != null:
			layer.sprite_frames = layer.sprite_frames.duplicate()
	play_visual(
		skin_tone,
		expression,
		default_action,
		default_direction,
		accessory,
		clothes_id,
		hair_style
	)


# Public API

func play_visual(
	skin_tone_id: String,
	expression_id: String,
	action: String,
	direction: String,
	accessory_id: String,
	clothes_id_param: String = "",
	hair_style_id: String = ""
) -> void:
	skin_tone = skin_tone_id
	expression = expression_id
	accessory = accessory_id if accessory_id != "" else "default"

	if clothes_id_param != "":
		clothes_id = clothes_id_param

	if hair_style_id != "":
		hair_style = hair_style_id

	var resolved_direction: String = _normalize_direction(direction)
	_update_cart_visual(action, resolved_direction)
	var resolved_action: String = _resolve_action(action, resolved_direction)
	var visual_key: String = "%s|%s|%s|%s|%s|%s|%s" % [
		skin_tone,
		expression,
		resolved_action,
		resolved_direction,
		accessory,
		clothes_id,
		hair_style
	]

	if current_visual_key == visual_key:
		return

	current_visual_key = visual_key
	_cart_pose_active = false
	if cart_visual != null and cart_visual.visible:
		cart_visual.set_frame_and_progress(0, 0.0)

	var playback_speed: float = idle_anim_speed if resolved_action == "idle" or resolved_action == "idle_cart" else anim_speed
	var base_anim: String = "%s_%s" % [resolved_action, resolved_direction]
	var walk_anim: String = "walk_%s" % resolved_direction
	var body_anim: String = "%s_%s" % [skin_tone_id, base_anim]
	var head_anim: String = "%s_%s_%s" % [expression_id, skin_tone_id, base_anim]
	var hand_anim: String = "%s_%s" % [skin_tone_id, base_anim]
	var clothes_anim: String = "%s_%s" % [clothes_id, base_anim]
	var hair_anim: String = "%s_%s" % [hair_style, base_anim]
	var accessory_anim: String = "%s_%s" % [accessory, base_anim]
	if resolved_action == "push_cart" or resolved_action == "idle_cart":
		_play_cart_visual(resolved_action, resolved_direction, playback_speed)
		return
	if resolved_action == "work":
		_play_layer(body_sprite, body_anim, "", playback_speed)
		_play_layer(head_sprite, head_anim, "base_%s_%s" % [skin_tone_id, base_anim], playback_speed)
		_hide_layer(hand_sprite)
		# Only matching work layers may overlay the supplied body/head motion.
		_play_optional_layer(clothes_sprite, clothes_id, clothes_anim, "", playback_speed)
		_play_optional_layer(hair_sprite, hair_style, hair_anim, "", playback_speed)
		_play_optional_layer(accessories_sprite, accessory, accessory_anim, "", playback_speed)
		_apply_work_timing(expression_id == "tired")
		return
	if not _has_playable_animation(head_sprite, head_anim):
		head_anim = "base_%s_%s" % [skin_tone_id, base_anim]

	_play_layer(body_sprite, body_anim, "%s_%s" % [skin_tone_id, walk_anim], playback_speed)
	_play_layer(head_sprite, head_anim, "%s_%s_%s" % [expression_id, skin_tone_id, walk_anim], playback_speed)

	if resolved_action == "idle":
		_hide_layer(hand_sprite)
	else:
		_play_layer(hand_sprite, hand_anim, "%s_%s" % [skin_tone_id, walk_anim], playback_speed)

	_play_optional_layer(clothes_sprite, clothes_id, clothes_anim, "%s_%s" % [clothes_id, walk_anim], playback_speed)
	_play_optional_layer(hair_sprite, hair_style, hair_anim, "%s_%s" % [hair_style, walk_anim], playback_speed)
	_play_optional_layer(accessories_sprite, accessory, accessory_anim, "%s_%s" % [accessory, walk_anim], playback_speed)


func apply_profile(
	skin_tone_id: String,
	expression_id: String,
	accessory_id: String,
	clothes_id_param: String = "",
	hair_style_id: String = ""
) -> void:
	skin_tone = skin_tone_id
	expression = expression_id
	accessory = accessory_id

	if clothes_id_param != "":
		clothes_id = clothes_id_param

	if hair_style_id != "":
		hair_style = hair_style_id

	play_visual(
		skin_tone,
		expression,
		default_action,
		default_direction,
		accessory,
		clothes_id,
		hair_style
	)


# Layer Playback

func _update_cart_visual(action: String, direction: String) -> void:
	var show_cart: bool = action in ["push_cart", "idle_cart"]
	if show_cart and cart_visual == null:
		cart_visual = preload("res://scenes/worker_visual/worker_cart.tscn").instantiate()
		cart_visual.sprite_frames = cart_visual.sprite_frames.duplicate()
		add_child(cart_visual)
	if cart_visual != null:
		var was_visible: bool = cart_visual.visible
		cart_visual.visible = show_cart
		cart_visual.flip_h = direction == "left"
		if show_cart:
			cart_visual.sprite_frames.set_animation_speed(action, idle_anim_speed if action == "idle_cart" else anim_speed)
			if not was_visible or cart_visual.animation != action:
				cart_visual.play(action)
				cart_visual.set_frame_and_progress(0, 0.0)
			elif not cart_visual.is_playing() and not _cart_pose_active:
				cart_visual.play(action)

func _play_cart_visual(action: String, direction: String, playback_speed: float) -> void:
	# Use the supplied light body/head/hand sheets with their original colors.
	var suffix: String = "light_%s_%s" % [action, direction]
	_play_layer(body_sprite, suffix, "", playback_speed)
	_play_layer(head_sprite, "base_%s" % suffix, "", playback_speed)
	if action == "push_cart":
		_play_layer(hand_sprite, suffix, "", playback_speed)
	else:
		_hide_layer(hand_sprite)
	# Cart sheets currently have no matching clothing, hair, or accessory layers.
	# Keep those layers hidden instead of mixing ordinary walk art into the pose.
	_hide_layer(clothes_sprite)
	_hide_layer(hair_sprite)
	_hide_layer(accessories_sprite)
	var mirrored: bool = direction == "left"
	body_sprite.flip_h = mirrored
	head_sprite.flip_h = mirrored
	hand_sprite.flip_h = mirrored
	# One clock keeps layers aligned when hands resume after an idle/cart change.
	_cart_pose_active = true
	head_sprite.pause()
	hand_sprite.pause()
	cart_visual.pause()
	_sync_cart_pose_frames()


func _sync_cart_pose_frames() -> void:
	if not _cart_pose_active:
		return
	for layer: AnimatedSprite2D in [head_sprite, hand_sprite, cart_visual]:
		if layer != null and layer.visible:
			layer.set_frame_and_progress(body_sprite.frame, body_sprite.frame_progress)


func _resolve_action(action: String, direction: String) -> String:
	if action != "push_cart" and action != "idle_cart":
		return action
	if not _has_cart_visual("light", action, direction):
		return "walk" if action == "push_cart" else "idle"
	return action


func _has_cart_visual(skin_tone_id: String, action: String, direction: String) -> bool:
	var suffix: String = "%s_%s_%s" % [skin_tone_id, action, direction]
	var has_body_and_head: bool = (
		_has_playable_animation(body_sprite, suffix)
		and _has_playable_animation(head_sprite, "base_%s" % suffix)
	)
	if action == "idle_cart":
		return has_body_and_head
	return has_body_and_head and _has_playable_animation(hand_sprite, suffix)

func _apply_work_timing(tired: bool) -> void:
	for layer: AnimatedSprite2D in [body_sprite, head_sprite, clothes_sprite, hair_sprite, accessories_sprite]:
		if not layer.visible:
			continue
		var frames: SpriteFrames = layer.sprite_frames
		var animation: StringName = layer.animation
		var count: int = frames.get_frame_count(animation)
		var key: String = str(layer.name) + ":" + str(animation)
		if not _work_frame_durations.has(key):
			var durations: Array[float] = []
			for i in range(count):
				durations.append(frames.get_frame_duration(animation, i))
			_work_frame_durations[key] = durations
		for i in range(count):
			var multiplier: float = 1.0
			if tired and i == 0:
				multiplier = tired_first_frame_hold
			elif tired and i == count - 1:
				multiplier = tired_last_frame_hold
			frames.set_frame(animation, i, frames.get_frame_texture(animation, i), _work_frame_durations[key][i] * multiplier)

func _play_layer(
	layer: AnimatedSprite2D,
	anim_name: String,
	fallback_anim: String = "",
	playback_speed: float = -1.0
) -> bool:
	var resolved_speed: float = playback_speed if playback_speed >= 0.0 else anim_speed

	if _has_playable_animation(layer, anim_name):
		layer.sprite_frames.set_animation_speed(anim_name, resolved_speed)
		layer.play(anim_name)
		layer.set_frame_and_progress(0, 0.0)
		layer.flip_h = false
		layer.visible = true
		return true

	if fallback_anim != "" and _has_playable_animation(layer, fallback_anim):
		layer.sprite_frames.set_animation_speed(fallback_anim, resolved_speed)
		layer.play(fallback_anim)
		layer.set_frame_and_progress(0, 0.0)
		layer.flip_h = false
		layer.visible = true
		return true

	_hide_layer(layer)
	return false


func _play_optional_layer(
	layer: AnimatedSprite2D,
	layer_id: String,
	anim_name: String,
	fallback_anim: String = "",
	playback_speed: float = -1.0
) -> void:
	if _is_default_option(layer_id):
		_hide_layer(layer)
		return

	_play_layer(layer, anim_name, fallback_anim, playback_speed)


func _hide_layer(layer: AnimatedSprite2D) -> void:
	layer.stop()
	layer.flip_h = false
	layer.visible = false


# Animation Resolution

func _is_default_option(layer_id: String) -> bool:
	return layer_id == "" or layer_id == "default" or layer_id == "none"


func _normalize_direction(direction: String) -> String:
	if direction == "side":
		return default_direction
	if directions.has(direction):
		return direction
	return default_direction


func _has_playable_animation(layer: AnimatedSprite2D, anim_name: String) -> bool:
	return (
		layer.sprite_frames != null
		and layer.sprite_frames.has_animation(anim_name)
		and layer.sprite_frames.get_frame_count(anim_name) > 0
	)
