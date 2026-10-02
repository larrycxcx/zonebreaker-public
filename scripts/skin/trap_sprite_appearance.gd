class_name TrapSpriteAppearance
extends Appearance
## 机关的贴图外观：一条 8 帧的动画（32×64 一帧），玩法告诉它第几帧就画第几帧——
## 不自己按时间播，**画面和判定永远是同一帧**。
## 液压机还有一根活塞杆：从天花板（`set_mount()`）一直接到这一帧的顶上，一行图竖着平铺。

@export var strip: Texture2D
@export var rod: Texture2D
@export var frames := 8

## 活塞杆从哪儿开始（本地坐标的 y，负数 = 在这一帧上面）。没有杆子的（闸门）不用管。
var _mount := 0.0
var _frame := 0


func _ready() -> void:
	pass


func set_mount(local_y: float) -> void:
	_mount = local_y
	queue_redraw()


func show_frame(frame: int) -> void:
	_frame = frame
	queue_redraw()


func _draw() -> void:
	if rod != null and _mount < 0.0:
		draw_texture_rect(rod, Rect2(0.0, _mount, rod.get_width(), -_mount), true)
	if strip == null:
		return
	var w := strip.get_width() / float(frames)
	draw_texture_rect_region(strip, Rect2(0.0, 0.0, w, strip.get_height()),
		Rect2(w * _frame, 0.0, w, strip.get_height()))
