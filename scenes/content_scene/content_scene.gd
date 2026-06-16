extends Node2D

@onready var npc_gabbi: Gabbi = $Actors/NPC_Gabbi

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	npc_gabbi.allow_random_walk = false
