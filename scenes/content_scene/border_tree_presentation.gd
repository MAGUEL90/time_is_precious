extends Node
## Retain hidden targets for retired sites so existing worksite records keep their IDs.
## The authoring scene alone determines which poplars are visible.
const POPLAR: Texture2D = preload("res://assets/objects/nature/trees/poplar.png")
const ROOTS: Array[Vector2] = [
	Vector2(35, -46), Vector2(69, -58),
	Vector2(67, -46), Vector2(228, -58),
	Vector2(282, -50), Vector2(306, -50), Vector2(348, -54),
]

const RETIRED_AUTHORED: Dictionary = {
	"WoodSiteB": Vector2(50, -66),
	"WoodSiteD": Vector2(244, -83),
	"WoodSiteE": Vector2(170, -248),
	"WoodSitePoplar7": Vector2(74, -66),
	"WoodSitePoplar9": Vector2(73, -142),
	"WoodSitePoplar10": Vector2(45, -121),
	"WoodSitePoplar20": Vector2(54, -248),
	"WoodSitePoplar24": Vector2(112, -250),
	"WoodSitePoplar25": Vector2(151, -252),
	"WoodSitePoplar26": Vector2(247, -248),
	"WoodSitePoplar28": Vector2(289, -251),
	"WoodSitePoplar32": Vector2(74, -248),
	"WoodSitePoplar33": Vector2(201, -234),
	"WoodSitePoplar34": Vector2(222, -234),
	"WoodSitePoplar36": Vector2(305, -233),
	"WoodSitePoplar37": Vector2(246, -234),
	"WoodSitePoplar38": Vector2(344, -235),
}

func _enter_tree() -> void:
	var world := get_parent().get_node("AuthoredMap/YSortWorld") as Node2D
	for index: int in range(ROOTS.size()):
		if world.has_node("BorderWorksiteTree%d" % index):
			continue
		var tree := Sprite2D.new()
		tree.name = "BorderWorksiteTree%d" % index
		tree.texture = POPLAR
		tree.visible = false
		# Existing border artwork had its upper-left corner at ROOTS - (16, 64).
		tree.position = ROOTS[index] - Vector2(0, 32)
		world.add_child(tree)


	if not world.has_node("RetiredPoplar11"):
		var retired := Sprite2D.new()
		retired.name = "RetiredPoplar11"
		retired.texture = POPLAR
		retired.visible = false
		retired.position = Vector2(38, -164)
		world.add_child(retired)

	for site_id: String in RETIRED_AUTHORED:
		var node_name: String = "Retired_" + site_id
		if world.has_node(node_name):
			continue
		var source := Sprite2D.new()
		source.name = node_name
		source.texture = POPLAR
		source.visible = false
		source.position = RETIRED_AUTHORED[site_id]
		world.add_child(source)
