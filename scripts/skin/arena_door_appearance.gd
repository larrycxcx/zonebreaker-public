class_name ArenaDoorAppearance
extends Appearance
## The look of the arena door: the door panel retracts into the ceiling (`show_open(ratio)`, 0 = down, 1 = fully retracted).
## With a texture it draws the texture (the skin pack: the lab's `Door3`, a 32×64 door pillar with red warning lights), otherwise a block of colour.
## The drawing origin is the door's top-left corner, the same as `ArenaDoor`; what shows is the **lower part** of the panel — the upper part has retracted into the ceiling.

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
