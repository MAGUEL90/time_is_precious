extends Node2D

@onready var row: HBoxContainer = $Row
@onready var icon: TextureRect = $Row/Icon
@onready var amount_label: Label = $Row/AmountLabel

# Public API

func setup(item_id: String, amount: int, is_positive: bool) -> void:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return

	icon.texture = item_data.icon

	if is_positive:
		amount_label.text = "+" + str(amount)
	else:
		amount_label.text = "-" + str(amount)

	_play_popup_effect(is_positive)

# Popup animation

func _play_popup_effect(is_positive: bool) -> void:
	row.position = Vector2(-14, -8)

	modulate = Color(1, 1, 1, 1)

	if is_positive:
		amount_label.self_modulate = Color.GREEN
	else:
		amount_label.self_modulate = Color.RED

	var start_position: Vector2 = position
	var tween: Tween = get_tree().create_tween()

	tween.tween_property(
		self,
		"position",
		start_position + Vector2(0, -6),
		0.6
	).set_trans(Tween.TRANS_LINEAR)

	tween.parallel().tween_property(
		self,
		"modulate:a",
		0.0,
		0.2
	).set_delay(0.4)

	tween.finished.connect(queue_free)
