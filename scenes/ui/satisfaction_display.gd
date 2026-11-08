extends RefCounted


static func to_percent(value: float) -> int:
	if value > 0.0 and value < 0.01:
		return 1
	return roundi(value * 100.0)
