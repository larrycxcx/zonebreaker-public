class_name Bullet
extends Area2D
## 直线飞行的子弹，撞到 world 层或超过存活时间后消失。

@export var speed := 260.0
@export var lifetime := 1.2

var direction := Vector2.RIGHT

var _age := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(_body: Node2D) -> void:
	queue_free()
