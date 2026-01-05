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

func _ready() -> void:
	set_data_attribute()
	_sync_shift_from_hour()
	
	interactable_label_component.hide()
	
	player_reff = get_tree().get_first_node_in_group("player")

	walk_cycle_duration.wait_time = randf_range(2.0, 3.5)
	walk_cycle_duration.start()
	
	TimeComponentManager.morning_shift.connect(on_morning_shift) # shift harus jalan walau player belum ada
	TimeComponentManager.afternoon_shift.connect(on_afternoon_shift) # shift harus jalan walau player belum ada
	TimeComponentManager.noon_shift.connect(on_noon_shift) # noon dianggap bagian “afternoon” supaya state tetap update
	TimeComponentManager.night_shift.connect(on_night_shift) # shift harus jalan walau player belum ada

	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))  # "self" = NPC ini sendiri)
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))

# INI HINT, BARIS KE BERAPA AKU?
func _recalc_contract_state() -> void:
	
	var is_night: bool = (current_shift == Shift.NIGHT)

	npc_allow_contract = (not is_night and \
	npc_current_satisfaction > 0.1 and \
	TimeComponentManager.current_weather in ["clear", "cloudy"])
	
	if OS.is_debug_build(): # batasi spam log hanya saat debug build
		print("is_night: ", is_night) # info debug
		print("npc_allow_contract: ", npc_allow_contract) # info debug


func start_dialogue () -> void:
	
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
	
	if not npc_state: # kalau state belum di-assign dari inspector
		npc_state = npc_state.new() # buat state runtime baru supaya NPC tetap bisa jalan
	
	# pastikan state punya npc_id yang cocok untuk save/load
	var state_id: String = npc_state.npc_id # aman walau field npc_id belum ada
	if state_id == "" and npc_data.id != "": # kalau belum ada id, set dari NPCData
		npc_state.set("npc_id", npc_data.id) # mapping state -> NPCData (kunci save/load)
	
	# ===== ambil identitas dari NPCData (template) =====
	npc_name = npc_data.npc_name # nama tampil NPC dari template
	npc_unique_dialogue = npc_data.unique_dialogue # dialog unik dari template
	npc_initial_satisfaction = npc_data.initial_satisfaction # nilai awal dari template (dipakai untuk init state baru)
	
	# ===== init satisfaction state kalau belum ada / belum pernah diisi =====
	var state_satisfaction: float = npc_state.current_satisfaction # aman walau belum @export / belum ada field
	if state_satisfaction == null: # jika belum pernah di-set sama sekali
		npc_state.set("current_satisfaction", npc_initial_satisfaction) # isi state pertama kali pakai nilai initial
	
	# clamp satisfaction supaya selalu dalam batas NPCData
	var satisfaction_value: float = float(npc_state.current_satisfaction) # baca satisfaction dari state
	if npc_data.has_method("clamp_satisfaction"): # jika kamu sudah pakai helper clamp_satisfaction di NPCData
		satisfaction_value = npc_data.clamp_satisfaction(satisfaction_value) # jaga agar tidak keluar limit
	else:
		satisfaction_value = clamp(satisfaction_value, npc_data.min_limit_satisfaction, npc_data.max_limit_satisfaction)
	npc_state.set("current_satisfaction", satisfaction_value) # simpan balik ke state agar konsisten
	npc_current_satisfaction = satisfaction_value # pakai untuk logic runtime (allow_contract, dll)
	
	# ===== posisi: ambil dari state, fallback ke posisi node saat ini =====
	var current_position: Vector2 = npc_state.current_position # aman walau field belum ada
	if current_position == null: # jika state belum punya posisi valid
		current_position = global_position # fallback: ambil posisi node di scene
		npc_state.set("current_position", current_position) # simpan posisi awal ke state
	
	var last_position: Vector2 = npc_state.last_position # aman walau field belum ada
	if last_position == null or not (last_position is Vector2): # jika state belum punya last_position valid
		last_position = current_position # set sama dengan current sebagai default awal
		npc_state.set("last_position", last_position) # simpan default ke state
	
	npc_current_position = current_position # cache runtime
	npc_last_position = last_position # cache runtime
	global_position = npc_current_position # tempatkan NPC sesuai state (penting untuk konsistensi load)

func debug_npc() -> String:
	var trust_value = npc_state.trust # tampilkan trust kalau sudah ada di state (fallback 0)
	debug_npc_label.text = "name: %s \n;
	allow_contract: %s \n;
	satisfaction: %.2f \n;
	trust: %.2f" % [
	npc_name, 
	npc_allow_contract, 
	npc_current_satisfaction, 
	float(trust_value)] 
	return debug_npc_label.text

func proceed_contract() -> void:
	is_contract_activated = true
