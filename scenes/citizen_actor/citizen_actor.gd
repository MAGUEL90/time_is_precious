class_name CitizenActor extends Node2D

@onready var base_worker_visual: Node2D = $BaseWorkerVisual

var citizen_data: CitizenData

func setup(data: CitizenData) -> void:
	if data == null:
		return
	
	citizen_data = data
	var citizen_profile = citizen_data.visual_profile
	
	if citizen_profile == null:
		return
	
	base_worker_visual.apply_profile(
		citizen_profile.skin_tone,
		citizen_profile.expression,
		citizen_profile.accessory,
		citizen_profile.clothes_id,
		citizen_profile.hair_style
	)
