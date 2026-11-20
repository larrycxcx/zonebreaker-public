class_name StripEffect
extends Node2D
## 一次性的帧动画特效（一排正方形的帧，中心对准节点原点）：播一遍就自己删掉。纯显示，没有碰撞。
## 第五关酸液瓶摔碎时那团酸液（`Acid2` 那张）用它。`radius` 是 `Fx` 照爆炸半径设的，这里用不上（素材不缩放）。

@export var strip: Texture2D
@export var frames := 6
@export var fps := 16.0

var radius := 0.0
var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age * fps >= frames:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if strip == null:
		return
	var size := float(strip.get_height())
	var frame := mini(int(_age * fps), frames - 1)
	draw_texture_rect_region(strip, Rect2(-size / 2.0, -size / 2.0, size, size),
		Rect2(size * frame, 0.0, size, size))
