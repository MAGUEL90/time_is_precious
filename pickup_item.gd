class_name PickUpItem extends Node2D

const ITEM_CHANGE_POPUP_SCENE: PackedScene = preload("res://scenes/ui/item_change_popup/item_change_popup.tscn")

var player_reff: Player

@export var item_id: String
@export var quantity: int = 1
@onready var icon: Sprite2D = $Icon
@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent
@onready var collision_shape_2d: CollisionShape2D = $InteractableComponent/CollisionShape2D

var idle_tween: Tween
var highlight_tween: Tween
var icon_default_position: Vector2
var icon_default_scale: Vector2
var icon_default_modulate: Color
var is_collecting: bool = false
var collecting_tween: Tween
var shake_tween: Tween

# Setup / Lifecycle

func _ready() -> void:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		push_error("PickupItem: item_id '%s' not found in ItemDatabase." % item_id)
		return

	if item_data.icon == null:
		push_error("ItemData does not have icon.")

	icon.texture = item_data.icon
	icon_default_position = icon.position
	icon_default_scale = icon.scale
	icon_default_modulate = icon.modulate
	_start_idle_float()

	player_reff = get_tree().get_first_node_in_group("player") as Player

	if player_reff:
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))

# Idle feedback

func _start_idle_float() -> void:
	if idle_tween and idle_tween.is_valid():
		idle_tween.kill()

	idle_tween = create_tween()
	idle_tween.set_loops()
	idle_tween.tween_property(icon, "position", icon_default_position + Vector2(0, -1), 0.95).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(icon, "position", icon_default_position, 0.95).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Collection flow

func on_player_interact(player: Player) -> void:
	if is_collecting:
		return

	if Inventory != null and Inventory.has_method("try_add_item"):
		var is_success: bool = Inventory.call("try_add_item", item_id, quantity)
		if is_success:
			is_collecting = true

			if idle_tween and idle_tween.is_valid():
				idle_tween.kill()

			if highlight_tween and highlight_tween.is_valid():
				highlight_tween.kill()

			icon.position = icon_default_position

			collision_shape_2d.disabled = true
			interactable_label_component.hide()
			_spawn_pickup_popup(player)

			collecting_tween = create_tween()
			collecting_tween.tween_property(self, "global_position", player.global_position, 0.1).set_ease(Tween.EASE_IN_OUT)
			collecting_tween.tween_property(self, "scale", Vector2.ZERO, 0.05)
			await collecting_tween.tween_interval(0.2).finished
			queue_free()
		else:
			if not Inventory.has_capacity_for(item_id, quantity):
				play_failed_pickup_shake()

	else:
		print("Please double check")

func _spawn_pickup_popup(player: Player) -> void:
	var item_popup = ITEM_CHANGE_POPUP_SCENE.instantiate()
	get_tree().current_scene.add_child(item_popup)
	item_popup.global_position = player.global_position + Vector2(0, -28)
	item_popup.setup(item_id, quantity, true)

# Interaction focus feedback

func on_player_enter_interaction() -> void:
	if not Inventory.has_capacity_for(item_id, quantity):
		interactable_label_component.label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.18, 1.0))
		interactable_label_component.set_text("Inventory Full")

	else:
		interactable_label_component.set_text("press E to collect")
		_play_focus_highlight()

func _play_focus_highlight() -> void:
	if is_collecting:
		return

	if highlight_tween and highlight_tween.is_valid():
		highlight_tween.kill()

	highlight_tween = create_tween()
	highlight_tween.set_parallel()
	highlight_tween.tween_property(icon, "modulate", Color(1.25, 1.25, 1.1, 1.0), 0.12)

func on_player_exit_interaction() -> void:
	if is_collecting:
		return

	if highlight_tween and highlight_tween.is_valid():
		highlight_tween.kill()

	highlight_tween = create_tween()
	highlight_tween.set_parallel()
	highlight_tween.tween_property(icon, "modulate", icon_default_modulate, 0.1)

# Failure feedback

func play_failed_pickup_shake() -> void:
	var original_position: Vector2 = position
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()

	shake_tween = create_tween()
	shake_tween.tween_property(self, "position", original_position + Vector2(4, 0), 0.04)
	shake_tween.tween_property(self, "position", original_position + Vector2(-4, 0), 0.04)
	shake_tween.tween_property(self, "position", original_position + Vector2(2, 0), 0.03)
	shake_tween.tween_property(self, "position", original_position, 0.03)

# Drop spawn feedback

func play_drop_spawn_feedback() -> void:
	scale = Vector2(0.75, 0.75)
	modulate.a = 0.0

	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
