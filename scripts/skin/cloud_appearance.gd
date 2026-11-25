class_name CloudAppearance
extends Appearance
## The look of a poison cloud: gameplay tells it "how far it has spread" (`show_progress(0..1)`) and it draws that frame —
## it does not play on its own timer, so the picture and the hit check share one progress.
## With a texture (the pack's `Acid2`, a cloud of poison slowly spreading out, square frames) it picks the frame by progress, centred on the node origin;
## without one (default skin) it draws a translucent ring that fades as it spreads.

@export var strip: Texture2D
@export var frames := 6
@export var color := Color(0.35, 0.85, 0.45, 0.55)
## Radius of the ring without a texture (the same as gameplay's hit radius).
@export var radius := 24.0

var _progress := 0.0


func _ready() -> void:
	pass


func show_progress(progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func current_frame() -> int:
	return mini(int(_progress * frames), frames - 1)


func _draw() -> void:
	if strip == null:
		var faded := color
		faded.a *= 1.0 - _progress * 0.7
		draw_circle(Vector2.ZERO, radius, faded)
		return
	var size := float(strip.get_height())
	draw_texture_rect_region(strip, Rect2(-size / 2.0, -size / 2.0, size, size),
		Rect2(size * current_frame(), 0.0, size, size))
