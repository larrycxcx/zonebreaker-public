extends Node2D
## Placeholder explosion effect: an orange square that grows and fades out. Display only; damage is worked out by Grenade.

@export var radius := 56.0
@export var duration := 0.25

@onready var _rect: ColorRect = $ColorRect


func _ready() -> void:
	_rect.size = Vector2(radius, radius) * 2.0
	_rect.position = -_rect.size / 2.0
	_rect.pivot_offset = _rect.size / 2.0
	_rect.scale = Vector2(0.4, 0.4)
	var tween := create_tween().set_parallel()
	tween.tween_property(_rect, "scale", Vector2.ONE, duration)
	tween.tween_property(_rect, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(queue_free)
