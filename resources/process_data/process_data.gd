class_name ProcessData extends Resource

@export var process_id: String = ""
@export var display_name: String = ""
@export var short_name: String = ""
@export var icon: Texture2D
@export var input_item_id: String = ""
@export var output_item_id: String = ""
@export var required_station_id: String = "" # mis. “drying_yard”
@export var base_duration_minutes: int = 0
@export var weather_speed_multiplier: Dictionary[String, float] = {}
@export var failure_chance_by_weather: Dictionary[String, float] = {}
@export var station_fee_currency_item_id: String = "shekel"
@export_range(1, 999, 1) var batch_size: int = 20
@export var requires_full_batch: bool = false
@export_range(0, 999, 1) var station_fee_per_batch: int = 0
