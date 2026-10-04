extends Resource

## Playtest configuration; city-statistics-driven visitors are a later feature.
@export var first_day: int = 1
@export var interval_days: int = 3
@export_range(0, 23) var arrival_hour: int = 8
@export_range(1, 24) var departure_hour: int = 18
@export var starting_shekel: int = 120
## Goods offered to the player: item_id, stock, buy_price.
@export var offers: Array[Dictionary] = []

## Goods requested from the player: item_id, quantity, sell_price.
@export var requests: Array[Dictionary] = []

## Randomize only on actual arrival; quantities use quantity_min..quantity.
@export var randomize_requests: bool = false
@export_range(1, 100) var request_count_min: int = 1
@export_range(1, 100) var request_count_max: int = 2
