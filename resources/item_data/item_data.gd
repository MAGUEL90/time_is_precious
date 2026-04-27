class_name ItemData extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var weight: float = 0.0
@export var category: ItemEnums.ItemCategory = ItemEnums.ItemCategory.RESOURCE
@export var max_stack: int = 99
@export var durability_max: int = 0 # khusus TOOL; 0 untuk non-tool
@export var base_value_shekel: int = 0
@export var rarity: ItemEnums.Rarity = ItemEnums.Rarity.COMMON
@export var fatigue_reduction: float = 0.0
@export var hunger_reduction: float = 0.0
@export var food_supply_value: int = 0
