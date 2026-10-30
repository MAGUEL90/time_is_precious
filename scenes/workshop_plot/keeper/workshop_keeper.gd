extends Node2D
## Owner-supplied layers share a 32px frame: body, sash, bald head, brown beard.
const LAYERS: Dictionary = {
	"Body": preload("res://assets/characters/shared_assets/body_assets/light/idle/light.png"),
	"SashTunic": preload("res://assets/characters/merchant/mudbrick_npc/sash_tunic/idle/idle.png"),
	"Head": preload("res://assets/characters/shared_assets/head_assets/idle/light/base/light.png"),
	"BrownBeard": preload("res://assets/characters/shared_assets/beard_assets/idle/brown/brown_01.png"),
}
var facing: String = "right"
var body: AnimatedSprite2D
func _ready() -> void:
	for title: String in LAYERS:
		var sprite := AnimatedSprite2D.new()
		sprite.name = title
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		for direction: String in ["right","left"]:
			frames.add_animation(direction)
			frames.set_animation_speed(direction,1.0)
			for index: int in range(2):
				var atlas := AtlasTexture.new()
				atlas.atlas = LAYERS[title]
				atlas.region = Rect2((index+(2 if direction=="left" else 0))*32,0,32,32)
				frames.add_frame(direction,atlas)
		sprite.sprite_frames = frames
		sprite.position = Vector2(0,-16)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
	body = get_node("Body")
	body.frame_changed.connect(_sync_layers)
	body.play(facing)
	_sync_layers()
func _process(_delta: float) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if player==null:
		return
	var dx: float = player.global_position.x-global_position.x
	# Same horizontal convention as npc_idle_state, retaining facing in its1px deadzone.
	if absf(dx)>=1.0:
		var next: String = "left" if dx<0 else "right"
		if next!=facing:
			facing = next
			body.play(facing)
			_sync_layers()
func _sync_layers() -> void:
	for layer: AnimatedSprite2D in get_children():
		if layer==body:
			continue
		layer.animation = body.animation
		layer.set_frame_and_progress(body.frame,body.frame_progress)