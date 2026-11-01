extends "res://scenes/workshop_plot/workshop_plot.gd"

## This view shares the workshop construction state, but has no workshop backend.
## The rubble itself is the interaction target; there is no keeper NPC.
const HOUSE_FOOTPRINTS: Array[Rect2] = [Rect2(-19, -4, 38, 20)]


func get_built_footprints() -> Array[Rect2]:
	return HOUSE_FOOTPRINTS


func _sync_construction() -> void:
	_sync_build_progress()
	var built: bool = construction.phase == "built"
	for path: String in ["Plot", "LeftWall", "LeftWallTop", "RightWall", "RightWallTop", "Table", "TableLegs", "TableResources", "Board"]:
		get_node(path).hide()
	$ToBeClean.visible = construction.phase in ["uncleared", "clearing"]
	$SiteHouse.visible = construction.phase in ["empty", "building"]
	$FinishedHouse.visible = built
	$HouseBody/CollisionShape2D.set_deferred("disabled", not built)
	interaction_area.position = Vector2(0, 8)
	interactable_label_component.position = Vector2(-8, -34)
	$InteractableLabelComponent/HammerIcon.texture = HAND_ICON if construction.phase in ["uncleared", "clearing"] else HAMMER_ICON
	interaction_area.set_deferred("monitoring", not built)
	if built:
		close_menu()
		interactable_label_component.hide()
		if is_instance_valid(player):
			player._on_interactable_deactivated(self)
		$Label.text = ""
	elif construction.phase == "clearing":
		$Label.text = "No worker" if construction.worker_ids.is_empty() else ("Contract expired" if construction._all_workers_payroll_blocked() else "Clearing")
	elif construction.phase == "building":
		$Label.text = "No workers" if construction.worker_ids.is_empty() else ("Contract expired" if construction._all_workers_payroll_blocked() else "Building")
	else:
		$Label.text = ""
