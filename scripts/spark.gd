class_name Spark
extends Node2D
## 命中火花和枪口闪光的占位特效：一个小方块，胀大一点再淡出，然后自己消失。
## 一个脚本几个场景（命中火花、撞墙火花、枪口闪光），差别只在场景里的尺寸、颜色和时长。
## 纯显示，没有碰撞，不影响任何玩法判定。

## 活多久（秒）。
@export var duration := 0.12
## 结束时放大到几倍。1 = 不变。
@export var grow := 2.0

@onready var _rect: ColorRect = $ColorRect


func _ready() -> void:
	_rect.pivot_offset = _rect.size / 2.0
	_rect.position = -_rect.size / 2.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_rect, "scale", Vector2.ONE * grow, duration)
	tween.tween_property(_rect, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(queue_free)
