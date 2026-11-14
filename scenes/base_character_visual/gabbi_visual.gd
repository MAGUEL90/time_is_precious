extends BaseCharacterVisual

const HEAD_WALK: Texture2D = preload("res://assets/characters/shared_assets/head_assets/walk/light/base/light.png")

func _ready() -> void:
	# Gabbi owns these frames; the shared base still contains old multi-row slices.
	head_sprite.sprite_frames = head_sprite.sprite_frames.duplicate(true)
	for direction: String in ["right", "left"]:
		for frame: int in range(4):
			var texture := AtlasTexture.new()
			texture.atlas = HEAD_WALK
			texture.region = Rect2((frame + (4 if direction == "left" else 0)) * 32, 0, 32, 32)
			head_sprite.sprite_frames.set_frame("head_walk_" + direction, frame, texture)

func play_visual(action: String, direction: String) -> void:
	# Gabbi's authored sheets face right; mirror only her custom layers.
	hair_sprite.flip_h = direction == "left"
	clothes_sprite.flip_h = direction == "left"
	# Native left body/head frames mirror around x=15; flip_h on a 32px
	# custom sheet mirrors around x=15.5. Align their pivots, not the PNGs.
	var mirrored_offset := -1.0 if direction == "left" else 0.0
	hair_sprite.position.x = mirrored_offset
	clothes_sprite.position.x = mirrored_offset
	super.play_visual(action, direction)
