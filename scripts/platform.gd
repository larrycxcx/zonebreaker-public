@tool
class_name Platform
extends StaticBody2D
## 矩形地面/平台。原点在左上角，`size` 决定碰撞体和显示方块的大小。

@export var size := Vector2(96, 16):
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
## 传送带（2026-10）：站在上面的人和敌人被这个速度带着走（正数往右、负数往左，0 = 普通平台）。
## 用的是 StaticBody2D 自带的 `constant_linear_velocity`：自己不动，但碰着它的身体像它在动一样被带着走，
## `move_and_slide()` 本来就会把脚下平台的速度加上——不用改玩家和敌人一行代码。
@export var conveyor := 0.0
## 素材包里用哪种地形画它（`SkinPack.APPEARANCE_KEYS` 里的 terrain_*）。只管长什么样，和规则无关。
## 留空就按平台自己的性质挑：单向平台是浮空的 `terrain_ledge`，其余是石砖 `terrain_stone`。
@export var skin_key := &""

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _rect: ColorRect = $Visual/ColorRect

var _visual: Node


func _ready() -> void:
	# 编辑器里（@tool）素材包单例没在跑，显示场景自带的色块就好
	if not Engine.is_editor_hint():
		_visual = Skins.build_appearance(self, terrain_key())
	_apply()


## 实际用的地形键（`skin_key` 留空时按单向与否自动挑）。
func terrain_key() -> StringName:
	if skin_key != &"":
		return skin_key
	return &"terrain_ledge" if one_way else &"terrain_stone"


func _apply() -> void:
	# 属性在场景加载时会先于 _ready 被赋值，此时子节点还不可用。
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
