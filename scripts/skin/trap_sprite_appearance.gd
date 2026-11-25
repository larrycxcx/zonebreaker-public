class_name TrapSpriteAppearance
extends Appearance
## Sprite look for traps: an 8-frame animation (32×64 per frame), drawing whichever frame gameplay says —
## it does not play on its own timer, so **the picture and the hit check are always on the same frame**.
## The hydraulic press also has a piston rod: from the ceiling (`set_mount()`) down to the top of the current frame, one row of image tiled vertically.

@export var strip: Texture2D
@export var rod: Texture2D
@export var frames := 8

## Where the piston rod starts (local y, negative = above this frame). Traps without a rod (the gate) can ignore it.
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
