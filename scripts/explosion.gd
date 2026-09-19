extends Node2D
## 爆炸的占位特效：一个橙色方块，放大淡出后消失。只管显示，伤害由 Grenade 算。

@export var radius := 28.0
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
