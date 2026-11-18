extends RefCounted

## Content history, not a save-format version. Published IDs are permanent:
## never remove/reuse retired IDs or derive an older registry from today's scene.
## These revisions describe ID membership only, NOT historical geometry.
## A future addition requires an explicit revision here and migration fixtures.
const PRE_FOREST: Array[String] = [
	"ClaySiteA",
	"WoodSite",
	"ReedSite",
	"StrawSite",
	"WaterSite",
	"ClaySiteB",
	"WoodSiteB",
	"WoodSiteC",
	"WoodSiteD",
	"WoodSiteE",
]
const FOREST_ADDITIONS: Array[String] = [
	"WoodSitePoplar6",
	"WoodSitePoplar7",
	"WoodSitePoplar8",
	"WoodSitePoplar9",
	"WoodSitePoplar10",
	"WoodSitePoplar11",
	"WoodSitePoplar12",
	"WoodSitePoplar13",
	"WoodSitePoplar14",
	"WoodSitePoplar15",
	"WoodSitePoplar16",
	"WoodSitePoplar17",
	"WoodSitePoplar18",
	"WoodSitePoplar19",
	"WoodSitePoplar20",
	"WoodSitePoplar21",
	"WoodSitePoplar22",
	"WoodSitePoplar23",
	"WoodSitePoplar24",
	"WoodSitePoplar25",
	"WoodSitePoplar26",
	"WoodSitePoplar27",
	"WoodSitePoplar28",
	"WoodSitePoplar29",
	"WoodSitePoplar30",
	"WoodSitePoplar31",
	"WoodSitePoplar32",
	"WoodSiteBorder0",
	"WoodSiteBorder1",
	"WoodSiteBorder2",
	"WoodSiteBorder3",
	"WoodSiteBorder4",
	"WoodSiteBorder5",
	"WoodSiteBorder6",
]
const AUTHORING_ADDITIONS: Array[String] = [
	"WoodSitePoplar33",
	"WoodSitePoplar34",
	"WoodSitePoplar35",
	"WoodSitePoplar36",
	"WoodSitePoplar37",
	"WoodSitePoplar38",
]

static func revisions() -> Array[Dictionary]:
	var initial: Dictionary = {}
	for id: String in PRE_FOREST:
		initial[id] = true
	var forest: Dictionary = initial.duplicate()
	for id: String in FOREST_ADDITIONS:
		forest[id] = true
	var authored: Dictionary = forest.duplicate()
	for id: String in AUTHORING_ADDITIONS:
		authored[id] = true
	return [initial, forest, authored]

## Exact registries remain valid for isolated fixtures. Only the complete
## published target permits historical migration; scene drift is not history.
static func plan(saved: Dictionary, current: Dictionary) -> Dictionary:
	if _same_ids(saved, current):
		return {"ok": true, "additions": []}
	var history: Array[Dictionary] = revisions()
	if not _same_ids(current, history.back()):
		return {"ok": false, "additions": []}
	for previous: Dictionary in history:
		if not _same_ids(saved, previous):
			continue
		var additions: Array[String] = []
		for id: String in history.back():
			if not saved.has(id):
				additions.append(id)
		return {"ok": true, "additions": additions}
	return {"ok": false, "additions": []}

static func _same_ids(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for id: Variant in left:
		if typeof(id) != TYPE_STRING or not right.has(id):
			return false
	return true
