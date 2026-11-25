class_name StripEffect
extends Node2D
## A one-shot frame-animation effect (a row of square frames, centred on the node origin): plays once, then deletes itself. Display only, no collision.
## Used for the splash of acid when a stage 5 acid flask shatters (the `Acid2` image). `radius` is set by `Fx` from the blast radius and is not used here (the art is not scaled).

@export var strip: Texture2D
@export var frames := 6
@export var fps := 16.0

var radius := 0.0
var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age * fps >= frames:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if strip == null:
		return
	var size := float(strip.get_height())
	var frame := mini(int(_age * fps), frames - 1)
	draw_texture_rect_region(strip, Rect2(-size / 2.0, -size / 2.0, size, size),
		Rect2(size * frame, 0.0, size, size))
