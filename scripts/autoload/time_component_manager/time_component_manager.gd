extends Node

@export var seconds_per_minute: float = 0.1 # 1 detik real = 1 menit game
@export var start_hour: int = 7
@export var start_day: int 
@export var tint_transition_minutes: float = 30.0 # durasi transisi tint (menit) agar tidak patah di batas jam
@export var env_transition_speed: float = 12.0 # kecepatan transisi warna environment (lebih besar = lebih cepat)

var current_minute: int = 0
var current_hour: int = 0
var current_day: int = 0
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
var _target_environment_color: Color = Color(1.0, 1.0 ,1.0)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_hour = start_hour
	current_day = start_day
	roll_daily_weather() # set cuaca awal untuk debugging/awal game
	emit_time_signal() # broadcast state awal (UI/NPC bisa langsung sync)
	day_cycle(true) # hitung warna awal + paksa emit shift pertama kali
	
	if environment:
		environment.color = _target_environment_color # set sekali saat start supaya tidak flash dari warna default

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	if is_paused: return
	
	# transisi warna dibuat halus per-frame (FPS berapa pun tetap smooth)
	if environment:
		var alpha: float = 1.0 - exp(-env_transition_speed * delta) # smoothing stabil berbasis delta
		environment.color = environment.color.lerp(_target_environment_color, alpha)
	
	_timer += delta
	if _timer >= seconds_per_minute:
		_timer -= seconds_per_minute
		
		advance_one_minute()
		day_cycle()

func emit_time_signal() -> void:
	emit_signal("minute_changed", current_minute) # kirim menit saat ini (bukan 60)
	emit_signal("hour_changed", current_hour) # kirim jam saat ini (bukan 24)
	emit_signal("day_changed", current_day) # kirim hari saat ini
	emit_signal("time_changed", current_day, current_hour, current_minute, current_weather) # sinkron sekali saat awal


func advance_one_minute() -> void:
	current_minute += 1
	if current_minute >= minute_per_hour:
		current_minute = 0
		current_hour += 1
		if current_hour >= hour_per_day:
			current_hour = 0
			current_day += 1
			emit_signal("new_day_started", current_day) # hari baru dimulai
			emit_signal("day_changed", current_day) # kabari UI/sistem lain soal hari baru
			on_new_day()
		emit_signal("hour_changed", current_hour) # kabari saat jam berubah
	emit_signal("minute_changed", current_minute) # signal menit berubah setiap menit
	emit_signal("time_changed", current_day, current_hour, current_minute, current_weather) # broadcast waktu terbaru

func on_new_day() -> void:
	roll_daily_weather()
	emit_signal("day_changed", current_day) # konfirmasi hari

