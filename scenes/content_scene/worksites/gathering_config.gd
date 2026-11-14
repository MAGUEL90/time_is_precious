extends RefCounted

## Shared configuration, not live work/save state. Units are game minutes.
## Keep durations positive, unique and ascending. Changes need balance approval.
const HOURLY_DURATIONS: Array[int] = [180, 360, 540]

## Fallbacks for the original clay fixture and markers without overrides.
## Authored marker values (for example wood/reed rates) still take precedence.
const DEFAULT_ITEM_ID: String = "clay_lump"
const DEFAULT_MINUTES_PER_UNIT: int = 10
const DEFAULT_STOCK: int = 72

## Existing finite-deposit balance; separate from the legacy daily-stock fallback.
const RESOURCE_CAPACITY: Dictionary = {
	"clay_lump": 36, "wood_log": 24, "reed_bundle": 40, "water_jar": 48,
}
const RESPAWN_MIN_MINUTES: int = 2 * 1440
const RESPAWN_MAX_MINUTES: int = 3 * 1440

static func duration_label(minutes: int) -> String:
	return "%dh" % (minutes / 60) if minutes % 60 == 0 else "%dmin" % minutes

static func duration_choice_message() -> String:
	var labels := PackedStringArray()
	for minutes: int in HOURLY_DURATIONS:
		labels.append(duration_label(minutes))
	return "Choose " + ", ".join(labels) + "."
