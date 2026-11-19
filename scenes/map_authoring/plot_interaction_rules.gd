extends RefCounted

## Authored purpose is separate from saved construction progress/building_kind.
## Story/NPC land must be driven by its own approved request flow. Until that
## flow exists it grants no general clearing, building choice or construction UI.
enum Purpose { GENERAL, STORY_NPC }
enum Step { NONE, CLEAR, CHOOSE_BUILDING, BUILD }

static func get_interaction_step(purpose: int, phase: String) -> Step:
	if purpose != Purpose.GENERAL:
		return Step.NONE
	match phase:
		"uncleared", "clearing":
			return Step.CLEAR
		"empty":
			return Step.CHOOSE_BUILDING
		"building":
			return Step.BUILD
	return Step.NONE
