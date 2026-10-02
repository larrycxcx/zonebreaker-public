class_name BreakableCrate
extends StaticBody2D
## 可打爆的箱子（2026-10）：堵在路上，**开几枪打烂才过得去**。一块 32×24（素材 `Chest.png` 那只箱子的大小）、实心（world 层）——
## 挡人、挡敌人、挡子弹，和墙一样；敌人可以躲在后面。被打 `toughness` 下就散架，碰撞撤掉、路就通了。
## 敌人的子弹打在上面也算数（躲在后面的人朝你开枪，可能自己把掩体打烂）。
## 节点原点在左上角。一只 24 高、跳得过去；地图里一竖条 `K` 会摞成一堆（`map_build.py`），摞到顶才真堵死。

@export var skin_key := &"trap_crate"
## 几下打烂（不按伤害算，按次数：换了把伤害高的枪，箱子不会一碰就碎，谜题的节奏才稳）。
@export var toughness := 4

const SIZE := Vector2(32, 24)

var hits := 0
var broken := false
var _visual: Node

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_visual = Skins.build_appearance(self, skin_key)
	_show()


func take_damage(_amount: int, _source_position := Vector2.INF, _from: Node = null) -> void:
	if broken:
		return
	hits += 1
	if hits >= toughness:
		broken = true
		_shape.set_deferred(&"disabled", true)
		GameEvents.report(&"bullet_impact", self)
	_show()
	if broken:
		# 散架动画走完再撤掉（外观自己播；占位色块就直接没了）
		var timer := get_tree().create_timer(0.5)
		timer.timeout.connect(queue_free)


## 外观看的是「打到第几下了」：0 = 完好，越打越烂，`broken` 之后播散架。
func damage_stage() -> float:
	return clampf(float(hits) / float(toughness), 0.0, 1.0)


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_damage"):
		_visual.call(&"show_damage", damage_stage(), broken)


func art_rects(_frame: int) -> Array[Rect2]:
	return [] if broken else [Rect2(Vector2.ZERO, SIZE)]
