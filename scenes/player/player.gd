class_name Player extends CharacterBody2D

var player_sprite_direction: Vector2 = Vector2.RIGHT
var current_interactable: Node = null
var current_npc_dialogue: NPCBase = null

var can_move: bool = true
var can_interact: bool = false
var dialogue_finished: bool = false
@export var speed = 50
@export var fatigue: float = 0.5 # << Hanya Tester
@export var min_fatigue: float = 0.0
@export var max_fatigue: float = 1.0
@export var hunger: float = 0.0
@export var hunger_increase_per_min: float = 0.001
@export var min_hunger: float = 0.0
@export var max_hunger: float = 1.0

var claim_menu_is_open: bool = false
var inventory_is_open: bool = false
var claim_menu_workshop: WorkShop = null
var claim_menu_claimable_index: int = 0
var claim_fee_confirm_is_open: bool = false
var claim_fee_confirm_choice: int = 0

@onready var player_movement_state: Node = $PlayerStateMachine/PlayerMovementState
@onready var time_component_manager = TimeComponentManager

func _ready() -> void:
	BaseDialogueManager.dialogue_activated.connect(on_dialogue_activated)
	BaseDialogueManager.dialogue_deactivated.connect(on_dialogue_deactivated)
	TimeComponentManager.minute_changed.connect(on_minute_changed)

func on_minute_changed(_minute: int) -> void:
	increase_hunger(hunger_increase_per_min)

func _unhandled_input(event: InputEvent) -> void:
	if claim_menu_is_open:
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			if claim_fee_confirm_is_open:
				if event.keycode == KEY_Y:
					_confirm_claim_choice_with_fee(true)
				elif event.keycode == KEY_N:
					_confirm_claim_choice_with_fee(false)
				elif event.keycode == KEY_ESCAPE:
					_close_claim_menu()
				return

			if event.keycode == KEY_1:
				_open_fee_confirmation(0) # TAKE TO PLAYER
			elif event.keycode == KEY_2:
				_open_workshop_storage_menu_ui()
			elif event.keycode == KEY_3:
				_confirm_claim_choice(2) # CONTINUE_PROCESS
			elif event.keycode == KEY_4:
				_pay_workshop_unpaid_fee()
			elif event.keycode == KEY_5:
				_pay_workshop_overdue_fee()
			elif event.keycode == KEY_ESCAPE:
				_close_claim_menu()
		return

	if not can_move:
		return

	if not event.is_action_pressed("interact"):
		return
	if not can_interact or current_interactable == null:
		return

	if current_interactable is NPCBase:
		var npc: NPCBase = current_interactable as NPCBase

		current_interactable = npc
		current_npc_dialogue = npc

		if npc.global_position.x >= global_position.x:
			npc.animated_sprite_2d.flip_h = true
		else:
			npc.animated_sprite_2d.flip_h = false

		if not npc.start_dialogue():
			current_npc_dialogue = null # dialog gagal mulai: jangan pause waktu, jangan simpan referensi stale
			return

		time_component_manager.toggle_pause()
		npc.interactable_label_component.hide()
		return

	# selain NPC: panggil method interact khusus kalau ada
	elif current_interactable is WorkShop:
		var work_shop: WorkShop = current_interactable as WorkShop
		work_shop.on_player_interact(self)
		work_shop.interactable_label_component.hide()

	elif current_interactable is PickUpItem:
		var pickup_item: PickUpItem = current_interactable as PickUpItem
		pickup_item.on_player_interact(self)

	elif current_interactable is JobBoard:
		var job_board: JobBoard = current_interactable as JobBoard
		job_board.on_player_interact(self)

func _on_interactable_activated(interactable_owner: Node):
	if current_interactable != null:
		return

	if interactable_owner is NPCBase and not (interactable_owner as NPCBase).can_start_dialogue():
		return # NPC tanpa dialog valid: jangan tampilkan prompt interact palsu, jangan jadikan interactable

	current_interactable = interactable_owner
	if current_interactable is PickUpItem:
		current_interactable.on_player_enter_interaction()
	current_interactable.interactable_label_component.show()
	can_interact  = true

func _on_interactable_deactivated(interactable_owner: Node):
	if current_interactable == interactable_owner:
		current_interactable.interactable_label_component.hide()
		current_interactable = null
		can_interact  = false

func on_dialogue_activated() -> void:
	can_move = false
	velocity = Vector2.ZERO

	if current_npc_dialogue:
		current_npc_dialogue.on_dialogue  = true
		current_npc_dialogue.can_walk = false
		current_npc_dialogue.walk_cycle_duration.stop()


func on_dialogue_deactivated() -> void:
	can_move = true

	time_component_manager.toggle_pause()
	if current_npc_dialogue:
		current_npc_dialogue.on_dialogue  = false
		current_npc_dialogue.can_walk = true
		current_npc_dialogue.walk_cycle_duration.start()

	current_npc_dialogue  = null

