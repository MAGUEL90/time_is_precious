extends "res://scenes/workshop_plot/workshop_plot.gd"

## Presentation for the authored main workshop; construction and production stay native.
const KEEPER_DIALOGUE = preload("res://scenes/workshop_plot/keeper/workshop_keeper_dialogue.gd")
const KEEPER_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
const BUILT_FOOTPRINTS: Array[Rect2] = [
	Rect2(-13, -30, 48, 40), Rect2(-13, 10, 7, 14), Rect2(6, 10, 29, 14),
]
const OPEN_FOOTPRINTS: Array[Rect2] = [
	Rect2(-24, -13, 48, 5), Rect2(-24, -8, 7, 32), Rect2(17, -8, 7, 32),
]
var keeper_dialogue: CanvasLayer
var _open_shapes: Array[CollisionShape2D] = []
var _built_shapes: Array[CollisionShape2D] = []

func _ready() -> void:
	var talk_range := CircleShape2D.new()
	talk_range.radius = 20.0
	$InteractableComponent/CollisionShape2D.shape = talk_range
	for rect: Rect2 in OPEN_FOOTPRINTS:
		_open_shapes.append(_add_footprint(rect))
	for rect: Rect2 in BUILT_FOOTPRINTS:
		_built_shapes.append(_add_footprint(rect))
	_add_footprint(get_keeper_footprint())
	super._ready()

func _add_footprint(rect: Rect2) -> CollisionShape2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return collision

func get_built_footprints() -> Array[Rect2]:
	return BUILT_FOOTPRINTS

func get_keeper_footprint() -> Rect2:
	return Rect2(13, 30, 6, 4)

func _sync_construction() -> void:
	super._sync_construction()
	var built: bool = construction.phase == "built"
	$FinishedBuilding.visible = built
	for path: String in ["Plot", "LeftWall", "LeftWallTop", "RightWall", "RightWallTop", "Table", "TableLegs", "TableResources"]:
		get_node(path).visible = not built and path != "TableResources"
	$Board.hide()
	interaction_area.position = $Craftsman.position + Vector2(0, -4)
	interactable_label_component.position = $Craftsman.position + Vector2(-8, -42)
	for shape: CollisionShape2D in _open_shapes:
		shape.set_deferred("disabled", built)
	for shape: CollisionShape2D in _built_shapes:
		shape.set_deferred("disabled", not built)
	# WorkerEntrance is the stable schema8 authored target. DoorEntrance marks art
	# only; moving the saved target would invalidate existing physical approaches.
	var backend: WorkShop = get_node_or_null("BuiltWorkshop") as WorkShop
	if backend != null:
		backend.get_node("InteractableComponent").position = interaction_area.position
		backend.interactable_label_component.position = interactable_label_component.position
		backend.interactable_label_component.position_offset = interactable_label_component.position

func on_player_interact(interacting_player: Player) -> void:
	# Completed plots relinquish E ownership to BuiltWorkshop in the native sync.
	# Its WorkShop handler opens the production menu without another greeting.
	if construction != null and construction.phase == "built":
		return
	if interacting_player != player or is_instance_valid(menu) or is_instance_valid(keeper_dialogue) or not has_player_access():
		return
	if not player.can_move or player.current_interactable != self or get_tree().paused:
		return
	var greeting: String = ""
	match construction.phase:
		"uncleared":
			greeting = "Once, this yard was my trade. Here we shaped clay into bricks. Wilt thou help me clear the rubble?"
		"empty":
			greeting = "The ground is clear. Bring materials and willing workers, and we shall raise this workshop anew."
		"clearing":
			greeting = "The rubble is being cleared. Let us see how the work fares."
		"building":
			greeting = "Willing hands raise these walls anew. Let us see how the building fares."
	keeper_dialogue = KEEPER_DIALOGUE.new()
	add_child(keeper_dialogue)
	keeper_dialogue.continued.connect(_continue_keeper_dialogue)
	keeper_dialogue.cancelled.connect(_close_keeper_dialogue)
	player.set_movement_locked(&"keeper_dialogue", true)
	interactable_label_component.hide()
	keeper_dialogue.open(greeting, $Craftsman)
	get_viewport().set_input_as_handled()

func _close_keeper_dialogue() -> void:
	if not is_instance_valid(keeper_dialogue):
		return
	keeper_dialogue.queue_free()
	keeper_dialogue = null
	if is_instance_valid(player):
		player.set_movement_locked(&"keeper_dialogue", false)
		if has_player_access() and player.current_interactable == self:
			interactable_label_component.show()

func _continue_keeper_dialogue() -> void:
	_close_keeper_dialogue()
	super.on_player_interact(player)

func close_menu() -> void:
	_close_keeper_dialogue()
	super.close_menu()

func _process(delta: float) -> void:
	super._process(delta)
	_update_keeper_hint()
	if is_instance_valid(keeper_dialogue) and not has_player_access():
		_close_keeper_dialogue()

func _update_keeper_hint() -> void:
	var bounds: Rect2 = KEEPER_BOUNDS.measure($Craftsman)
	if not bounds.has_area():
		return
	var hints: Array[Control] = [interactable_label_component]
	var backend: WorkShop = get_node_or_null("BuiltWorkshop") as WorkShop
	if backend != null:
		hints.append(backend.interactable_label_component)
	for hint: Control in hints:
		var anchor := Vector2(bounds.get_center().x - hint.size.x * 0.5, bounds.position.y - 4.0 - hint.size.y)
		hint.position = (hint.get_parent() as Node2D).to_local(anchor)
		if hint is InteractableLabelComponent:
			hint.position_offset = hint.position

func _exit_tree() -> void:
	_close_keeper_dialogue()
	super._exit_tree()
