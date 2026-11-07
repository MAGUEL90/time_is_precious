extends Node2D

# Provisional presentation-only thresholds, aligned with the existing 40% and
# 75% work bands. They never change a person's actual Satisfaction.
const MOOD_ANGRY_BELOW := 0.20
const MOOD_SAD_BELOW := 0.40
const MOOD_HAPPY_AT := 0.75
const MOOD_REFRESH_SECONDS := 0.25
# Match the daily Satisfaction precision when raid arithmetic lands just below
# a nominal band boundary; this never modifies the underlying value.
const MOOD_COMPARISON_EPSILON := 0.000000001
const EMOTION_SHEETS := {
	"dark": {
		"angry": preload("res://assets/characters/shared_assets/head_assets/idle/dark/angry/dark.png"),
		"happy": preload("res://assets/characters/shared_assets/head_assets/idle/dark/happy/dark.png"),
		"sad": preload("res://assets/characters/shared_assets/head_assets/idle/dark/sad/dark.png"),
		"tired": preload("res://assets/characters/shared_assets/head_assets/idle/dark/tired/dark.png"),
	},
	"light": {
		"angry": preload("res://assets/characters/shared_assets/head_assets/idle/light/angry/light.png"),
		"happy": preload("res://assets/characters/shared_assets/head_assets/idle/light/happy/light.png"),
		"sad": preload("res://assets/characters/shared_assets/head_assets/idle/light/sad/light.png"),
		"tired": preload("res://assets/characters/shared_assets/head_assets/idle/light/tired/light.png"),
	},
	"tan": {
		"angry": preload("res://assets/characters/shared_assets/head_assets/idle/tan/angry/tan.png"),
		"happy": preload("res://assets/characters/shared_assets/head_assets/idle/tan/happy/tan.png"),
		"sad": preload("res://assets/characters/shared_assets/head_assets/idle/tan/sad/tan.png"),
		"tired": preload("res://assets/characters/shared_assets/head_assets/idle/tan/tired/tired.png"),
	},
	"warm": {
		"angry": preload("res://assets/characters/shared_assets/head_assets/idle/warm/angry/warm.png"),
		"happy": preload("res://assets/characters/shared_assets/head_assets/idle/warm/happy/warm.png"),
		"sad": preload("res://assets/characters/shared_assets/head_assets/idle/warm/sad/warm.png"),
		"tired": preload("res://assets/characters/shared_assets/head_assets/idle/warm/tired/warm.png"),
	},
}

const CLAY_WORK_SHEET_PATH: String = "res://assets/characters/shared_assets/cloth_assets/clay_worn_wrap/busy/busy.png"
# The source sheet has nine poses, while the body has eight poses per facing.
# These are candidate pose matches and should be reviewed in motion in both directions.
const CLAY_WORK_POSES := {
	"right": [0, 1, 2, 3, 4, 5, 6, 5],
	"left": [5, 6, 5, 4, 3, 2, 7, 8],
}
# Work hair sheets contain three direction-specific poses per facing. The
# right work head moves down then holds; the left head holds low and rises.
const WORK_HAIR_FRAME_MAPS: Dictionary = {
	"right": [0, 1, 2, 2, 2, 2, 2, 2],
	"left": [3, 3, 3, 3, 3, 3, 4, 5],
}
const WORK_HAIR_ASSET_ROOT: String = "res://assets/characters/shared_assets/hair_assets/busy"

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
var _work_clothes_pose_active: bool = false
var _work_hair_pose_active: bool = false
var _walk_mood_pose_active: bool = false
var _walk_mood_animations: Dictionary = {}
var _head_default_offset: Vector2 = Vector2.ZERO
var _missing_work_clothes_warnings: Dictionary = {}
var _missing_work_hair_warnings: Dictionary = {}
# A reference, not a copied stat. No save fields or source data are changed.
var _satisfaction_source: Resource
var _mood_refresh_left: float = 0.0
var _last_requested_action: String = "idle"
var _last_requested_direction: String = "right"
var _visible_mood: String = ""

