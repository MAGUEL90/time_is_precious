class_name NPCBase extends CharacterBody2D

const GAME_dialogue_BALLOON = preload("uid://73jm5qjy52vq")

@export var npc_data: NPCData

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var walk_cycle_duration: Timer = $WalkCycleDuration
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D
@onready var debug_npc_label: Label = $DebugNPCLabel



var on_dialogue : bool = false
var can_walk: bool = false
var player_reff: Player

# ============= ATTRIBUTES
var npc_name: String
var npc_class: String
var npc_unique_dialogue : DialogueResource
var npc_container: Dictionary = {}

# ============= NPCPosition
var npc_current_position: Vector2
var npc_last_position: Vector2

# ============= PARAM
var npc_initial_satisfaction: float
var npc_current_satisfaction: float

# ============= CONTRACT
var npc_allow_contract: bool = false
var is_contract_activated: bool = false

var is_clear_day: bool = false

# ============= SHIFT
enum Shift { MORNING, AFTERNOON, NOON, NIGHT}
var current_shift: Shift = Shift.MORNING

func _ready() -> void:
	set_data_attribute()
	_sync_shift_from_hour()
	
	TimeComponentManager.morning_shift.connect(on_morning_shift)
	TimeComponentManager.afternoon_shift.connect(on_afternoon_shift)
	TimeComponentManager.noon_shift.connect(on_noon_shift)
	TimeComponentManager.night_shift.connect(on_night_shift)
	
	interactable_label_component.hide()
	player_reff = get_tree().get_first_node_in_group("player")
	
	walk_cycle_duration.wait_time = randf_range(2.0, 3.5)
	walk_cycle_duration.start()
	
	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))  # "self" = NPC ini sendiri)
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))


func _recalc_contract_state() -> void:
	
	var is_night: bool = false
	
	if current_shift == Shift.NIGHT:
		is_night = true
	
	npc_allow_contract = (not is_night and \
	npc_current_satisfaction > 0.1 and \
	TimeComponentManager.current_weather == "clear")
	print("is_night: ", is_night)
	print("npc_allow_contract: ", npc_allow_contract)


	
func start_dialogue () -> void:
	
	if not npc_unique_dialogue :
		return
		
	var balloon: BaseGameDialogueBalloon = GAME_dialogue_BALLOON.instantiate()
	get_tree().current_scene.add_child(balloon)
	
	var title_list: Array = npc_unique_dialogue .get_titles()
	var contract_founded: bool = false
	var npc_state: Array = [self]
	
	for title in title_list:
		if title.begins_with("contract") and npc_allow_contract:
			var contract_title = title
			if npc_unique_dialogue .titles.has(contract_title):
				balloon.start(npc_unique_dialogue , contract_title, npc_state)
				contract_founded = true
				break
	
	if not contract_founded:
		var casual_title: String = "casual_%s" % npc_name.to_lower() + "_1"
		if title_list.has(casual_title):
			balloon.start(npc_unique_dialogue , casual_title, npc_state)
		elif title_list.size() > 0:
			balloon.start(npc_unique_dialogue , title_list[0], npc_state)
			

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
	if npc_data:
		npc_name = npc_data.name
		npc_last_position = npc_data.last_position
		npc_current_position = npc_data.current_position
		npc_unique_dialogue  = npc_data.unique_dialogue 
		npc_current_satisfaction = npc_data.current_satisfaction

func debug_npc() -> String:
	debug_npc_label.text = "name: %s; allow_contract: %s" % [npc_name, npc_allow_contract] 
	return debug_npc_label.text

func proceed_contract() -> void:
	is_contract_activated = true
