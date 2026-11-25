class_name Spark
extends Node2D
## Placeholder effect for hit sparks and muzzle flashes: a small square that grows a little, fades out, then removes itself.
## One script, several scenes (hit sparks, wall sparks, muzzle flash), differing only in size, colour and duration in the scene.
## Display only, no collision, affects no gameplay check.

## Lifetime (seconds).
@export var duration := 0.12
## Scale reached at the end. 1 = unchanged.
@export var grow := 2.0

@onready var _rect: ColorRect = $ColorRect


func _ready() -> void:
	_rect.pivot_offset = _rect.size / 2.0
	_rect.position = -_rect.size / 2.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_rect, "scale", Vector2.ONE * grow, duration)
	tween.tween_property(_rect, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(queue_free)