# Lifecycle

func _ready() -> void:
	body_sprite.frame_changed.connect(_sync_cart_pose_frames)
	body_sprite.frame_changed.connect(_sync_work_clothes_frame)
	body_sprite.frame_changed.connect(_sync_work_hair_frame)
	body_sprite.frame_changed.connect(_sync_walk_mood_frame)
	_head_default_offset = head_sprite.offset
	# Playback timing belongs to this actor, not every actor sharing the scene.
	for layer: AnimatedSprite2D in [body_sprite, head_sprite, hand_sprite, clothes_sprite, hair_sprite, accessories_sprite]:
		if layer.sprite_frames != null:
			layer.sprite_frames = layer.sprite_frames.duplicate()
	var clay_work_sheet: Texture2D = null
	if ResourceLoader.exists(CLAY_WORK_SHEET_PATH, "Texture2D"):
		clay_work_sheet = load(CLAY_WORK_SHEET_PATH) as Texture2D
	_install_clay_work_animations(clay_work_sheet)
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

# Wires the live resident/worker, not its saved profile. A missing source keeps
# the authored profile unchanged, including manual fixture actors.
func set_satisfaction_source(source: Resource) -> void:
	if _satisfaction_source == source:
		return
	_satisfaction_source = source
	_mood_refresh_left = 0.0
	# Rebinding or detaching must immediately reflect the new source/profile.
	if is_node_ready():
		play_visual(skin_tone, expression, _last_requested_action, _last_requested_direction, accessory, clothes_id, hair_style)


func _process(delta: float) -> void:
	if _satisfaction_source == null or _last_requested_action not in ["idle", "walk"]:
		return
	_mood_refresh_left -= delta
	if _mood_refresh_left > 0.0:
		return
	_mood_refresh_left = MOOD_REFRESH_SECONDS
	if _resolve_mood(expression, _last_requested_action) != _visible_mood:
		play_visual(skin_tone, expression, _last_requested_action, _last_requested_direction, accessory, clothes_id, hair_style)


