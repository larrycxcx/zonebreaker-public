class_name TrapBlocks
extends Appearance
## Placeholder look for traps (default skin): draws a few coloured blocks in the shape the trap gives (`art_rects(frame)`).
## The shape and the hit check come from the same table, so the placeholder draws exactly what can hurt you.

@export var color := Color(0.85, 0.45, 0.2, 1)

var _frame := 0


func _ready() -> void:
	pass


func show_frame(frame: int) -> void:
	_frame = frame
	queue_redraw()


## For breakable crates: nothing is drawn once broken (the shape is up to its own `art_rects()`).
func show_damage(_stage: float, _broken: bool) -> void:
	queue_redraw()


func _draw() -> void:
	var owner_ := get_parent()
	if owner_ == null or not owner_.has_method(&"art_rects"):
		return
	for rect: Rect2 in owner_.call(&"art_rects", _frame):
		draw_rect(rect, color)
