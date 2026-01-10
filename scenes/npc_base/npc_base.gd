class_name NPCBase extends CharacterBody2D

const GAME_dialogue_BALLOON = preload("uid://73jm5qjy52vq")

@export var npc_data: NPCData
@export var npc_state: NPCState

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var walk_cycle_duration: Timer = $WalkCycleDuration
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D
@onready var debug_npc_label: Label = $DebugNPCLabel

var on_dialogue : bool = false
var can_walk: bool = false
var player_reff: Player

# ============= IDENTITY =============
var npc_name: String
var npc_role: String
var npc_id: String
var npc_unique_dialogue : DialogueResource

# ============= Position =============
var npc_current_position: Vector2
var npc_last_position: Vector2

# ============= SATISFACTION =============
var npc_initial_satisfaction: float
var npc_current_satisfaction: float

# ============= WORK & CONTRACT =============
var npc_allow_contract: bool = false
var is_contract_activated: bool = false

var is_clear_day: bool = false

# ============= SHIFT
enum Shift { MORNING, AFTERNOON, NOON, NIGHT}
var current_shift: Shift = Shift.MORNING

@export var state_pos_sync_threshold: float = 0.5 # jarak minimal (pixel/unit) sebelum posisi disimpan ke state (biar tidak update terus tiap frame)
@export_range(0.0, 1.0, 0.01) var daily_satisfaction_decay: float = 0.0 # (opsional) test decay per hari; default 0 agar tidak mengubah gameplay

func _ready() -> void:
	set_data_attribute()
	_sync_shift_from_hour()
	_sync_state_position(true) # pastikan state langsung sinkron dengan posisi awal saat spawn/load
	
	interactable_label_component.hide()
	
	player_reff = get_tree().get_first_node_in_group("player") as Player

	walk_cycle_duration.wait_time = randf_range(2.0, 3.5)
	walk_cycle_duration.start()
	
	TimeComponentManager.morning_shift.connect(on_morning_shift) # shift harus jalan walau player belum ada
	TimeComponentManager.afternoon_shift.connect(on_afternoon_shift) # shift harus jalan walau player belum ada
	TimeComponentManager.noon_shift.connect(on_noon_shift) # noon dianggap bagian “afternoon” supaya state tetap update
	TimeComponentManager.night_shift.connect(on_night_shift) # shift harus jalan walau player belum ada
	TimeComponentManager.new_day_started.connect(on_new_day_started) # daily tick: update NPC sekali per hari
	_recalc_contract_state()
	
	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))  # "self" = NPC ini sendiri)
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))

func _physics_process(_delta: float) -> void:
	debug_npc()
	_sync_state_position(false) # setiap frame fisika, cek apakah NPC pindah; kalau iya, simpan ke npc_state

func _recalc_contract_state() -> void:
	
	var is_night: bool = (current_shift == Shift.NIGHT)

	npc_allow_contract = (not is_night and \
	npc_current_satisfaction > 0.1 and \
	TimeComponentManager.current_weather in ["clear", "cloudy"])
	
	if OS.is_debug_build(): # batasi spam log hanya saat debug build
		print("is_night: ", is_night) # info debug
		print("npc_allow_contract: ", npc_allow_contract) # info debug

func _sync_state_position(force: bool):
	if not npc_state:
		return
	
	# force dipakai untuk kasus spawn/load/teleport (langsung sinkron tanpa threshold)
	if force:
		npc_state.last_position = npc_state.current_position # simpan posisi sebelumnya (kalau ada)
		npc_state.current_position = global_position # posisi sekarang dari noded
		npc_last_position = npc_state.last_position # cache untuk logic NPCBase
		npc_current_position = npc_state.current_position # cache untuk logic NPCBase
		return
	
	# normal mode: hanya update kalau benar-benar pindah cukup jauh
	if global_position.distance_to(npc_state.current_position) >= state_pos_sync_threshold:
		npc_state.last_position = npc_state.current_position # geser current -> last
		npc_state.current_position = global_position # simpan posisi terbaru
		npc_last_position = npc_state.last_position # cache untuk logic NPCBase
		npc_current_position = npc_state.current_position # cache untuk logic NPCBase

func start_dialogue() -> void:
	
	if not npc_unique_dialogue :
		return
		
	var balloon: BaseGameDialogueBalloon = GAME_dialogue_BALLOON.instantiate()
	get_tree().current_scene.add_child(balloon)
	
	var title_list: Array = npc_unique_dialogue .get_titles()
	var contract_founded: bool = false
	var npc_states: Array = [self]
	
	for title in title_list:
		if title.begins_with("contract") and npc_allow_contract:
			var contract_title = title
			if npc_unique_dialogue .titles.has(contract_title):
				balloon.start(npc_unique_dialogue , contract_title, npc_states)
				contract_founded = true
				break
	
	if not contract_founded:
		var casual_title: String = "casual_%s" % npc_name.to_lower() + "_1"
		if title_list.has(casual_title):
			balloon.start(npc_unique_dialogue , casual_title, npc_states)
		elif title_list.size() > 0:
			balloon.start(npc_unique_dialogue , title_list[0], npc_states)

func _on_walk_cycle_duration_timeout() -> void:
	can_walk = true

func on_morning_shift() -> void:
	current_shift = Shift.MORNING
	call_deferred("_recalc_contract_state")
	
