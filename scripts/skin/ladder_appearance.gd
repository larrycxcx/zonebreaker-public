@tool
class_name LadderAppearance
extends Appearance
## The look of a ladder. With a texture (skin pack) the middle section is tiled vertically and a stretch of handrail goes on top;
## without one (default skin) it draws coloured blocks for two rails and rungs. The origin is the top centre of the ladder, the same as `Ladder`.

## The middle section (the piece that tiles seamlessly vertically) and the stretch of handrail sticking out above the floor (not drawn if missing).
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
	# Placeholder: two rails and a rung every 12 pixels
	var half := _size.x / 2.0
	draw_rect(Rect2(-half, 0.0, 3.0, _size.y), rail_color)
	draw_rect(Rect2(half - 3.0, 0.0, 3.0, _size.y), rail_color)
	var y := 6.0
	while y < _size.y:
		draw_rect(Rect2(-half, y, _size.x, 2.0), rail_color)
		y += 12.0
