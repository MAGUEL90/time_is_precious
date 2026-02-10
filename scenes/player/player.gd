class_name Player extends CharacterBody2D

var player_sprite_direction: Vector2 = Vector2.RIGHT
var current_interactable: Node = null
var current_npc_dialogue: NPCBase = null

var can_interact: bool = false
var dialogue_finished: bool = false
var speed = 50

var claim_menu_is_open: bool = false
var claim_menu_workshop: WorkShop = null
var claim_menu_claimable_index: int = 0

@onready var player_movement_state: Node = $PlayerStateMachine/PlayerMovementState
@onready var time_component_manager = TimeComponentManager

func _ready() -> void:
	BaseDialogueManager.dialogue_activated.connect(on_dialogue_activated)
	BaseDialogueManager.dialogue_deactivated.connect(on_dialogue_deactivated)


func _unhandled_input(event: InputEvent) -> void:
	if claim_menu_is_open:
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			if event.keycode == KEY_1:
				_confirm_claim_choice(0) # TAKE TO PLAYER
			elif event.keycode == KEY_2:
				_confirm_claim_choice(1) # STORE IN WORKSHOP
			elif event.keycode == KEY_3:
				_confirm_claim_choice(2) # CONTINUE_PROCESS
			elif event.keycode == KEY_ESCAPE:
				_close_claim_menu()
		return
	
	if not event.is_action_pressed("interact"):
		return
	if not can_interact or current_interactable == null:
		return
	
	if current_interactable is NPCBase:
		var npc: NPCBase = current_npc_dialogue as NPCBase
		current_npc_dialogue = npc
		
		if npc.global_position.x >= global_position.x:
			npc.animated_sprite_2d.flip_h = true
		else:
			npc.animated_sprite_2d.flip_h = false
			
		npc.start_dialogue ()
		time_component_manager.toggle_pause()
		npc.interactable_label_component.hide()
		return
		
	# selain NPC: panggil method interact khusus kalau ada
	elif current_interactable is WorkShop:
		var work_shop: WorkShop = current_interactable as WorkShop
		
		work_shop.on_player_interact(self)
		work_shop.interactable_label_component.hide()

func _on_interactable_activated(interactable_owner: Node):
	if current_interactable != null:
		return
	
	current_interactable = interactable_owner
	current_interactable.interactable_label_component.show()
	can_interact  = true

func _on_interactable_deactivated(interactable_owner: Node):
	if current_interactable == interactable_owner:
		current_interactable.interactable_label_component.hide()
		current_interactable = null
		can_interact  = false

func on_dialogue_activated() -> void:
	
	if current_npc_dialogue:
		current_npc_dialogue.on_dialogue  = true
		current_npc_dialogue.can_walk = false
		current_npc_dialogue.walk_cycle_duration.stop()
		

	process_mode = Node.PROCESS_MODE_DISABLED

func on_dialogue_deactivated() -> void:
	time_component_manager.toggle_pause()
	if current_npc_dialogue:
		current_npc_dialogue.on_dialogue  = false
		current_npc_dialogue.can_walk = true
		current_npc_dialogue.walk_cycle_duration.start()
	
	current_npc_dialogue  = null
	process_mode = Node.PROCESS_MODE_INHERIT

func open_workshop_claim_menu(workshop: WorkShop, claimable_index: int) -> void:
	claim_menu_is_open = true
	claim_menu_workshop = workshop
	claim_menu_claimable_index = claimable_index
	print("CLAIM MENU: ")
	print("1) Ambil ke Inventory Player")
	print("2) Simpan ke Inventory Workshop")
	print("3) Lanjut Proses (auto-pull)")
	print("ESC) Batal")

func _confirm_claim_choice(claim_action: int) -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		return
	claim_menu_workshop.claim_with_action(self, claim_menu_claimable_index, claim_action)
	_close_claim_menu()

func _close_claim_menu() -> void:
	claim_menu_is_open = false
	claim_menu_workshop = null
	claim_menu_claimable_index = 0
