class_name OutlineBox
extends Control
## 一个空心的方框，用来框住「现在选中的是哪一项」。
##
## 界面上不用小箭头当光标了，一律用这个黄框圈住选中的东西——
## 框住的是整块内容（那一行字、那个头像、那一格装备），一眼看得出选的是什么。

@export var colour := Color(0.961, 0.784, 0.353):
	set(value):
		colour = value
		queue_redraw()
## 线宽（像素）。
@export var thickness := 1.0:
	set(value):
		thickness = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 框到这一块上。
func frame(box: Rect2) -> void:
	position = box.position
	size = box.size
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), colour, false, thickness)
