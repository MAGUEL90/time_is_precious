class_name InitialCitizenSeed extends Resource

## New-citizen defaults only. IDs, professions and legacy-save repair stay in
## InitialWorksites; editing this resource never rewrites an existing citizen.
@export var display_name: String = ""
@export_range(0.0, 1.0, 0.01) var satisfaction: float = 0.55
@export var visual_profile: VisualProfile

func validation_error() -> String:
	if display_name.strip_edges().is_empty():
		return "Starter display name must not be empty."
	if not is_finite(satisfaction) or satisfaction < 0.0 or satisfaction > 1.0:
		return "Starter Satisfaction must be finite and between zero and one."
	if visual_profile == null:
		return "Starter visual profile must be explicit."
	return ""

func create_visual_profile() -> VisualProfile:
	# Resources are cached/shared, but each citizen owns its mutable appearance.
	return visual_profile.duplicate(true) as VisualProfile
