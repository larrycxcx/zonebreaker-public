@tool
class_name Platform
extends StaticBody2D
## A rectangular ground / platform. The origin is the top-left corner; `size` sets the size of the collision shape and the display block.

@export var size := Vector2(96, 16):
	set(value):
		size = value
		_apply()
@export var color := Color(0.35, 0.55, 0.3):
	set(value):
		color = value
		_apply()
## One-way platform: can be passed through from below, only stood on from above.
@export var one_way := false:
	set(value):
		one_way = value
		_apply()
## Conveyor belt (2026-10): people and enemies standing on it are carried at this speed (positive right, negative left, 0 = an ordinary platform).
## It uses StaticBody2D's own `constant_linear_velocity`: the platform does not move, but bodies touching it are carried as if it did,
## because `move_and_slide()` already adds the velocity of the platform underfoot — not a line of player or enemy code had to change.
@export var conveyor := 0.0
## Which terrain of the skin pack draws it (the terrain_* entries of `SkinPack.APPEARANCE_KEYS`). Only the look, not the rules.
## Empty picks by the platform's own nature: one-way platforms are the floating `terrain_ledge`, everything else stone blocks `terrain_stone`.
@export var skin_key := &""

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _rect: ColorRect = $Visual/ColorRect

var _visual: Node


func _ready() -> void:
	# In the editor (@tool) the skin pack singleton is not running, so just show the scene's own colour block
	if not Engine.is_editor_hint():
		_visual = Skins.build_appearance(self, terrain_key())
	_apply()


## The terrain key actually used (picked automatically from one-way or not when `skin_key` is empty).
func terrain_key() -> StringName:
	if skin_key != &"":
		return skin_key
	return &"terrain_ledge" if one_way else &"terrain_stone"


func _apply() -> void:
	# Properties are assigned before _ready when the scene loads, when the child nodes are not available yet.
	if not is_node_ready():
		return
	(_shape.shape as RectangleShape2D).size = size
	_shape.position = size / 2.0
	_shape.one_way_collision = one_way
	constant_linear_velocity = Vector2(conveyor, 0.0)
	_rect.size = size
	_rect.color = color
	if _visual != null and _visual.has_method(&"fit"):
		_visual.call(&"fit", size)
