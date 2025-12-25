extends Node

@export var seconds_per_minute: float = 0.05 # 1 detik real = 1 menit game
@export var start_hour: int = 4
@export var start_day: int = 1

var current_minute: int
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
var noon_hour: int = 17
var night_hour: int = 19

signal time_changed(day: int, hour: int, minute: int, weather: String)
signal minute_changed(minute: int)
signal day_changed(day: int)
signal hour_changed(hour: int)
signal new_day_started(day)
signal weather_changed(weather: String)
signal morning_shift
signal afternoon_shift
signal noon_shift
signal night_shift

@onready var environment: CanvasModulate = $Environment

var _timer: float = 0.0
var _last_shift: String = "" # menyimpan shift terakhir supaya signal shift tidak terpanggil setiap menit

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_hour = start_hour
	current_day = start_day
	current_minute = 0
	roll_daily_weather()
	emit_time_signal()
	day_cycle()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:

	if is_paused: return
	
	_timer += delta
	if _timer >= seconds_per_minute:
		_timer -= seconds_per_minute
		
		advance_one_minute()
		day_cycle()

func emit_time_signal() -> void:
	emit_signal("minute_changed", current_minute)
	emit_signal("hour_changed", current_hour)
	emit_signal("day_changed", current_day)
	
	emit_signal("weather_changed", current_weather)
	emit_signal("time_changed", current_day, current_hour, current_minute, current_weather) # sinkron sekali saat awal
	
	#emit_signal("season_changed", season)

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
			on_new_day()
		emit_signal("hour_changed", current_hour)
		
	emit_signal("time_changed", current_day, current_hour, current_minute, current_weather)

func on_new_day() -> void:
	roll_daily_weather()
	emit_signal("day_changed", current_day)

func day_cycle(force_emit: bool = false) -> void: # force_emit dipakai untuk emit shift pertama kali di _ready()
	var darkness: float = 0.0
	var new_shift: String = "morning" # shift baru yang dihitung dari jam sekarang
	if current_hour >= morning_hour and current_hour < afternoon_hour:
		darkness = 1.0 - (current_hour - morning_hour + current_minute / 60.0) / 5
		new_shift = "morning"
	elif current_hour >= afternoon_hour and current_hour < noon_hour:
		new_shift = "afternoon"
	elif current_hour >= noon_hour and current_hour < night_hour:
		darkness = (current_hour - noon_hour + current_minute / 60.0) / 2
		new_shift = "noon"
	elif current_hour >= night_hour or current_hour < morning_hour:
		darkness = 1.0
		new_shift = "night"
	else:
		darkness = 0.0
	
	var night_tint: Color = Color(0.15, 0.15, 0.3)
	var day_tint: Color = Color(1.0, 1.0, 1.0)
	var base_color: Color = day_tint.lerp(night_tint, darkness)
	
	if environment:
		environment.color = base_color

	if force_emit or new_shift != _last_shift: # emit hanya kalau shift berubah (hemat performa)
		_last_shift = new_shift # simpan shift terakhir
		match new_shift:
			"morning": emit_signal("morning_shift") # signal shift pagi
			"afternoon": emit_signal("afternoon_shift") # signal shift siang
			"noon": emit_signal("noon_shift") # signal shift sore
			"night": emit_signal("night_shift") # signal shift malam
		

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