func open_workshop_menu(workshop: WorkShop, claimable_index: int) -> void:
	claim_menu_is_open = true
	claim_menu_workshop = workshop
	claim_menu_claimable_index = claimable_index
	claim_fee_confirm_is_open = false

	var fee_summary: Dictionary = WorkShopStorage.get_unpaid_fee_summary()
	var claimables: Array = WorkShopStorage.get("claimable_outputs")
	var has_claimable_output: bool = not claimables.is_empty()

	var menu_scene: PackedScene = preload("res://scenes/ui/workshop_menu_ui/workshop_menu_ui.tscn")
	var menu_ui: WorkshopMenuUI = menu_scene.instantiate()

	get_tree().current_scene.add_child(menu_ui)

	menu_ui.action_selected.connect(_on_work_shop_menu_action_selected)
	menu_ui.closed.connect(_on_workshop_menu_closed)

	menu_ui.open_menu(fee_summary, has_claimable_output)

func _confirm_claim_choice(claim_action: int) -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		return
	claim_menu_workshop.claim_with_action(self, claim_menu_claimable_index, claim_action, true)

func _open_fee_confirmation(claim_action: int) -> void:
	claim_fee_confirm_is_open = true
	claim_fee_confirm_choice = claim_action
	print("Bayar Fee sekarang? [Y]=Bayar, [N]=TidakBayar (masuk workshop + hitung jatuh tempo hari)")

func _confirm_claim_choice_with_fee(will_pay_fee: bool) -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		return

	claim_menu_workshop.claim_with_action(self, claim_menu_claimable_index, claim_fee_confirm_choice, will_pay_fee)
	_close_claim_menu()

func _close_claim_menu() -> void:
	claim_menu_is_open = false
	claim_menu_workshop = null
	claim_menu_claimable_index = 0
	claim_fee_confirm_is_open = false
	claim_fee_confirm_choice = 0

func _pay_workshop_unpaid_fee() -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		return
	if claim_menu_workshop.has_method("pay_all_unpaid_fees"):
		var paid_success: bool = bool(claim_menu_workshop.call("pay_all_unpaid_fees", self))
		print("Pay unpaid fee success: ", paid_success)
	_close_claim_menu()

func _pay_workshop_overdue_fee() -> void:
	if claim_menu_workshop == null:
		_close_claim_menu()
		return

	if claim_menu_workshop.has_method("pay_overdue_fees"):
		var paid_success: bool = bool(claim_menu_workshop.call("pay_overdue_fees", self))
		print("Pay overdue fee success", paid_success)

	_close_claim_menu()

func reduce_fatigue(amount: float) -> bool:
	if fatigue > min_fatigue and amount > 0.0:
		fatigue = clampf(fatigue- amount, min_fatigue, max_fatigue)
		return true

	return false

func increase_fatigue(amount: float) -> bool:
	if fatigue < max_fatigue and amount > 0.0:
		fatigue = clampf(fatigue + amount, min_fatigue, max_fatigue)
		return true
	return false

func reduce_hunger(amount: float) -> bool:
	if hunger > min_hunger and amount > 0.0:
		hunger = clampf(hunger - amount, min_hunger, max_hunger)
		return true

	return false

func increase_hunger(amount: float) -> bool:
	if hunger < max_hunger and amount > 0.0:
		hunger = clampf(hunger + amount, min_hunger, max_hunger)
		return true
	return false

func get_focus() -> float:
	return 1.0 - ((fatigue + hunger) / 2.0)

func get_fatigue_percent() -> int:
	return int(fatigue * 100.0)

func get_hunger_percent() -> int:
	return int(hunger * 100.0)

func get_focus_percent() -> int:
	return int(get_focus() * 100.0)

func _open_workshop_storage_menu_ui() -> void:
	if claim_menu_workshop == null:
		return

	var workshop_storage_scene: PackedScene = preload("res://scenes/ui/workshop_storage_menu_ui/workshop_storage_menu_ui.tscn")
	var workshop_storage_menu: WorkshopStorageMenuUI = workshop_storage_scene.instantiate()

	get_tree().current_scene.add_child(workshop_storage_menu)

	workshop_storage_menu.action_selected.connect(_on_workshop_storage_menu_action_selected)
	workshop_storage_menu.closed.connect(_on_workshop_storage_menu_closed)

	claim_menu_is_open = false
	workshop_storage_menu.open_menu()

func _on_workshop_storage_menu_action_selected(action_id: int) -> void:
	match action_id:
		WorkshopStorageMenuUI.Action.DEPOSIT_ITEMS:
			_open_workshop_deposit_transfer()
		WorkshopStorageMenuUI.Action.WITHDRAW_ITEMS:
			_open_workshop_withdraw_transfer()

