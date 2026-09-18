@tool
class_name Platform
extends StaticBody2D
## 矩形地面/平台。原点在左上角，`size` 决定碰撞体和显示方块的大小。

@export var size := Vector2(48, 8):
	set(value):
		size = value
		_apply()
@export var color := Color(0.35, 0.55, 0.3):
	set(value):
		color = value
		_apply()
## 单向平台：可以从下方穿过，只在上方站立。
@export var one_way := false:
	set(value):
		one_way = value
		_apply()

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _rect: ColorRect = $ColorRect


func _ready() -> void:
	_apply()


func _apply() -> void:
	# 属性在场景加载时会先于 _ready 被赋值，此时子节点还不可用。
	if not is_node_ready():
		return
	(_shape.shape as RectangleShape2D).size = size
	_shape.position = size / 2.0
	_shape.one_way_collision = one_way
	_rect.size = size
	_rect.color = color
