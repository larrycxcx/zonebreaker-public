class_name ArenaDoorAppearance
extends Appearance
## 房间门的样子：门板往天花板里缩（`show_open(比例)`，0 = 放下来、1 = 全缩进去）。
## 有贴图就画贴图（素材包：实验室的 `Door3`，32×64 的门柱，带红色警示灯），没有就画一块色块。
## 画的原点是门的左上角，和 `ArenaDoor` 一样；门板露出来的是**下半截**——上面那截缩进天花板了。

@export var texture: Texture2D
@export var color := Color(0.75, 0.3, 0.3, 1)

const SIZE := Vector2(32, 64)

var _ratio := 1.0


func show_open(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var shown := SIZE.y * (1.0 - _ratio)
	if shown < 0.5:
		return
	if texture == null:
		draw_rect(Rect2(0, 0, SIZE.x, shown), color)
		draw_rect(Rect2(0, shown - 3.0, SIZE.x, 3.0), color.darkened(0.4))
		return
	var cut := SIZE.y - shown
	draw_texture_rect_region(texture, Rect2(0, 0, SIZE.x, shown), Rect2(0, cut, SIZE.x, shown))
