extends Node
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
var failures: int = 0
func _ready() -> void:
	var codec = VALUES.new()
	var citizen := CitizenData.new()
	citizen.citizen_id = "saved_resident"
	citizen.visual_profile = VisualProfile.new()
	citizen.visual_profile.skin_tone = "dark"
	var order := WorkOrder.new()
	order.order_id = "saved_order"
	order.inputs_snapshot["stone"] = 12
	var batch := ProcessBatch.new()
	batch.batch_id = "saved_batch"
	batch.fee_ids.append("fee_1")
	var station := StationState.new()
	station.setup("drying_yard", 2)
	station.set_slot(1, batch)
	var raw: Dictionary = {&"name": "value", 12: [9223372036854775807, -9223372036854775807 - 1, Vector2(3.5, -9), NodePath("Authored/Path")], "citizen": citizen, "order": order, "station": station}
	var encoded: Variant = codec.encode(raw)
	_check(codec.error.is_empty(), "Supported values encode.")
	var restored: Variant = codec.decode(JSON.parse_string(JSON.stringify(encoded, "", true, true)))
	_check(codec.error.is_empty() and restored is Dictionary, "JSON roundtrip preserves value tags.")
	if restored is Dictionary:
		_check(restored[12] == raw[12], "Int64 extremes, vectors and data-only paths survive exactly.")
		_check(restored.citizen.visual_profile.skin_tone == "dark" and restored.order.inputs_snapshot["stone"] == 12, "Explicit Resource fields survive.")
		_check(restored.station.slots[0] == null and restored.station.slots[1].fee_ids == ["fee_1"], "Nested typed process state survives.")
	codec.encode(self)
	_check(not codec.error.is_empty(), "Live Nodes cannot enter the save.")
	codec.decode({"$type": "object", "class": "Node", "fields": {}})
	_check(not codec.error.is_empty(), "Save-controlled engine classes cannot be instantiated.")
	codec.decode({"$type": "object", "class": "CitizenData", "fields": {}})
	_check(not codec.error.is_empty(), "Missing object fields reject instead of silently defaulting.")
	codec.decode({"$type": "int", "value": "9223372036854775808"})
	_check(not codec.error.is_empty(), "Out-of-range int64 is rejected.")
	codec.encode(INF)
	_check(not codec.error.is_empty(), "Nonfinite values are rejected.")
	print("CitySaveValuesTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
