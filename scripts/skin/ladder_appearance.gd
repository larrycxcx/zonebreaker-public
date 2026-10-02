@tool
class_name LadderAppearance
extends Appearance
## 梯子的外观。有贴图（素材包）就把中段那一格竖着平铺、顶上再盖一截扶手；
## 没贴图（默认皮肤）就画两根竖杆加横档的色块。原点是梯子顶的正中，和 `Ladder` 一样。

## 中段（能无缝竖着平铺的那一格）和顶上露出地面的那截扶手（没有就不画）。
@export var middle: Texture2D
@export var top: Texture2D
@export var rail_color := Color(0.55, 0.6, 0.7, 1)

var _size := Vector2(24, 96)


func _ready() -> void:
	pass


func fit(size: Vector2) -> void:
	_size = size
	queue_redraw()


func _draw() -> void:
	if middle != null:
		var w := float(middle.get_width())
		draw_texture_rect(middle, Rect2(-w / 2.0, 0.0, w, _size.y), true)
		if top != null:
			var tw := float(top.get_width())
			draw_texture(top, Vector2(-tw / 2.0, -top.get_height()))
		return
	# 占位：两根竖杆、每 12 像素一根横档
	var half := _size.x / 2.0
	draw_rect(Rect2(-half, 0.0, 3.0, _size.y), rail_color)
	draw_rect(Rect2(half - 3.0, 0.0, 3.0, _size.y), rail_color)
	var y := 6.0
	while y < _size.y:
		draw_rect(Rect2(-half, y, _size.x, 2.0), rail_color)
		y += 12.0
