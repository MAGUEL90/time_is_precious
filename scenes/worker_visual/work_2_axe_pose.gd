extends Node2D
## Presentation only: no item, worker, clock, or save mutations.
const ROOT := "res://assets/characters/shared_assets/"
const FRAME_COUNT := 13
var sprites: Array[Sprite2D] = []
var hair_offsets: Array[Vector2] = []
var elapsed := 0.0
var frames_per_second := 13.0
var profile_key := ""

func configure(body: String, head: String, hand: String, hair: String,
		player_hair: Texture2D = null, player_head: Texture2D = null) -> void:
	var key := "%s|%s|%s|%s" % [body, head, hand, hair]
	if key == profile_key:
		return
	for sprite: Sprite2D in sprites:
		remove_child(sprite)
		sprite.queue_free()
	sprites.clear()
	hair_offsets.clear()
	profile_key = key
	var paths: Array[String] = [
		"body_assets/work_2/%s/%s.png" % [body, body],
		"cloth_assets/clay_worn_wrap/work_2/work_2.png",
		"head_assets/work_2/%s/%s.png" % [head, head],
		"tools_assets/work_2/axe/axe.png",
		"hand_assets/work_2/%s/%s.png" % [hand, hand]]
	for path: String in paths:
		var sprite := Sprite2D.new()
		sprite.texture = load(ROOT + path)
		sprite.hframes = FRAME_COUNT
		add_child(sprite)
		sprites.append(sprite)
	var hair_sprite := Sprite2D.new()
	if player_hair != null:
		# The player has no work_2 hair sheet. Keep the original hair pixels and
		# follow the source head's displacement instead of substituting civil hair.
		hair_sprite.texture = player_hair
		var source: Image = sprites[2].texture.get_image()
		var reference: Rect2i = player_head.get_image().get_used_rect()
		for index: int in range(FRAME_COUNT):
			var bounds: Rect2i = source.get_region(Rect2i(index * 32, 0, 32, 32)).get_used_rect()
			hair_offsets.append(Vector2(bounds.position - reference.position))
	elif hair != "default":
		var parts := hair.split("_")
		if parts.size() == 3:
			hair_sprite.texture = load(ROOT + "hair_assets/work_2/%s/%s/%s.png" % [parts[0], parts[1], parts[2]])
			hair_sprite.hframes = FRAME_COUNT
	add_child(hair_sprite)
	sprites.append(hair_sprite)
	# Keep the gripping hand in front of hair without changing the axe's depth.
	move_child(sprites[4], -1)

func start(direction: String, speed: float = 13.0) -> void:
	if not visible:
		elapsed = 0.0
	frames_per_second = speed
	scale.x = -1.0 if direction == "left" else 1.0
	show()
	_set_frame(int(elapsed * frames_per_second) % FRAME_COUNT)

func _process(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	_set_frame(int(elapsed * frames_per_second) % FRAME_COUNT)

func _set_frame(index: int) -> void:
	for sprite: Sprite2D in sprites:
		if sprite.hframes == FRAME_COUNT:
			sprite.frame = index
	if not hair_offsets.is_empty():
		sprites[5].position = hair_offsets[index]
