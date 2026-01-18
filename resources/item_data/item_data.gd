class_name ItemData extends Resource

var id: String = ""
var display_name: String = ""
var stackable: bool = false
var description: String = ""
var icon: Texture2D

@export var max_stack: int = 0
@export var durability_max: int = 0 # khusus TOOL; 0 untuk non-tool
@export var base_value_shekel: int = 0
@export var category: ItemEnums.ItemCategory = ItemEnums.ItemCategory.MATERIAL
@export var rarity: ItemEnums.Rarity = ItemEnums.Rarity.COMMON
