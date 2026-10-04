extends Node

## One run's authoritative visit ledger, hosted under existing WorkStateRuntime.
## No disk-save schema. Scene views never own stock or generate visit money.
signal changed

const MAX_INT: int = 9223372036854775807
@export var config: Resource = preload("res://resources/traveling_merchant/common_merchant.tres")
var _stock: Dictionary[String, int] = {}
var _offers: Dictionary = {}
var _demand: Dictionary[String, int] = {}
var _budget: int = 0
var _visit_day: int = -1
var _latest_minute: int = -1
var _present: bool = false
var _trading: bool = false
var _valid: bool = false

func _ready() -> void:
	_valid = _validate_config()
	TimeComponentManager.time_changed.connect(_on_time_changed)
	_sync_clock()

func _validate_config() -> bool:
	if config == null or config.first_day < 0 or config.interval_days <= 0 or config.arrival_hour < 0 or config.departure_hour > 24 or config.arrival_hour >= config.departure_hour or config.starting_shekel < 0:
		return false
	for offer: Dictionary in config.offers:
		var id: String = str(offer.get("item_id", ""))
		if id.is_empty() or id == "shekel" or _offers.has(id) or ItemDatabase.get_item_data(id) == null:
			return false
		for key: String in ["stock", "buy_price"]:
			if not offer.get(key) is int or int(offer[key]) < 0:
				return false
		_offers[id] = offer.duplicate(true)
		_offers[id]["sell_price"] = 0
		_offers[id]["requested"] = 0
	var seen: Dictionary = {}
	for request: Dictionary in config.requests:
		var id: String = str(request.get("item_id", ""))
		if id.is_empty() or id == "shekel" or seen.has(id) or ItemDatabase.get_item_data(id) == null:
			return false
		for key: String in ["quantity", "sell_price"]:
			if not request.get(key) is int or int(request[key]) <= 0:
				return false
		seen[id] = true
		if not _offers.has(id):
			_offers[id] = {"stock": 0, "buy_price": 0}
		if _offers[id].buy_price > 0 and request.sell_price > _offers[id].buy_price:
			return false
		_offers[id]["sell_price"] = request.sell_price
		_offers[id]["requested"] = request.quantity
	return not _offers.is_empty()

func _sync_clock() -> void:
	_on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute, "")

func _on_time_changed(day: int, hour: int, minute: int, _weather: String) -> void:
	if not _valid:
		return
	var now: int = day * 1440 + hour * 60 + minute
	# Rewinding debug time must never create another budget or restore sold stock.
	if now < _latest_minute:
		_present = false
		changed.emit()
		return
	_latest_minute = now
	_present = _is_visit_time(day, hour)
	if _present and day > _visit_day:
		_visit_day = day
		_budget = config.starting_shekel
		_stock.clear()
		_demand.clear()
		for id: String in _offers:
			_stock[id] = int(_offers[id].stock)
			_demand[id] = int(_offers[id].requested)
	changed.emit()

func _is_visit_time(day: int, hour: int) -> bool:
	return day >= config.first_day and (day - config.first_day) % config.interval_days == 0 and hour >= config.arrival_hour and hour < config.departure_hour

func is_present() -> bool:
	var clock := TimeComponentManager
	var now: int = clock.current_day * 1440 + clock.current_hour * 60 + clock.current_minute
	return _valid and _present and now >= _latest_minute and clock.current_day == _visit_day and _is_visit_time(clock.current_day, clock.current_hour)

func get_budget() -> int:
	return _budget

func get_catalog() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in _offers:
		rows.append({"item_id": id, "stock": _stock.get(id, 0), "buy_price": _offers[id].buy_price, "sell_price": _offers[id].sell_price, "player_qty": Inventory.items.get(id, 0), "demand": _demand.get(id, 0), "requested": _offers[id].requested})
	return rows