func day_cycle(force_emit: bool = false) -> void: # force_emit dipakai untuk emit shift pertama kali di _ready()
	var darkness: float = 0.0
	var new_shift: String = "morning" # shift baru yang dihitung dari jam sekarang
	
	# waktu dalam jam desimal (contoh 18.5 = 18:30)
	var total_hours: float = float(current_hour) + float((current_minute) / 60.0) # untuk perhitungan transisi halus
	var transition_hour: float = tint_transition_minutes / 60.0 # durasi transisi dalam jam
	
	if current_hour >= morning_hour and current_hour < afternoon_hour:
		darkness = 1.0 - (current_hour - morning_hour + current_minute / 60.0) / 5
		new_shift = "morning"
	elif current_hour >= afternoon_hour and current_hour < noon_hour:
		darkness = 0.0 # siang: tidak ada gelap dari time-of-day
		new_shift = "afternoon"
	elif current_hour >= noon_hour and current_hour < night_hour:
		# _debug_lerp_clamp()
		var noon_duration: float = float(night_hour - noon_hour) # durasi segmen noon sampai night (jam)
		if noon_duration <= 0.0: # pengaman kalau setting jam tidak valid
			noon_duration = 1.0
		var hours_since_noon: float = total_hours - float(noon_hour) # jam berlalu sejak noon
		darkness = clamp(hours_since_noon / noon_duration, 0.0, 1.0) # naik halus 0..1
		new_shift = "noon"
	elif current_hour >= night_hour or current_hour < morning_hour:
		darkness = 1.0
		new_shift = "night"
	else:
		darkness = 0.0
	
	var night_tint: Color = Color(0.15, 0.15, 0.3)
	var day_tint: Color = Color(1.0, 1.0, 1.0)
	var base_color: Color = day_tint.lerp(night_tint, darkness) # dasar warna dari siang->malam
	
	# ===== Warm tint dibuat smooth berdasarkan waktu (menghilangkan snap di 17:00 & 19:00) =====
	var afternoon_tint: Color = Color(1.0, 0.96, 0.88)
	var noon_tint: Color = Color(1.0, 0.86, 0.74)
	
	var k_to_noon: float = _smoothstep(float(noon_hour) - transition_hour, float(noon_hour) + transition_hour, total_hours) # 0->1 sekitar jam 17
	var k_to_night: float = _smoothstep(float(night_hour) - transition_hour, float(night_hour), total_hours) # 0->1 mendekati jam 19
	
	var warm_tint: Color = afternoon_tint.lerp(noon_tint, k_to_noon) # transisi warna hangat afternoon -> noon
	var warm_strength: float = lerp(0.18, 0.25, k_to_noon) # kekuatan warm mengikuti transisi)
	warm_strength *= (1.0 - k_to_night) # fade-out warm menuju night supaya tidak snap di 19:00
	
	# warm hanya aktif di rentang siang-sore (di luar itu, dimatikan)
	if total_hours < float(afternoon_hour) or total_hours >= float(night_hour):  # batasi warm hanya saat siang-sore 
		warm_strength = 0.0 # matikan warm di pagi & malam
	
	# cuaca buruk mengurangi efek hangat supaya tidak “aneh” saat storm/rainy
	if current_weather == "storm":
		warm_strength *= 0.10 # badai: hampir tidak ada hangat
	elif current_weather == "rainy": 
		warm_strength *= 0.35 # hujan: hangat berkurang banyak
	elif current_weather == "cloudy":
		warm_strength *= 0.60 # mendung: hangat agak berkurang
	
	base_color = base_color.lerp(warm_tint, warm_strength) # apply warm tint yang sudah smooth
	
	if new_shift == "afternoon":
		base_color = base_color.lerp(afternoon_tint, warm_strength) # apply hangat setelah disesuaikan cuaca
	elif new_shift == "noon":
		base_color = base_color.lerp(noon_tint, warm_strength) # apply hangat setelah disesuaikan cuaca
	
	# ===== Weather tint (mood keseluruhan) =====
	var weather_tint: Color = Color(1.0, 1.0, 1.0) # default: clear (tidak mengubah)
	var weather_strength: float = 0.0 # seberapa kuat weather tint
	var weather_dim: float = 1.0 # pengali brightness (1.0 = tidak dim)
	
	match current_weather:
		"storm":
			weather_tint = Color(0.65, 0.70, 0.85) # dingin kebiruan-abu
			weather_strength = 0.55 # cukup kuat
			weather_dim = 0.72 # lebih gelap
		"rainy":
			weather_tint = Color(0.78, 0.82, 0.92) # dingin tipis
			weather_strength = 0.30 # sedang
			weather_dim = 0.85 # sedikit gelap
		"cloudy":
			weather_tint = Color(0.90, 0.92, 0.98) # netral-agak dingin
			weather_strength = 0.18 # ringan
			weather_dim = 0.93 # sedikit dim
		"storm":
			weather_strength = 0.0
			weather_dim = 1.0
	
	base_color = base_color.lerp(weather_tint, weather_strength) # geser warna sesuai cuaca
	base_color *= Color(weather_dim, weather_dim, weather_dim, 1.0) # redupkan brightness sesuai cuaca
	
	_target_environment_color = base_color # simpan warna target; yang apply halus ada di _process()
	
	# emit shift hanya saat berubah (hemat performa + mencegah spam)
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
	
	emit_signal("weather_changed", current_weather) # kabari sistem lain kalau cuaca berubah

func toggle_pause() -> void:
	is_paused = !is_paused

func _smoothstep(edge0: float, edge1: float, x: float) -> float: # transisi halus 0..1 tanpa patah
	if edge0 == edge1: # jika batas sama, tidak ada rentang transisi
		return 0.0 # pengaman agar tidak bagi nol
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0) # normalisasi ke 0..1
	return t * t * (3.0 - 2.0 * t) # kurva smoothstep klasik

func _debug_lerp_clamp():
	var day_r := 1.0
	var night_r := 0.15
	var noon_duration := night_hour - noon_hour # 2 jam
	
	var samples := [
		Vector2(16, 50),
		Vector2(17, 0),
		Vector2(17, 30),
		Vector2(18, 0),
		Vector2(18, 30),
		Vector2(19, 0),
		Vector2(19, 10),
	]
	
	for s in samples:
		var h = s.x
		var m = s.y
		var time := float(h) + float(m)/60.0
		var t = (time - noon_hour) / noon_duration
		var t_clamped = clamp(t, 0.0, 1.0)
		var r = lerp(day_r, night_r, t_clamped)
		print("%02d:%02d  time=%.4f  t=%.4f  tC=%.4f  R=%.4f" % [int(h), int(m), time, t, t_clamped, r])
