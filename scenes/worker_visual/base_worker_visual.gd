extends Node2D

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var clothes_sprite: AnimatedSprite2D = $ClothesSprite
@onready var head_sprite: AnimatedSprite2D = $HeadSprite
@onready var accessories_sprite: AnimatedSprite2D = $AccessoriesSprite
@onready var hand_sprite: AnimatedSprite2D = $HandSprite
@onready var hair_sprite: AnimatedSprite2D = $HairSprite

@export var anim_speed: float = 3.0
@export var idle_anim_speed: float = 1.0
@export_enum("idle", "walk") var default_action: String = "walk"
@export var default_direction: String = "side"
@export_enum("light", "tan", "warm") var skin_tone: String = "light"
@export var expression: String = "base"
@export_enum("none", "clay_worn_wrap") var clothes_id: String = "clay_worn_wrap"
@export_enum("none", "curly_hair_grey_01", "long_hair_grey_01", "simple_hair_grey_01", "simple_hair_grey_02", "simple_hair_grey_03", "simple_hair_grey_04") var hair_style: String = "simple_hair_grey_01"
@export_enum("none", "farmer_hat", "tied_work_band") var accessory: String = "none"

var skin_tones: Array[String] = ["light", "tan", "warm"]
var expressions: Array[String] = ["base"]
var clothes: Array[String] = ["none", "clay_worn_wrap"]
var hair_styles: Array[String] = [
	"none",
	"curly_hair_grey_01",
	"long_hair_grey_01",
	"simple_hair_grey_01",
	"simple_hair_grey_02",
	"simple_hair_grey_03",
	"simple_hair_grey_04",
]
var accessories: Array[String] = ["none", "farmer_hat", "tied_work_band"]

func _ready() -> void:
	play_visual(skin_tone, expression, default_action, default_direction, accessory, clothes_id, hair_style)

func play_visual(skin_tone_id: String,
				expression_id: String,
				action: String,
				direction: String,
				accessory_id: String,
				clothes_id_param: String = "",
				hair_style_id: String = "") -> void:
	skin_tone = skin_tone_id
	expression = expression_id
	accessory = accessory_id

	if clothes_id_param != "":
		clothes_id = clothes_id_param

	if hair_style_id != "":
		hair_style = hair_style_id

	var playback_speed: float = idle_anim_speed if action == "idle" else anim_speed
	var base_anim: String = "%s_%s" % [action, direction]
	var walk_anim: String = "walk_%s" % direction
	var body_anim: String = "%s_%s" % [skin_tone_id, base_anim]
	var head_anim: String = "%s_%s_%s" % [expression_id, skin_tone_id, base_anim]
	var hand_anim: String = "%s_%s" % [skin_tone_id, base_anim]
	var clothes_anim: String = "%s_%s" % [clothes_id, base_anim]
	var hair_anim: String = "%s_%s" % [hair_style, base_anim]
	var accessory_anim: String = "%s_%s" % [accessory_id, base_anim]

	_play_layer(body_sprite, body_anim, "%s_%s" % [skin_tone_id, walk_anim], playback_speed)
	_play_layer(head_sprite, head_anim, "%s_%s_%s" % [expression_id, skin_tone_id, walk_anim], playback_speed)

	if action == "idle":
		hand_sprite.visible = false
	else:
		_play_layer(hand_sprite, hand_anim, "%s_%s" % [skin_tone_id, walk_anim], playback_speed)

	_play_optional_layer(clothes_sprite, clothes_id, clothes_anim, "%s_%s" % [clothes_id, walk_anim], playback_speed)
	_play_optional_layer(hair_sprite, hair_style, hair_anim, "%s_%s" % [hair_style, walk_anim], playback_speed)
	_play_optional_layer(accessories_sprite, accessory_id, accessory_anim, "%s_%s" % [accessory_id, walk_anim], playback_speed)

func _play_layer(layer: AnimatedSprite2D, anim_name: String, fallback_anim: String = "", playback_speed: float = -1.0) -> bool:
	var resolved_speed: float = playback_speed if playback_speed >= 0.0 else anim_speed

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

	layer.visible = false
	return false

func _play_optional_layer(layer: AnimatedSprite2D, layer_id: String, anim_name: String, fallback_anim: String = "", playback_speed: float = -1.0) -> void:
	if layer_id == "none":
		layer.visible = false
		return

	_play_layer(layer, anim_name, fallback_anim, playback_speed)

func _has_playable_animation(layer: AnimatedSprite2D, anim_name: String) -> bool:
	return (
		layer.sprite_frames != null
		and layer.sprite_frames.has_animation(anim_name)
		and layer.sprite_frames.get_frame_count(anim_name) > 0
	)

func apply_profile(skin_tone_id: String,
					expression_id: String,
					accessory_id: String,
					clothes_id_param: String = "",
					hair_style_id: String = "") -> void:
	skin_tone = skin_tone_id
	expression = expression_id
	accessory = accessory_id

	if clothes_id_param != "":
		clothes_id = clothes_id_param

	if hair_style_id != "":
		hair_style = hair_style_id

	play_visual(skin_tone, expression, default_action, default_direction, accessory, clothes_id, hair_style)
