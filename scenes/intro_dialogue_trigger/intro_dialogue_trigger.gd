class_name IntroDialogueTrigger extends Node

const INTRO_DIALOGUE = preload("res://dialogue/game_dialogue_conversations/intro/intro.dialogue")
const GAME_DIALOGUE_BALLOON = preload("res://dialogue/game_dialogue_balloon/game_dialogue_balloon.tscn")

func _ready() -> void:
	call_deferred("_start_intro") # deferred agar semua node (terutama Player) selesai _ready dan signal dialog sudah ter-connect

func _start_intro() -> void:
	if BaseDialogueManager.intro_seen:
		return

	BaseDialogueManager.intro_seen = true

	var balloon: BaseGameDialogueBalloon = GAME_DIALOGUE_BALLOON.instantiate()
	get_tree().current_scene.add_child(balloon)

	TimeComponentManager.toggle_pause() # pasangan toggle untuk resume di Player.on_dialogue_deactivated (sama seperti alur interact NPC)
	balloon.start(INTRO_DIALOGUE, "intro_1")
