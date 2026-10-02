class_name TrapBlocks
extends Appearance
## 机关的占位外观（默认皮肤）：按机关自己给的形状（`art_rects(帧)`）画几块色块。
## 形状和判定是同一张表，所以占位画出来的就是碰得到的地方。

@export var color := Color(0.85, 0.45, 0.2, 1)

var _frame := 0


func _ready() -> void:
	pass


func show_frame(frame: int) -> void:
	_frame = frame
	queue_redraw()


## 可打爆的箱子用的：打烂了就不画了（形状由它自己的 `art_rects()` 说了算）。
func show_damage(_stage: float, _broken: bool) -> void:
	queue_redraw()


func _draw() -> void:
	var owner_ := get_parent()
	if owner_ == null or not owner_.has_method(&"art_rects"):
		return
	for rect: Rect2 in owner_.call(&"art_rects", _frame):
		draw_rect(rect, color)