func _open_workshop_deposit_transfer() -> void:
	if claim_menu_workshop == null:
		return

	var item_transfer_scene: PackedScene = preload("res://scenes/ui/item_transfer_ui/item_transfer_ui.tscn")
	var item_transfer_menu: ItemTransferUI = item_transfer_scene.instantiate()

	get_tree().current_scene.add_child(item_transfer_menu)

	item_transfer_menu.transfer_confirmed.connect(_on_workshop_deposit_confirmed)
	item_transfer_menu.transfer_cancelled.connect(_on_workshop_deposit_cancelled)

	claim_menu_is_open = false
	item_transfer_menu.open_transfer("Deposit to Workshop", Inventory.items, "Deposit")

func _open_workshop_withdraw_transfer() -> void:
	if claim_menu_workshop == null:
		return

	var item_transfer_scene: PackedScene = preload("res://scenes/ui/item_transfer_ui/item_transfer_ui.tscn")
	var item_transfer_menu: ItemTransferUI = item_transfer_scene.instantiate()

	get_tree().current_scene.add_child(item_transfer_menu)

	item_transfer_menu.transfer_confirmed.connect(_on_workshop_withdraw_confirmed)
	item_transfer_menu.transfer_cancelled.connect(_on_workshop_withdraw_cancelled)

	claim_menu_is_open = false
	item_transfer_menu.open_transfer("Withdraw to Inventory", WorkShopStorage.items, "Withdraw")

func _on_workshop_storage_menu_closed() -> void:
	_close_claim_menu()
	_show_current_interact_label()

func _on_workshop_deposit_confirmed(selected_items: Dictionary) -> void:
	if claim_menu_workshop == null:
		return

	var workshop: WorkShop = claim_menu_workshop

	var deposit_success: bool = workshop.deposit_selected_items_from_player(selected_items)

	if not deposit_success:
		_close_claim_menu()
		_show_current_interact_label()
		return

	var index: int = 0

	for item_id in selected_items.keys():
		var qty: int = int(selected_items[item_id])
		var stack_offset: Vector2 = Vector2(0, -12 * index)

		_spawn_item_change_popup(
			item_id,
			qty,
			false,
			global_position + Vector2(0, -28) + stack_offset
		)

		_spawn_item_change_popup(
			item_id,
			qty,
			true,
			workshop.global_position + Vector2(0, -32) + stack_offset
		)

		index += 1

	_close_claim_menu()
	_show_current_interact_label()

func _on_workshop_deposit_cancelled() -> void:
	_close_claim_menu()
	_show_current_interact_label()

func _on_workshop_withdraw_confirmed(selected_items: Dictionary) -> void:
	if claim_menu_workshop == null:
		return

	var workshop: WorkShop = claim_menu_workshop

	var withdraw_success: bool = workshop.withdraw_selected_items_to_player(selected_items)

	if not withdraw_success:
		_close_claim_menu()
		_show_current_interact_label()
		return

	var index: int = 0

	for item_id in selected_items.keys():
		var qty: int = int(selected_items[item_id])
		var stack_offset: Vector2 = Vector2(0, -12 * index)

		_spawn_item_change_popup(
			item_id,
			qty,
			true,
			global_position + Vector2(0, -28) + stack_offset
		)

		_spawn_item_change_popup(
			item_id,
			qty,
			false,
			workshop.global_position + Vector2(0, -32) + stack_offset
		)

		index += 1

	_close_claim_menu()
	_show_current_interact_label()

func _on_workshop_withdraw_cancelled() -> void:
	_close_claim_menu()
	_show_current_interact_label()

func _on_work_shop_menu_action_selected(action_id: int) -> void:
	match action_id:
		WorkshopMenuUI.Action.CLAIM_TO_PLAYER:
			_open_fee_confirmation(WorkShopStorage.ClaimAction.TAKE_TO_PLAYER)
		WorkshopMenuUI.Action.MANAGE_STORAGE:
			_open_workshop_storage_menu_ui()
		WorkshopMenuUI.Action.ASSIGN_WORKER:
			if claim_menu_workshop.has_assigned_worker():
				claim_menu_workshop.start_mudbrick_job_from_storage()
			else:
				claim_menu_workshop.assign_test_worker()

			_close_claim_menu()
			_show_current_interact_label()
		WorkshopMenuUI.Action.PAY_ALL_FEES:
			_pay_workshop_unpaid_fee()
		WorkshopMenuUI.Action.PAY_OVERDUE_FEES:
			_pay_workshop_overdue_fee()

func _on_workshop_menu_closed() -> void:
	_close_claim_menu()
	_show_current_interact_label()

func _show_current_interact_label() -> void:
	if current_interactable == null:
		return

	if not can_interact:
		return

	current_interactable.interactable_label_component.show()

func _spawn_item_change_popup(item_id: String, amount: int, is_positive: bool, pos: Vector2) -> void:
	var popup_scene: PackedScene = preload("res://scenes/ui/item_change_popup/item_change_popup.tscn")
	var item_popup = popup_scene.instantiate()
	get_tree().current_scene.add_child(item_popup)
	item_popup.global_position = pos
	item_popup.setup(item_id, amount, is_positive)
