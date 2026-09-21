class_name Appearance
extends Node2D
## 角色的外观层：挂在每个角色的 `Visual` 节点上，是玩法和「长什么样」之间的唯一接口。
##
## 玩法代码只调下面这几个方法——朝向、姿势、瞄准、受击、闪烁、死亡、后坐力——
## 不去碰方块、颜色、缩放、`modulate`。换皮肤时只要给出一个同样接口的实现，玩法一行都不用改。
## 现在这个实现就是占位方块的画法：压扁表示趴下、改 `modulate` 表示受击和闪烁、按瞄准方向切换枪的方块。
##
## 这里只管「看起来怎么样」。判定点（枪口、射线、受击框）一律挂在角色**本体**上、不在 `Visual` 里，
## 所以换外观不会改变任何游戏规则（`tests/test_visuals.gd` 守着这条）。

## 角色现在在做什么。玩法每帧算出来告诉外观，外观据此选动画（占位方块只有一个样子，用不上）。
## 趴下不在这里：由 `pose()` 的高度比例表示，一件事只从一个地方说。
enum Motion {
	IDLE,  ## 站着不动
	WALK,  ## 走
	RUN,   ## 奔跑（按住 Alt）
	JUMP,  ## 在空中上升
	FALL,  ## 在空中下落
}

## 按瞄准方向切换的枪（玩家用）：方向 → 子节点名字。场景里没有的就跳过。
const GUN_BY_AIM := {
	Vector2(1, 0): "Gun",
	Vector2(0, -1): "GunUp",
	Vector2(1, -1): "GunDiagonalUp",
	Vector2(1, 1): "GunDiagonalDown",
	Vector2(0, 1): "GunDown",
}

## 会跟着瞄准方向转动的枪管（敌人用；玩家是切换好几块枪，不用这个）。留空表示没有。
@export var turning_gun: NodePath

## 各子节点朝右时的横向位置，翻转时按它镜像（见 VisualFlip）。
var _bases := {}
## 姿势（趴下）带来的整体位移，和后坐力的临时偏移**分开记**再相加，
## 否则开枪和趴下会互相把对方的位移抹掉。
var _pose_offset := Vector2.ZERO
var _kick := Vector2.ZERO
var _facing := 1
var _aim := Vector2.RIGHT


func _ready() -> void:
	_bases = VisualFlip.capture(self)
	face(_facing)


## 朝向：1 朝右，-1 朝左。
func face(facing: int) -> void:
	_facing = facing
	VisualFlip.apply(_bases, facing)
	_turn_gun()


## 瞄准方向（单位向量）：按方向切换枪的方块，并把会转的枪管转过去。
func aim(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		_aim = direction
	var key := Vector2(absf(signf(_aim.x)), signf(_aim.y))
	for aim_key in GUN_BY_AIM:
		var gun := get_node_or_null(NodePath(GUN_BY_AIM[aim_key])) as CanvasItem
		if gun != null:
			gun.visible = aim_key == key
	_turn_gun()


## 现在在做什么（站/走/跑/上升/下落）。占位方块只有一个样子，不用管；精灵图版据此选动画。
func motion(_state: Motion) -> void:
	pass


## 姿势：身体现在压到原来的几成高（`height_ratio`）、整体下移多少（`lowered`）。
## 占位美术直接纵向压扁；换成精灵图时这里改成切换「站 / 趴」两套图。
func pose(height_ratio: float, lowered: float) -> void:
	scale.y = height_ratio
	_pose_offset.y = lowered
	_apply_offset()


## 后坐力这类临时位移（纯表现，不影响任何判定）。
func kick(offset: Vector2) -> void:
	_kick = offset
	_apply_offset()


## 挨了一下：闪一下白。
func flash_hit() -> void:
	modulate = Color(2.0, 2.0, 2.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.12)


## 无敌闪烁：1.0 是正常，小于 1 是变淡的那一下。
func blink(alpha: float) -> void:
	modulate.a = alpha


## 死了：整体变暗。
func show_dead() -> void:
	modulate = Color(0.5, 0.5, 0.5, 1.0)


func _apply_offset() -> void:
	position = _pose_offset + _kick


func _turn_gun() -> void:
	var gun := get_node_or_null(turning_gun) as Control
	if gun != null:
		VisualFlip.aim_gun(gun, _facing, _aim)
