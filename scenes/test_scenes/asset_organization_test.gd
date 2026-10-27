extends Node

# Every owner asset remains represented after relocation or byte-identical reuse.
const ASSETS: Array[Dictionary] = [
	{"path": "res://assets/objects/barrel.png", "uid": "uid://dyc3wa671w6q2", "sha256": "58cd76e7d54d573787df34962d27a691fd66e787cd79dd5eacc2bbf6e926b36e", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/ui_icon/checklist_icon.png", "uid": "uid://dvf6iiypuilwu", "sha256": "4e5b4df71a5297f4c6c116a1a7fd4c63767b3bc4d29142a9df7a95c27c217644", "size": Vector2i(16, 16)},
	{"path": "res://assets/objects/worksites/clay_site.png", "uid": "uid://b650c5xjes0rl", "sha256": "a6d86339ac876b40669dcfd890ce0586a620314e66fa64fda075830a9c522abf", "size": Vector2i(32, 32)},
	{"path": "res://assets/ui/ui_icon/hauler_icon.png", "uid": "uid://70r5ceud5uop", "sha256": "32657f8c396c0fdc9abb9978b4c5a2d64440e2bdff163892004bd37efef0c35c", "size": Vector2i(32, 32)},
	{"path": "res://assets/objects/house_level_0.png", "uid": "uid://fthba18nxxwn", "sha256": "6cf4a1fb554663faf8d3018907fb99f37a28dc4c7cbdf08db40fd08f2cfc925b", "size": Vector2i(64, 64)},
	{"path": "res://assets/objects/job_board.png", "uid": "uid://b760kxx2baat3", "sha256": "443632fa545c9d7ea46aecfe4d3b201195212af9a5b80153b30e2d7c03e9c43e", "size": Vector2i(34, 24)},
	{"path": "res://assets/ui/ui_icon/laborer_icon.png", "uid": "uid://dup44odh1wp4x", "sha256": "80f924435adf3a8c31638b7d97d4215559b8d8a5f454d6fa9bc303d3131938de", "size": Vector2i(32, 32)},
	{"path": "res://assets/ui/ui_icon/no_output_icon.png", "uid": "uid://diuh2vy7hxxf0", "sha256": "80c5193d2eb412dadc9133414721219e1cc4444b32bf9391fe1f992eaf40b4ab", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/building/plot_level_1.png", "uid": "uid://c1reci3qtu8o7", "sha256": "1f413e9cfbbc5dad6ad198b73cd937350d7d10f91eacb34eb62663901f608136", "size": Vector2i(48, 48)},
	{"path": "res://assets/objects/worksites/reed_site_content.png", "uid": "uid://ccxxriex3w5el", "sha256": "42cde0c4f44367a8547171769cc1f7b44532e22eb52ad3f7a7bb6fd89d3ee430", "size": Vector2i(32, 32)},
	{"path": "res://assets/ui/ui_icon/satisfaction_anger_icon.png", "uid": "uid://7vp11m7l42kd", "sha256": "28e06e3fe5aa8c85b99c28c45977002015a8f8511ad79843e2b8b5cba6f76417", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/ui_icon/satisfaction_anger_small_icon.png", "uid": "uid://d13pq8kjqsr5d", "sha256": "7e21091b4b9a0bedba9b4afc75be53a5e58d60d29a569ac61e4eb9dd1a63b39a", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/ui_icon/satisfaction_happy_icon.png", "uid": "uid://bi5cb05fp3nub", "sha256": "20d3971dff79c3edf3db2e1059340582f58f978768422c517205a15b6db2e29c", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/ui_icon/satisfaction_happy_small_icon.png", "uid": "uid://bgifj8o1hiifb", "sha256": "5460629f32d9394ae3917b5799445bc6f55b88de1afc8c8302b7f219a636c041", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/ui_icon/satisfaction_normal_icon.png", "uid": "uid://cbya0n3th2fti", "sha256": "584629ad41e3f507318f16bd8ecb0298140cbf037244a57dbc8c4fad336705f7", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/ui_icon/satisfaction_normal_small_icon.png", "uid": "uid://bfjqiclx7yxsp", "sha256": "8d2400dc22580f648250536a6ae6e14d9121d67d734cee98ac6f9f989f81aacb", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/ui_icon/storage_icon.png", "uid": "uid://cevraa3ucn5ew", "sha256": "4515d1966ca960eda784300f73ae74e138125f9b30026a50cd92c3bcf4273f69", "size": Vector2i(16, 16)},
	{"path": "res://assets/tile_set/tile_set_base_new_24_10_2026_expanded.png", "uid": "uid://c22v1m15n6ky3", "sha256": "ce9466a48e4c62a7c838f5e2c14efdcc52578f47cde2fb957e38033e24c3fcea", "size": Vector2i(359, 458)},
	{"path": "res://assets/ui/building/to_be_clean_1.png", "uid": "uid://yutg1ax64b0w", "sha256": "c0038a02e3a2b40587f174ca68188c86da2d14d270164b3abbb538faefdcac9e", "size": Vector2i(48, 48)},
	{"path": "res://assets/objects/vase_type_1.png", "uid": "uid://c2rm24bmsku7m", "sha256": "e815ef10ae5f197d24d5ccbe64f49a11425404c580065f272cc193c987116a63", "size": Vector2i(16, 16)},
	{"path": "res://assets/objects/vase_type_2.png", "uid": "uid://cpaaqvy6ms60m", "sha256": "d32608c32a4d5a04734ca20196b5add04bfaecbb4688ff298ce959d606260c1d", "size": Vector2i(16, 16)},
	{"path": "res://assets/ui/building/wall_stone_0.png", "uid": "uid://doa2eqsykrlv0", "sha256": "99bc2614fb5b6e6b5512a25fd8c3a86b9c830ad64532698b9edd0cbe54839da8", "size": Vector2i(112, 48)},
	{"path": "res://assets/objects/worksites/water_site.png", "uid": "uid://bn7d4dx4dhbjo", "sha256": "088e921a22d1af70a18fa76ecaaf0f24b196e7809f7ab3b5abdcaa2eb3f64718", "size": Vector2i(32, 32)},
	{"path": "res://assets/objects/worksites/wood_site.png", "uid": "uid://51yjjv2etox8", "sha256": "aeaee396ee1df6789bba5e50748ccfebb5bc5f8fcb7dc500575c09f18726b6ba", "size": Vector2i(32, 32)},
	{"path": "res://assets/objects/workshop_1.png", "uid": "uid://bhs8s48uwgvx8", "sha256": "be1a9b13091da67b75db80ec951004279930708b0957b50d238fe91a50c2772c", "size": Vector2i(48, 64)},
]

var failures := 0
var checks := 0

func _ready() -> void:
	for asset: Dictionary in ASSETS:
		_expect(FileAccess.file_exists(asset.path), "Source exists: " + asset.path)
		_expect(FileAccess.get_sha256(asset.path) == asset.sha256, "Original PNG bytes retained: " + asset.path)
		_expect(ResourceLoader.exists(asset.path, "Texture2D"), "Imported texture exists: " + asset.path)
		var texture: Texture2D = load(asset.path)
		_expect(texture != null and Vector2i(texture.get_size()) == asset.size, "Native dimensions retained: " + asset.path)
		if texture != null:
			_expect(texture.get_image() != null and texture.get_image().get_size() == asset.size, "Imported pixels readable: " + asset.path)
		var id: int = ResourceLoader.get_resource_uid(asset.path)
		_expect(ResourceUID.id_to_text(id) == asset.uid, "Expected stable or canonical UID: " + asset.path)
		_expect(ResourceUID.has_id(id) and ResourceUID.get_id_path(id) == asset.path, "UID resolves to final path: " + asset.path)
	var directory := DirAccess.open("res://assets")
	_expect(not directory.dir_exists("new_asset"), "Staging asset directory removed")
	print("ASSET ORGANIZATION QA checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("PASS " if ok else "FAIL ", label)