func on_afternoon_shift() -> void:
	current_shift = Shift.AFTERNOON
	call_deferred("_recalc_contract_state")

func on_noon_shift() -> void:
	current_shift = Shift.NOON
	call_deferred("_recalc_contract_state")

func on_night_shift() -> void:
	current_shift = Shift.NIGHT
	call_deferred("_recalc_contract_state")

func on_new_day_started(day: int) -> void: # memastikan daily update hanya sekali per hari
	print("[NPC]", npc_name, "new_day_started: ", day)
	if not npc_state or not npc_data: #safety
		return
	
	if npc_state.last_updated_day == day: # sudah di-update untuk hari ini
		return
	
	npc_state.last_updated_day = day # tandai agar tidak double
	daily_update(day) # isi logic harian di sini

func daily_update(day: int) -> void: # placeholder: nanti isi needs/contract progression, dll
	print("[NPC]: ", npc_name, ", daily_update_day: ", day, ", satisfaction_before: ", npc_state.current_satisfaction)

	if daily_satisfaction_decay > 0.0: # kalau mau test decay, set angka di inspector (mis. 0.02)
		npc_state.current_satisfaction = npc_data.clamp_satisfaction(npc_state.current_satisfaction - daily_satisfaction_decay)
		npc_current_satisfaction = npc_state.current_satisfaction # sync cache untuk logic NPCBase
		call_deferred("_recalc_contract_state") # kontrak bisa berubah karena satisfaction berubah
	
	print("[NPC]: ", npc_name, ", satisfaction_after: ", npc_state.current_satisfaction)


func _sync_shift_from_hour() -> void:
	var hour: int = TimeComponentManager.current_hour
	if hour >= TimeComponentManager.morning_hour and hour < TimeComponentManager.afternoon_hour:
		current_shift = Shift.MORNING
	elif hour >= TimeComponentManager.afternoon_hour and hour < TimeComponentManager.noon_hour:
		current_shift = Shift.AFTERNOON
	elif hour >= TimeComponentManager.noon_hour and hour < TimeComponentManager.night_hour:
		current_shift = Shift.NOON
	elif hour >= TimeComponentManager.night_hour or hour < TimeComponentManager.morning_hour: 
		current_shift = Shift.NIGHT

func set_data_attribute() -> void:
	if not npc_data: # NPCData wajib ada sebagai template
		return # tanpa NPCData, NPC tidak punya identitas/template
	
	var state_was_created: bool = false # penanda: state baru dibuat di runtime (supaya kita tidak overwrite progress save)
	if not npc_state: # kalau state belum di-assign dari inspector
		npc_state = NPCState.new() # buat state runtime baru supaya NPC tetap bisa jalan
		state_was_created = true # tandai bahwa ini state baru
	
	# pastikan state punya npc_id yang cocok untuk save/load
	if npc_state.npc_id == "" and npc_data.id != "": # kalau belum ada id, set dari NPCData
		npc_state.npc_id = npc_data.id # mapping state -> NPCData (kunci save/load)
	
	# ===== ambil identitas dari NPCData (template) =====
	npc_name = npc_data.npc_name # nama tampil NPC dari template
	npc_role = npc_data.role # role dari template (supaya siap dipakai di UI/logic)
	npc_id = npc_data.id # id dari template (berguna buat debug dan mapping)
	npc_unique_dialogue = npc_data.unique_dialogue # dialog unik dari template
	npc_initial_satisfaction = npc_data.initial_satisfaction # nilai awal dari template (dipakai untuk init state baru)

	# ===== init satisfaction hanya jika state baru dibuat (jangan overwrite state hasil load) =====
	if state_was_created: # hanya set nilai awal jika state baru
		npc_state.current_satisfaction = npc_initial_satisfaction # isi state pertama kali pakai nilai initial
		npc_state.last_updated_day = TimeComponentManager.current_day # tandai hari terakhir update (supaya logic daily jelas sejak awal)

	# clamp satisfaction supaya selalu dalam batas NPCData
	var satisfaction_value: float = npc_data.clamp_satisfaction(npc_state.current_satisfaction) # clamp selalu lewat helper NPCData
	npc_state.current_satisfaction = satisfaction_value # simpan balik ke state agar konsisten
	npc_current_satisfaction = satisfaction_value # pakai untuk logic runtime (allow_contract, dll)
	
	# ===== posisi: ambil dari state, fallback ke posisi node saat ini =====
	if state_was_created: # posisi hanya di-init jika state baru (jangan override posisi hasil load)
		npc_state.current_position = global_position # set posisi awal sesuai scene
		npc_state.last_position = global_position # set last_position awal sama dengan current
	
	npc_current_position = npc_state.current_position # cache runtime
	npc_last_position = npc_state.last_position # cache runtime
	global_position = npc_current_position # tempatkan NPC sesuai state (penting untuk konsistensi load)

func debug_npc() -> String:
	var trust_value: float = npc_state.trust # tampilkan trust kalau sudah ada di state (fallback 0)
	debug_npc_label.text = "name: %s\nallow_contract: %s\nsatisfaction: %.2f\ntrust: %.2f" % [
	npc_name, 
	npc_allow_contract, 
	npc_current_satisfaction, 
	trust_value
	]
	return debug_npc_label.text

func proceed_contract() -> void:
	is_contract_activated = true
