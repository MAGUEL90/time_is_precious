extends Node

@export var seconds_per_minute: float = 0.1 # 1 detik real = 1 menit game
@export var start_hour: int = 17
@export var start_day: int = 1

var current_minute: float
var current_hour: int 
var current_day: int
var current_weather: String = "clear" 

@export var weather_chance_storm: float = 0.05
@export var weather_chance_rainy: float = 0.2

var minute_per_hour: int = 60
var hour_per_day: int = 24
var is_paused: bool = false
var morning_hour: int = 5
var afternoon_hour: int = 10
var night_hour: int = 17

signal time_changed(day: int, hour: int, minute: int)
signal minute_changed(minute: int)
signal day_changed(day: int)
signal hour_changed(hour: int)
signal new_day_started(day)
signal weather_changed(weather: String)
signal morning_shift
signal afternoon_shift
signal night_shift

@onready var environment: CanvasModulate = $Environment

var _timer: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_hour = start_hour
	current_day = start_day
	emit_time_signal()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	if is_paused: return
	
	_timer += delta
	if _timer >= seconds_per_minute:
		_timer -= seconds_per_minute
		
		advance_one_minute()
		day_cycle()
		# print("day: ", current_day, " minute: ", current_minute, " hour: ", current_hour)
	
func emit_time_signal() -> void:
	emit_signal("minute_changed", minute_per_hour)
	emit_signal("hour_changed", hour_per_day)
	emit_signal("day_changed", current_day)
	#emit_signal("season_changed", season)
	#emit_signal("weather_changed", current_weather)
	#emit_signal("time_scale_changed", time_scale)

func advance_one_minute() -> void:
	current_minute += 1
	if current_minute >= minute_per_hour:
		current_minute = 0
		current_hour += 1
		if current_hour >= hour_per_day:
			current_hour = 0
			current_day += 1
			emit_signal("new_day_started", current_day)
			emit_signal("day_changed", current_day)
			print(current_weather)
			on_new_day()
		emit_signal("hour_changed", current_hour)
		
	emit_signal("time_changed", current_minute, current_hour, current_day)

func on_new_day() -> void:
	roll_daily_weather()
	emit_signal("day_changed", current_day)

func day_cycle() -> void:
	var darkness: float = 0.0
	if current_hour >= morning_hour and current_hour <= 7:
		darkness = 1.0 - (current_hour - morning_hour + current_minute / 60.0) / 3.0
		emit_signal("morning_shift")
	elif current_hour >= night_hour and current_hour < 19:
		darkness = (current_hour - night_hour + current_minute / 60.0) / 2.0
		emit_signal("afternoon_shift")
	elif current_hour >= 19 or current_hour < morning_hour:
		darkness = 1.0
		emit_signal("night_shift")
	else:
		darkness = 0.0
		
	
	var night_tint: Color = Color(0.15, 0.15, 0.3)
	var day_tint: Color = Color(1.0, 1.0, 1.0)
	var base_color: Color = day_tint.lerp(night_tint, darkness)
	
	if environment:
		environment.color = base_color

func roll_daily_weather() -> void:
	var roll: float = randf()
	if roll < weather_chance_storm:
		current_weather = "storm"
	elif roll < weather_chance_storm + weather_chance_rainy:
		current_weather = "rainy"
	elif roll < 0.6:
		current_weather = "cloudy"
	else:
		current_weather = "clear"
	
	emit_signal("weather_changed", current_weather)

func toggle_pause() -> void:
	is_paused = !is_paused