func _resolve_mood(profile_expression: String, action: String) -> String:
	# Existing tired priority and work/cart head sheets remain authoritative.
	if _satisfaction_source == null or profile_expression == "tired" or action not in ["idle", "walk"]:
		return profile_expression
	var value: float
	if _satisfaction_source is CitizenData:
		value = (_satisfaction_source as CitizenData).satisfaction
	elif _satisfaction_source is WorkerData:
		value = (_satisfaction_source as WorkerData).get_resolved_satisfaction()
	else:
		return profile_expression
	if value < MOOD_ANGRY_BELOW - MOOD_COMPARISON_EPSILON:
		return "angry"
	if value < MOOD_SAD_BELOW - MOOD_COMPARISON_EPSILON:
		return "sad"
	if value >= MOOD_HAPPY_AT - MOOD_COMPARISON_EPSILON:
		return "happy"
	return "base"


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
	_last_requested_action = action
	_last_requested_direction = direction
	var effective_expression := _resolve_mood(expression_id, action)
	_visible_mood = effective_expression

	if clothes_id_param != "":
		clothes_id = clothes_id_param

	if hair_style_id != "":
		hair_style = hair_style_id

	var resolved_direction: String = _normalize_direction(direction)
	_update_cart_visual(action, resolved_direction)
	var resolved_action: String = _resolve_action(action, resolved_direction)
	var visual_key: String = "%s|%s|%s|%s|%s|%s|%s" % [
		skin_tone,
		effective_expression,
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
	_work_clothes_pose_active = false
	_work_hair_pose_active = false
	_walk_mood_pose_active = false
	head_sprite.offset = _head_default_offset
	if cart_visual != null and cart_visual.visible:
		cart_visual.set_frame_and_progress(0, 0.0)

	var playback_speed: float = idle_anim_speed if resolved_action == "idle" or resolved_action == "idle_cart" else anim_speed
	var base_anim: String = "%s_%s" % [resolved_action, resolved_direction]
	var walk_anim: String = "walk_%s" % resolved_direction
	var body_anim: String = "%s_%s" % [skin_tone_id, base_anim]
	var head_anim: String = "%s_%s_%s" % [effective_expression, skin_tone_id, base_anim]
	if resolved_action == "idle":
		_ensure_expression_animation(skin_tone_id, effective_expression, resolved_direction)
	elif resolved_action == "walk":
		_walk_mood_pose_active = _ensure_walk_expression_animation(skin_tone_id, effective_expression, resolved_direction)
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
		var sync_work_clothes: bool = _play_work_clothes(clothes_anim, resolved_direction, playback_speed)
		var sync_work_hair: bool = _play_work_hair(hair_anim, resolved_direction, playback_speed)
		_play_optional_layer(accessories_sprite, accessory, accessory_anim, "", playback_speed)
		_apply_work_timing(expression_id == "tired")
		_work_clothes_pose_active = sync_work_clothes
		_work_hair_pose_active = sync_work_hair
		if _work_clothes_pose_active:
			# One clock also follows worksite owners that manually set the body frame.
			clothes_sprite.pause()
			_sync_work_clothes_frame()
		if _work_hair_pose_active:
			# Match the work body, including worksite owners that manually set it.
			hair_sprite.pause()
			_sync_work_hair_frame()
		return
	if not _has_playable_animation(head_sprite, head_anim):
		head_anim = "base_%s_%s" % [skin_tone_id, base_anim]

	_play_layer(body_sprite, body_anim, "%s_%s" % [skin_tone_id, walk_anim], playback_speed)
	_play_layer(head_sprite, head_anim, "%s_%s_%s" % [expression_id, skin_tone_id, walk_anim], playback_speed)
	if _walk_mood_pose_active:
		# The walk body is the authoritative clock, including manual frame changes.
		head_sprite.pause()
		_sync_walk_mood_frame()

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

# Source idle strips contain right frames 0–1, left frames 2–3. Install
# only the requested clip, preserving the four-frame idle body cadence.
func _ensure_expression_animation(tone: String, emotion: String, direction: String) -> void:
	if head_sprite.sprite_frames == null or not EMOTION_SHEETS.has(tone):
		return
	var palette: Dictionary = EMOTION_SHEETS[tone]
	if not palette.has(emotion):
		return
	var sheet: Texture2D = palette[emotion]
	if sheet == null or sheet.get_size() != Vector2(128, 32):
		return
	var frames: SpriteFrames = head_sprite.sprite_frames
	var animation := "%s_%s_idle_%s" % [emotion, tone, direction]
	if frames.has_animation(animation):
		return
	frames.add_animation(animation)
	frames.set_animation_loop(animation, true)
	var first := 0 if direction == "right" else 2
	for index: int in [first, first + 1, first, first + 1]:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(index * 32, 0, 32, 32)
		frames.add_frame(animation, atlas)


func _ensure_walk_expression_animation(tone: String, emotion: String, direction: String) -> bool:
	if emotion not in ["angry", "sad", "happy"] or head_sprite.sprite_frames == null or not EMOTION_SHEETS.has(tone):
		return false
	var animation := "%s_%s_walk_%s" % [emotion, tone, direction]
	var frames: SpriteFrames = head_sprite.sprite_frames
	if frames.has_animation(animation):
		return _walk_mood_animations.has(animation)
	var palette: Dictionary = EMOTION_SHEETS[tone]
	var sheet: Texture2D = palette.get(emotion)
	if sheet == null or sheet.get_size() != Vector2(128, 32):
		return false
	# The supplied neutral walk heads use the first idle face for the same
	# direction, with a one-pixel vertical bob on alternating body frames.
	# Reuse that exact pose and bob for the existing emotion art.
	frames.add_animation(animation)
	frames.set_animation_loop(animation, true)
	var first := 0 if direction == "right" else 2
	for _index: int in range(4):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(first * 32, 0, 32, 32)
		frames.add_frame(animation, atlas)
	_walk_mood_animations[animation] = true
	return true


func _sync_walk_mood_frame() -> void:
	if not _walk_mood_pose_active or not body_sprite.visible or not head_sprite.visible:
		return
	head_sprite.set_frame_and_progress(body_sprite.frame, body_sprite.frame_progress)
	head_sprite.offset = _head_default_offset + Vector2(0, body_sprite.frame % 2)


func _install_clay_work_animations(sheet: Texture2D) -> bool:
	if sheet == null or sheet.get_size() != Vector2(288, 32) or clothes_sprite.sprite_frames == null:
		return false
	var frames: SpriteFrames = clothes_sprite.sprite_frames
	for direction: String in CLAY_WORK_POSES:
		var animation: String = "clay_worn_wrap_work_" + direction
		# Keep a custom, already-authored work clip intact.
		if _has_playable_animation(clothes_sprite, animation):
			continue
		if not frames.has_animation(animation):
			frames.add_animation(animation)
		frames.set_animation_loop(animation, true)
		for source_frame: int in CLAY_WORK_POSES[direction]:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(source_frame * 32, 0, 32, 32)
			frames.add_frame(animation, atlas)
	return true


func _play_work_clothes(requested_animation: String, direction: String, speed: float) -> bool:
	if _is_default_option(clothes_id) or not body_sprite.visible:
		_hide_layer(clothes_sprite)
		return false
	var animation: String = requested_animation
	if not _matches_work_body(animation):
		# Temporary work-only fallback. The selected outfit ID is never changed.
		animation = "clay_worn_wrap_work_" + direction
	if _matches_work_body(animation):
		return _play_layer(clothes_sprite, animation, "", speed)

	# A missing/invalid work sheet should not silently strip a selected outfit.
	# Hold an existing idle (or walk) pose until the authored work art is available.
	var idle_animation: String = "%s_idle_%s" % [clothes_id, direction]
	var walk_animation: String = "%s_walk_%s" % [clothes_id, direction]
	var shown: bool = _play_layer(clothes_sprite, idle_animation, walk_animation, speed)
	if shown:
		clothes_sprite.pause()
	var warning_key: String = "%s|%s|%s" % [clothes_id, direction, shown]
	if not _missing_work_clothes_warnings.has(warning_key):
		push_warning("No compatible work clothing for '%s'; %s." % [clothes_id, "holding its existing pose" if shown else "no clothing texture is available"])
		_missing_work_clothes_warnings[warning_key] = true
	return false


func _play_work_hair(requested_animation: String, direction: String, speed: float) -> bool:
	if _is_default_option(hair_style):
		_hide_layer(hair_sprite)
		return false
	if not _ensure_work_hair_animation(hair_style, direction):
		# Keep the selected style visible if its dedicated work sheet is missing.
		var idle_animation: String = "%s_idle_%s" % [hair_style, direction]
		var walk_animation: String = "%s_walk_%s" % [hair_style, direction]
		var shown: bool = _play_layer(hair_sprite, idle_animation, walk_animation, speed)
		if shown:
			hair_sprite.pause()
		var warning_key: String = "%s|%s" % [hair_style, direction]
		if not _missing_work_hair_warnings.has(warning_key):
			push_warning("No compatible work hair for '%s'; holding its selected pose." % hair_style)
			_missing_work_hair_warnings[warning_key] = true
		return false
	if not _play_layer(hair_sprite, requested_animation, "", speed):
		return false
	return true


func _ensure_work_hair_animation(style_id: String, direction: String) -> bool:
	var animation: String = "%s_work_%s" % [style_id, direction]
	if _has_playable_animation(hair_sprite, animation):
		return _matches_work_hair_body(animation, direction)
	var style_parts: PackedStringArray = style_id.split("_")
	if style_parts.size() != 3 or not directions.has(direction):
		return false
	var color: String = style_parts[0]
	var sex: String = style_parts[1]
	var number: String = style_parts[2]
	if color not in ["grey", "red", "black", "brown"] or sex not in ["female", "male"] or number not in ["01", "02", "03"]:
		return false
	var texture_path: String = "%s/%s/%s/%s.png" % [WORK_HAIR_ASSET_ROOT, color, sex, number]
	if not ResourceLoader.exists(texture_path, "Texture2D"):
		return false
	var sheet: Texture2D = load(texture_path) as Texture2D
	if sheet == null or sheet.get_size() != Vector2(192, 32):
		return false
	if body_sprite.sprite_frames == null or not _has_playable_animation(body_sprite, str(body_sprite.animation)):
		return false
	var body_count: int = body_sprite.sprite_frames.get_frame_count(body_sprite.animation)
	var frame_map: Array = WORK_HAIR_FRAME_MAPS.get(direction, [])
	if body_count != frame_map.size():
		return false
	var frames: SpriteFrames = hair_sprite.sprite_frames
	if frames == null:
		return false
	if not frames.has_animation(animation):
		frames.add_animation(animation)
	frames.set_animation_loop(animation, true)
	for source_frame: int in frame_map:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(source_frame * 32, 0, 32, 32)
		frames.add_frame(animation, atlas)
	return _matches_work_hair_body(animation, direction)


func _matches_work_hair_body(animation: String, direction: String) -> bool:
	if not body_sprite.visible or not _has_playable_animation(body_sprite, str(body_sprite.animation)):
		return false
	if not _has_playable_animation(hair_sprite, animation):
		return false
	var body_count: int = body_sprite.sprite_frames.get_frame_count(body_sprite.animation)
	var hair_count: int = hair_sprite.sprite_frames.get_frame_count(animation)
	var frame_map: Array = WORK_HAIR_FRAME_MAPS.get(direction, [])
	if hair_count != body_count or hair_count != frame_map.size():
		return false
	for index: int in range(hair_count):
		var texture: Texture2D = hair_sprite.sprite_frames.get_frame_texture(animation, index)
		if texture == null or texture.get_size() != Vector2(32, 32):
			return false
	return true


func _matches_work_body(animation: String) -> bool:
	if not body_sprite.visible or not _has_playable_animation(body_sprite, str(body_sprite.animation)):
		return false
	if not _has_playable_animation(clothes_sprite, animation):
		return false
	var frames: SpriteFrames = clothes_sprite.sprite_frames
	var count: int = frames.get_frame_count(animation)
	if count != body_sprite.sprite_frames.get_frame_count(body_sprite.animation):
		return false
	for index: int in range(count):
		var texture: Texture2D = frames.get_frame_texture(animation, index)
		if texture == null:
			return false
		if texture is AtlasTexture and (texture as AtlasTexture).atlas == null:
			return false
		if texture.get_size().x <= 0 or texture.get_size().y <= 0:
			return false
	return true


func _sync_work_clothes_frame() -> void:
	if _work_clothes_pose_active and body_sprite.visible and clothes_sprite.visible:
		clothes_sprite.set_frame_and_progress(body_sprite.frame, body_sprite.frame_progress)


func _sync_work_hair_frame() -> void:
	if _work_hair_pose_active and body_sprite.visible and hair_sprite.visible:
		hair_sprite.set_frame_and_progress(body_sprite.frame, body_sprite.frame_progress)


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
		if not layer.visible or ((layer == clothes_sprite or layer == hair_sprite) and not str(layer.animation).contains("_work_")):
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
