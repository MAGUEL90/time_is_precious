class_name ProcessData extends Resource

var process_id: String = ""
var display_name: String = ""
var input_item_id: String = ""
var output_item_id: String = ""
var required_station_id: String = "" # mis. “drying_yard”

@export var base_duration_minutes: int = 0
@export var weather_speed_multiplier: Dictionary[String, float] = {}
@export var failure_chance_by_weather: Dictionary[String, float] = {}

# INI HINT, BARIS KE BERAPA AKU ?
