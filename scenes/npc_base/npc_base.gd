class_name NPCBase extends CharacterBody2D

const GAME_DIALOUGE_BALLOON = preload("uid://73jm5qjy52vq")

@export var npc_data: NPCData

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var walk_cycle_duration: Timer = $WalkCycleDuration
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D
@onready var time_component_manager = TimeComponentManager
@onready var debug_npc_label: Label = $DebugNPCLabel

var on_dialouge: bool = false
var can_walk: bool = false
var player_reff: Player

# ============= ATTRIBUTES
var npc_name: String
var npc_class: String
var npc_unique_dialouge: DialogueResource
var npc_container: Dictionary = {
	
}

# ============= NPCPosition
var npc_current_position: Vector2
var npc_last_position: Vector2

# ============= PARAM
var npc_initial_satisfaction: float
var npc_current_satisfaction: float

# ============= CONTRACT
var npc_allow_contract: bool

var is_morning_shift: bool = false
var is_afternoon_shift: bool = false
var is_night_shift: bool = false
var is_clear_day: bool = false



func _ready() -> void:
	for npc in get_parent().get_children():
		if npc is NPCBase and not npc_container.has("name"):
			npc_container["name"] = [str(npc.name)]
		elif npc is NPCBase and npc_container.has("name"):
			npc_container["name"].append(str(npc.name))
	
	call_deferred("set_data_attribute")
	
	interactable_label_component.hide()
	player_reff = get_tree().get_first_node_in_group("player")
	
	walk_cycle_duration.wait_time = randf_range(2.0, 3.5)
	walk_cycle_duration.start()
	
	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))  # "self" = NPC ini sendiri)
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))
		time_component_manager.connect("morning_shift", on_morning_shift)
		time_component_manager.connect("afternoon_shift", on_afternoon_shift)
		time_component_manager.connect("night_shift", on_night_shift)

func _process(delta: float) -> void:

	adjust_condition_contract_dialouge()
	debug_npc()

func start_dialouge() -> void:
	
	if not npc_unique_dialouge:
		return
	
	var balloon: BaseGameDialougeBalloon = GAME_DIALOUGE_BALLOON.instantiate()
	get_tree().current_scene.add_child(balloon)
	
	
	var title_list: Array = npc_unique_dialouge.get_titles()
	for title in title_list:
		if title.begins_with("contract") and npc_allow_contract:
			var contract_title = title
			if npc_unique_dialouge.titles.has(contract_title):
				balloon.start(npc_unique_dialouge, contract_title)
				break
		else:	
			balloon.start(npc_unique_dialouge, "casual_%s" % npc_name + "_1")
				

func _on_walk_cycle_duration_timeout() -> void:
	requirement_get_contract()
	can_walk = true

func on_morning_shift() -> void:
	is_morning_shift = true
	is_night_shift = false
	
func on_afternoon_shift() -> void:
	is_afternoon_shift = true
	is_morning_shift = false

func on_night_shift() -> void:
	is_afternoon_shift = false
	is_night_shift = true

func set_data_attribute() -> void:
	if npc_data:
		npc_name = npc_data.name
		npc_last_position = npc_data.last_position
		npc_current_position = npc_data.current_position
		npc_unique_dialouge = npc_data.unique_dialouge
		npc_current_satisfaction = npc_data.current_satisfaction

func requirement_get_contract() -> void:
	pass

func adjust_condition_contract_dialouge() -> void:
	#kondisi OK
	#parameter cukup, cuaca bagus, dalam jam kerja
	
	#kondisi tidak OK
	#tidak parameter cukup, tidak cuaca bagus, tidak dalam jam kerja
	
	#tidak parameter cukup, cuaca bagus, dalam jam kerja
	#tidak parameter cukup, tidak cuaca bagus, dalam jam kerja
	#tidak parameter cukup, tidak dalam jam kerja, cuaca bagus
	
	#tidak cuaca bagus, parameter cukup, dalam jam kerja
	#tidak cuaca bagus, tidak parameter cukup, dalam jam kerja
	#tidak cuaca bagus, tidak dalam jam kerja, cuaca bagus
	
	#tidak jam kerja, cuaca bagus, parameter cukup
	
	
	if not is_night_shift and npc_current_satisfaction > 0.1:
		if time_component_manager.current_weather == "clear":
			npc_allow_contract = true
				 
	else:
		npc_allow_contract = false
		
	

func debug_npc() -> void:
	debug_npc_label.text = "name: %s \n allow_contract: %s" % [npc_name, npc_allow_contract] 
