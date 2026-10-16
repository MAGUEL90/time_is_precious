extends Node

const STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const FIXTURE_IDS: Array[String] = [
	"raid_test_z_high_value", "raid_test_a_mythic_lower",
	"raid_test_z_rare_tie", "raid_test_a_common_tie",
	"raid_test_a_id_tie", "raid_test_z_id_tie",
	"raid_test_z_balanced_ratio", "raid_test_a_balanced_low",
	"raid_test_z_food_value", "raid_test_a_base_value",
	"raid_test_a_food_need", "raid_test_z_nonfood_rich",
	"raid_test_oversized", "raid_test_fitting", "raid_test_epsilon",
	"raid_test_zero_weight", "raid_test_negative_weight", "raid_test_infinite_weight"
]

var failures: int = 0
var changed_count: int = 0
var storage: Node
var inventory_before: Dictionary = {}
var watch_reentrancy: bool = false
var signal_observed_lock: bool = false
var reentrant_peek: Dictionary = {}
var reentrant_take: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_install_item_fixtures()
	storage = STORAGE_SCRIPT.new()
	add_child(storage)
	storage.changed.connect(_on_storage_changed)
	inventory_before = Inventory.items.duplicate(true)

	_test_preference_ranking()
	_test_fit_and_invalid_requests()
	_test_invalid_stacks_and_metadata()
	_test_supported_equipment_is_untouched()
	_test_zero_weight_single_item_receipts()

	_expect(Inventory.items == inventory_before,
		"Ranked raid loot never changes player Inventory.")
	_remove_item_fixtures()
	print("CityStorageRankedRaidLootTest %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _test_preference_ranking() -> void:
	_reset({"raid_test_a_mythic_lower": 1, "raid_test_z_high_value": 1})
	var valuables: Dictionary = storage.peek_raid_loot(10.0, "valuables")
	_expect(str(valuables.get("item_id", "")) == "raid_test_z_high_value",
		"Valuables prefer higher base value even when the lower-value item has greater rarity and lighter weight.")
	_expect(int(valuables.get("rarity", -1)) == ItemEnums.Rarity.COMMON
		and str(valuables.get("reason", "")).length() > 0,
		"Peek reports the selected item's rarity and ranking reason.")
	_expect(storage.items == {"raid_test_a_mythic_lower": 1, "raid_test_z_high_value": 1}
		and changed_count == 0,
		"Peeking does not mutate counted stock or emit a change.")

	_reset({"raid_test_z_balanced_ratio": 1, "raid_test_a_balanced_low": 1})
	_expect(str(storage.peek_raid_loot(10.0).get("item_id", "")) == "raid_test_z_balanced_ratio",
		"Balanced ranking uses value per weight instead of alphabetical order.")

	_reset({"raid_test_z_food_value": 1, "raid_test_a_base_value": 1})
	_expect(str(storage.peek_raid_loot(10.0, "balanced").get("item_id", "")) == "raid_test_z_food_value",
		"Balanced ranking uses the greater of base value and food supply before dividing by weight.")

	_reset({"raid_test_a_food_need": 1, "raid_test_z_nonfood_rich": 1})
	var food_choice: Dictionary = storage.peek_raid_loot(10.0, "food")
	_expect(str(food_choice.get("item_id", "")) == "raid_test_a_food_need"
		and str(food_choice.get("reason", "")) == "food supply",
		"Food preference prioritizes a counted food unit over a much more valuable nonfood unit.")

	_reset({"raid_test_a_common_tie": 1, "raid_test_z_rare_tie": 1})
	_expect(str(storage.peek_raid_loot(10.0, "valuables").get("item_id", "")) == "raid_test_z_rare_tie",
		"Rarity breaks equal-value ties before item identifier order.")
	_reset({"raid_test_a_id_tie": 1, "raid_test_z_id_tie": 1})
	_expect(str(storage.peek_raid_loot(10.0, "valuables").get("item_id", "")) == "raid_test_a_id_tie",
		"Equal-value and equal-rarity ties use deterministic item identifier order.")
	_expect(storage.peek_raid_loot(10.0, "unknown").is_empty(),
		"Unknown loot preferences are rejected.")


func _test_fit_and_invalid_requests() -> void:
	_reset({"raid_test_oversized": 1, "raid_test_fitting": 1})
	_expect(str(storage.peek_raid_loot(1.0, "valuables").get("item_id", "")) == "raid_test_fitting",
		"An oversized top-ranked stack is skipped so a lighter fitting item can be selected.")
	_reset({"raid_test_epsilon": 1})
	_expect(str(storage.peek_raid_loot(1.0).get("item_id", "")) == "raid_test_epsilon",
		"Positive item weight within the documented capacity epsilon fits.")

	var invalid_budgets: Array[float] = [-1.0, NAN, INF]
	for budget: float in invalid_budgets:
		_expect(storage.peek_raid_loot(budget).is_empty()
			and storage.take_ranked_raid_item(budget).is_empty(),
			"Negative and nonfinite remaining-weight budgets are rejected.")
	_expect(changed_count == 0, "Invalid requests emit no storage change.")

	_reset({"raid_test_fitting": 1})
	var locked_before: Dictionary = storage.items.duplicate(true)
	storage._transfer_in_progress = true
	_expect(storage.peek_raid_loot(10.0).is_empty()
		and storage.take_ranked_raid_item(10.0).is_empty(),
		"Peek and take reject while another City Storage transfer is in progress.")
	storage._transfer_in_progress = false
	_expect(storage.items == locked_before and changed_count == 0,
		"Transfer-lock rejection preserves the stack and emits no change.")


func _test_invalid_stacks_and_metadata() -> void:
	_reset({"raid_test_fitting": "malformed"})
	var malformed_before: Dictionary = storage.items.duplicate(true)
	_expect(storage.peek_raid_loot(10.0).is_empty()
		and storage.take_ranked_raid_item(10.0).is_empty(),
		"Loot selection rejects an invalid counted stack.")
	_expect(storage.items == malformed_before and changed_count == 0,
		"Invalid counted-stack rejection leaves stock unchanged and emits nothing.")

	_reset({"raid_test_unregistered": 1})
	_expect(storage.peek_raid_loot(10.0).is_empty()
		and storage.take_ranked_raid_item(10.0).is_empty()
		and storage.items == {"raid_test_unregistered": 1} and changed_count == 0,
		"Unregistered stored identifiers are rejected without changing stock.")

	_reset({"raid_test_negative_weight": 1, "raid_test_infinite_weight": 1})
	var invalid_metadata_before: Dictionary = storage.items.duplicate(true)
	_expect(storage.peek_raid_loot(10.0).is_empty()
		and storage.take_ranked_raid_item(10.0).is_empty(),
		"Unknown or invalid item metadata is ineligible for loot.")
	_expect(storage.items == invalid_metadata_before and changed_count == 0,
		"Invalid metadata rejection preserves every counted stack.")


func _test_supported_equipment_is_untouched() -> void:
	_reset({"stone_hammer": 2})
	var items_before: Dictionary = storage.items.duplicate(true)
	var units_before: Dictionary = storage.units.duplicate(true)
	var portions_before: Dictionary = storage.food_portions.duplicate(true)
	_expect(storage.peek_raid_loot(10.0).is_empty()
		and storage.take_ranked_raid_item(10.0).is_empty(),
		"Unique supported equipment stored as allocated units is not counted raid loot.")
	_expect(storage.items == items_before and storage.units == units_before
		and storage.food_portions == portions_before and changed_count == 0,
		"Equipment and fractional food portions remain untouched when loot is rejected.")


func _test_zero_weight_single_item_receipts() -> void:
	_reset({"raid_test_zero_weight": 2})
	var items_before: Dictionary = storage.items.duplicate(true)
	var preview: Dictionary = storage.peek_raid_loot(0.0)
	_expect(str(preview.get("item_id", "")) == "raid_test_zero_weight"
		and is_zero_approx(float(preview.get("weight", -1.0)))
		and not preview.has("quantity"),
		"A zero-weight whole item can be previewed at zero remaining capacity without a bulk quantity.")
	_expect(storage.items == items_before and changed_count == 0,
		"Zero-weight peek leaves its full stack untouched.")

	watch_reentrancy = true
	var first_receipt: Dictionary = storage.take_ranked_raid_item(0.0)
	watch_reentrancy = false
	_expect(str(first_receipt.get("item_id", "")) == "raid_test_zero_weight"
		and int(first_receipt.get("quantity", 0)) == 1,
		"A loot receipt removes exactly one item even from a zero-weight stack.")
	_expect(int(storage.items.get("raid_test_zero_weight", 0)) == 1 and changed_count == 1,
		"Taking one of two zero-weight items leaves one item and emits once.")
	_expect(signal_observed_lock and reentrant_peek.is_empty() and reentrant_take.is_empty(),
		"The transfer lock remains held during changed and rejects reentrant loot calls.")

	var second_receipt: Dictionary = storage.take_ranked_raid_item(0.0)
	_expect(int(second_receipt.get("quantity", 0)) == 1
		and not storage.items.has("raid_test_zero_weight") and changed_count == 2,
		"Taking the final stack item erases its key and emits one additional change.")
	_expect(storage.take_ranked_raid_item(0.0).is_empty() and changed_count == 2,
		"An empty stack cannot be taken again or emit another change.")
	_expect(storage.units == {"unit_hammer": {"tool_id": "stone_hammer", "name": "Test Hammer", "worker_id": "worker"}}
		and storage.food_portions == {"barley_bread": 2},
		"Successful loot never changes unique equipment or fractional food portions.")


func _reset(next_items: Dictionary) -> void:
	storage.items = next_items.duplicate(true)
	storage.units = {
		"unit_hammer": {
			"tool_id": "stone_hammer",
			"name": "Test Hammer",
			"worker_id": "worker"
		}
	}
	storage.food_portions = {"barley_bread": 2}
	storage._transfer_in_progress = false
	changed_count = 0
	watch_reentrancy = false
	signal_observed_lock = false
	reentrant_peek = {}
	reentrant_take = {}


func _on_storage_changed() -> void:
	changed_count += 1
	if watch_reentrancy:
		signal_observed_lock = storage._transfer_in_progress
		reentrant_peek = storage.peek_raid_loot(10.0)
		reentrant_take = storage.take_ranked_raid_item(10.0)


func _install_item_fixtures() -> void:
	_create_item("raid_test_z_high_value", 5.0, 10, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_a_mythic_lower", 1.0, 9, ItemEnums.Rarity.MYTHIC)
	_create_item("raid_test_z_rare_tie", 1.0, 4, ItemEnums.Rarity.RARE)
	_create_item("raid_test_a_common_tie", 1.0, 4, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_a_id_tie", 1.0, 4, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_z_id_tie", 1.0, 4, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_z_balanced_ratio", 2.0, 6, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_a_balanced_low", 1.0, 1, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_z_food_value", 2.0, 1, ItemEnums.Rarity.COMMON, 6)
	_create_item("raid_test_a_base_value", 2.0, 5, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_a_food_need", 5.0, 1, ItemEnums.Rarity.COMMON, 1)
	_create_item("raid_test_z_nonfood_rich", 1.0, 100, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_oversized", 5.0, 100, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_fitting", 1.0, 1, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_epsilon", 1.0000005, 1, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_zero_weight", 0.0, 4, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_negative_weight", -1.0, 20, ItemEnums.Rarity.COMMON)
	_create_item("raid_test_infinite_weight", INF, 20, ItemEnums.Rarity.COMMON)


func _create_item(item_id: String, weight: float, value: int, rarity: ItemEnums.Rarity, food_value: int = 0) -> void:
	var item_data: ItemData = ItemData.new()
	item_data.id = item_id
	item_data.weight = weight
	item_data.base_value_shekel = value
	item_data.rarity = rarity
	item_data.food_supply_value = food_value
	ItemDatabase.items_by_id[item_id] = item_data


func _remove_item_fixtures() -> void:
	for item_id: String in FIXTURE_IDS:
		ItemDatabase.items_by_id.erase(item_id)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
