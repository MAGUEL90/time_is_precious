extends Node2D

const OFFSET_SPAWN: Vector2 = Vector2(24, 0)

@export var citizen_actor_scene: PackedScene = preload("res://scenes/citizen_actor/citizen_actor.tscn")
@export var spawn_position: Vector2

var spawn_index: int = 0

func _ready() -> void:
	for citizen_data in CitizenManager.get_all_citizens():
		_spawn_citizen_actor(citizen_data)
	
	CitizenManager.citizen_added.connect(_on_citizen_added)

func _on_citizen_added(citizen_data: CitizenData) -> void:
	_spawn_citizen_actor(citizen_data)

func _spawn_citizen_actor(citizen_data: CitizenData) -> void:
	if citizen_actor_scene == null:
		return
	
	var actor: CitizenActor = citizen_actor_scene.instantiate() as CitizenActor
	if actor == null:
		return
	
	add_child(actor)
	actor.global_position = spawn_position + OFFSET_SPAWN * spawn_index
	spawn_index += 1
	actor.setup(citizen_data)
