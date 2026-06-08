extends Node2D

@onready var row: HBoxContainer = $Row
@onready var icon: TextureRect = $Row/Icon
@onready var amount_label: Label = $Row/AmountLabel

func setup(item_id: String, amount: int, is_positive: bool) -> void:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return
	icon.texture = item_data.icon
	if is_positive:
		amount_label.text = "+" + str(amount)
		popup_effect(is_positive)
	else:
		amount_label.text = "-" + str(amount)
		popup_effect(is_positive)

func popup_effect(is_positive: bool) -> void:
	row.position = Vector2(-12, -8)

	modulate = Color(1, 1, 1, 1)

	if is_positive:
		amount_label.self_modulate = Color.GREEN
	else:
		amount_label.self_modulate = Color.RED

	var tween: Tween = get_tree().create_tween()

	tween.parallel().tween_property(self, "position", position + Vector2(0, -6), 0.4)
	tween.parallel().tween_property(self, "scale", Vector2(1.1, 1.1), 0.4)
	tween.tween_property(self, "position", position + Vector2(0, 0), 0.2)
	tween.parallel().tween_property(self, "scale", Vector2.ZERO, 0.2)
	# tween.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	tween.finished.connect(queue_free)
