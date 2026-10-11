extends Control
class_name RaiderTypeIcon

const TYPE_TEXTURES: Dictionary = {
	"light": preload("res://assets/ui/ui_icon/light_raider_icon.png"),
	"normal": preload("res://assets/ui/ui_icon/raider_icon.png"),
	# Keep the asset author's original filename.
	"heavy": preload("res://assets/ui/ui_icon/heavt_raider_icon.png"),
}
var type_id: String = ""
var source_texture: Texture2D

func set_icon(next_type_id: String, next_texture: Texture2D = null) -> void:
	type_id = next_type_id.to_lower()
	source_texture = next_texture if next_texture != null else TYPE_TEXTURES.get(type_id)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func _draw() -> void:
	if source_texture != null:
		# Native pixels, centered on whole coordinates inside the card.
		draw_texture(source_texture, ((size - source_texture.get_size()) * 0.5).floor())