func get_status_text() -> String:
	if not _valid:
		return "Merchant configuration unavailable."
	if is_present():
		return "Common merchant | Leaves today at %02d:00" % config.departure_hour
	var day: int = maxi(TimeComponentManager.current_day, config.first_day)
	var remainder: int = (day - config.first_day) % config.interval_days
	if remainder != 0:
		day += config.interval_days - remainder
	elif TimeComponentManager.current_day == day and TimeComponentManager.current_hour >= config.departure_hour:
		day += config.interval_days
	var prefix: String = "Tomorrow" if day == TimeComponentManager.current_day + 1 else "Day %d" % day
	return "Next merchant: %s at %02d:00" % [prefix, config.arrival_hour]

func quote(item_id: String, quantity: int, buying: bool) -> Dictionary:
	if _trading:
		return _failure("A trade is already being completed.")
	if not is_present():
		return _failure("The merchant is not here.")
	if quantity <= 0 or not _offers.has(item_id):
		return _failure("Choose an available item and a positive quantity.")
	var offer: Dictionary = _offers[item_id]
	var price: int = offer.buy_price if buying else offer.sell_price
	if price <= 0:
		return _failure("The merchant does not trade this item in that direction.")
	@warning_ignore("integer_division")
	var max_quantity: int = MAX_INT / price
	if quantity > max_quantity:
		return _failure("Trade amount is too large.")
	var total: int = price * quantity
	var owned: int = Inventory.items.get(item_id, 0)
	var wallet: int = Inventory.items.get("shekel", 0)
	var stock: int = _stock.get(item_id, 0)
	if owned < 0 or wallet < 0 or stock < 0 or _budget < 0:
		return _failure("Invalid trade balance.")
	if buying:
		if stock < quantity:
			return _failure("Not enough merchant stock.")
		if wallet < total:
			return _failure("Not enough Shekel.")
		if owned > MAX_INT - quantity or _budget > MAX_INT - total:
			return _failure("Trade would exceed the balance limit.")
	else:
		if quantity > _demand.get(item_id, 0):
			return _failure("Merchant request limit reached.")
		if owned < quantity:
			return _failure("Not enough items in your inventory.")
		if _budget < total:
			return _failure("The merchant does not have enough Shekel.")
		if stock > MAX_INT - quantity or wallet > MAX_INT - total:
			return _failure("Trade would exceed the balance limit.")
	# Check the final inventory using item data; Shekel has zero weight.
	var item_weight: float = Inventory.get_item_total_weight(item_id, quantity)
	var money_weight: float = Inventory.get_item_total_weight("shekel", total)
	var delta: float = item_weight - money_weight if buying else money_weight - item_weight
	var final_weight: float = Inventory.get_total_inventory_weight() + delta
	if not is_finite(final_weight) or final_weight > Inventory.max_load + 0.00001:
		return _failure("Not enough inventory capacity for this trade.")
	return {"ok": true, "message": "", "total": total}

func trade(item_id: String, quantity: int, buying: bool) -> Dictionary:
	var result: Dictionary = quote(item_id, quantity, buying)
	if not result.ok:
		return result
	_trading = true
	var total: int = result.total
	var direction: int = 1 if buying else -1
	# Preflight above; publish only after BOTH inventories and budgets are committed.
	# Separate remove/add calls emit intermediate balances and allow reentrant trades.
	_set_inventory_stack(item_id, Inventory.items.get(item_id, 0) + direction * quantity)
	_set_inventory_stack("shekel", Inventory.items.get("shekel", 0) - direction * total)
	_stock[item_id] -= direction * quantity
	_budget += direction * total
	if not buying:
		_demand[item_id] -= quantity
	Inventory.items_changed.emit()
	_trading = false
	changed.emit()
	return {"ok": true, "message": "%s %d %s for %d Shekel." % ["Bought" if buying else "Sold", quantity, ItemDatabase.get_item_data(item_id).display_name, total], "total": total}

func _set_inventory_stack(id: String, quantity: int) -> void:
	if quantity == 0:
		Inventory.items.erase(id)
	else:
		Inventory.items[id] = quantity

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "total": 0}
