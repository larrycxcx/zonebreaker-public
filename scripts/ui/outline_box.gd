class_name OutlineBox
extends Control
## A hollow box used to frame "which item is selected now".
##
## The UI no longer uses little arrows as cursors; selected things are always framed by this yellow box —
## it frames the whole piece of content (that line of text, that portrait, that gear box), so you can see at a glance what is selected.

@export var colour := Color(0.961, 0.784, 0.353):
	set(value):
		colour = value
		queue_redraw()
## Line width (pixels).
@export var thickness := 1.0:
	set(value):
		thickness = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Frame this rectangle.
func frame(box: Rect2) -> void:
	position = box.position
	size = box.size
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), colour, false, thickness)
