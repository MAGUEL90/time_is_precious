extends RefCounted

## Fixed identity and location of the removed main-map stockpiles. Old saves
## contain counts but not item IDs, so their authored mapping is kept here.
const STOCKPILES: Dictionary = {
	"ClayStorage": {"site_id": "ClaySiteA", "item_id": "clay_lump", "position": Vector2(-24, -24)},
	"WoodStorage": {"site_id": "WoodSite", "item_id": "wood_log", "position": Vector2(-24, 8)},
	"ReedStorage": {"site_id": "ReedSite", "item_id": "reed_bundle", "position": Vector2(-24, 40)},
	"StrawStorage": {"site_id": "StrawSite", "item_id": "straw_bundle", "position": Vector2(24, -24)},
	"WaterStorage": {"site_id": "WaterSite", "item_id": "water_jar", "position": Vector2(24, 8)},
}
