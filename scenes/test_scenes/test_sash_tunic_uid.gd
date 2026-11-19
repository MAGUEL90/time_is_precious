extends SceneTree

const SHARED := "res://assets/characters/shared_assets/cloth_assets/sash_tunic/idle/idle.png"
const MERCHANT := "res://assets/characters/merchant/mudbrick_npc/sash_tunic/idle/idle.png"

func _initialize() -> void:
	var shared_uid := ResourceLoader.get_resource_uid(SHARED)
	var merchant_uid := ResourceLoader.get_resource_uid(MERCHANT)
	var valid := shared_uid != -1 and merchant_uid != -1 and shared_uid != merchant_uid
	valid = valid and ResourceUID.get_id_path(shared_uid) == SHARED
	valid = valid and ResourceUID.get_id_path(merchant_uid) == MERCHANT
	valid = valid and ResourceLoader.load(SHARED) != null and ResourceLoader.load(MERCHANT) != null
	print("SashTunicUIDTest: ", "PASS" if valid else "FAIL")
	quit(0 if valid else 1)
