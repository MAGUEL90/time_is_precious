extends Node

## Render-only motion. The palm source, pickup locations and save identity never move.
const SWAY_SHADER: Shader = preload("res://scenes/pickup_item/palm_sway.gdshader")
const PERIOD: float = 5.0
const AMPLITUDE_PIXELS: float = 2.0

var sprite: Sprite2D
var original_material: Material
var sway_material: ShaderMaterial
var elapsed: float = 0.0
var phase: float = 0.0
var last_offset: float = INF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	sprite = get_parent() as Sprite2D
	if sprite == null:
		set_process(false)
		return
	# A duplicated palm can inherit the original's runtime material. Give it an
	# independent clock/material without replacing an authored material.
	var previous: Material = sprite.material
	if previous is ShaderMaterial and previous.shader == SWAY_SHADER:
		previous = null
	if previous != null:
		set_process(false)
		return
	original_material = previous
	sway_material = ShaderMaterial.new()
	sway_material.shader = SWAY_SHADER
	sprite.material = sway_material
	phase = float(absi(str(sprite.get_path()).hash()) % 1000) / 1000.0 * TAU
	_update_offset()

func _process(delta: float) -> void:
	if TimeComponentManager.is_paused or SceneTransition.is_transitioning or not sprite.is_visible_in_tree():
		return
	elapsed = fposmod(elapsed + delta, PERIOD)
	_update_offset()

func _update_offset() -> void:
	# Quantized offsets retain the project's native pixel-art cadence.
	var offset: float = roundf(sin(elapsed * TAU / PERIOD + phase) * AMPLITUDE_PIXELS)
	if offset != last_offset:
		sway_material.set_shader_parameter("sway_pixels", offset)
		last_offset = offset

func _exit_tree() -> void:
	if is_instance_valid(sprite) and sprite.material == sway_material:
		sprite.material = original_material
