extends Node2D
## Ground torch presentation and a small solid footprint at its base.
const BASE := preload("res://assets/objects/ground_torch.png")
const FIRE := preload("res://assets/objects/ground_torch_fire_animation.png")
const MAX_LIGHT_ENERGY := 0.8
@export_node_path("Sprite2D") var authored_torch_path: NodePath
var torch_light: PointLight2D
var fire_sprite: AnimatedSprite2D

func _ready() -> void:
	# The authored sprite is the only placement source. This runtime view stays
	# in the city's common Y-sort world; no position polling or scene mutation.
	var source := get_node_or_null(authored_torch_path) as Sprite2D
	if source == null or source.texture != BASE:
		push_error("Ground torch binding requires the authored ground_torch sprite: " + str(authored_torch_path))
		hide()
		set_process(false)
		return
	global_transform = source.global_transform
	visible = source.is_visible_in_tree()
	var base := Sprite2D.new()
	base.name = "GroundTorchBase"
	base.texture = BASE
	base.centered = source.centered
	base.offset = source.offset
	base.flip_h = source.flip_h
	base.flip_v = source.flip_v
	add_child(base)
	fire_sprite = AnimatedSprite2D.new()
	var fire := fire_sprite
	fire.name = "GroundTorchFire"
	fire.position = Vector2(0, -5)
	fire.sprite_frames = SpriteFrames.new()
	fire.sprite_frames.add_animation("burn")
	fire.sprite_frames.set_animation_speed("burn", 6.0)
	fire.sprite_frames.set_animation_loop("burn", true)
	for index: int in range(4):
		var frame := AtlasTexture.new()
		frame.atlas = FIRE
		frame.region = Rect2(index * 24, 0, 24, 24)
		fire.sprite_frames.add_frame("burn", frame)
	add_child(fire)
	fire.play("burn")
	_create_collision()
	_create_light()
	_update_light()
	# Hide only this instance's duplicate artwork after the functional view exists.
	source.hide()

func _create_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "GroundTorchBody"
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 8)
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.position = Vector2(0, 1)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _create_light() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.85))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.32))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 96
	texture.height = 96
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	torch_light = PointLight2D.new()
	torch_light.name = "GroundTorchLight"
	torch_light.position = Vector2(0, -5)
	torch_light.texture = texture
	torch_light.color = Color(1.0, 0.68, 0.34)
	add_child(torch_light)

func _process(_delta: float) -> void:
	_update_light()

func _update_light() -> void:
	if not is_instance_valid(torch_light) or not is_instance_valid(TimeComponentManager.environment):
		return
	# The flame is extinguished throughout morning and daytime; it is lit again
	# when the existing evening period starts. No time or weather state is changed.
	var lit: bool = TimeComponentManager.current_hour < TimeComponentManager.morning_hour or TimeComponentManager.current_hour >= TimeComponentManager.noon_hour
	fire_sprite.visible = lit
	if not lit:
		torch_light.energy = 0.0
		torch_light.enabled = false
		return
	# Follow the visible environment tint, including its existing smooth transition.
	var ambient_red: float = TimeComponentManager.environment.color.r
	var strength: float = clampf((0.90 - ambient_red) / 0.65, 0.0, 1.0)
	torch_light.energy = strength * MAX_LIGHT_ENERGY
	torch_light.enabled = strength > 0.001
