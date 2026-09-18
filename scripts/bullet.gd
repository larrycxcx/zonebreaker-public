class_name Bullet
extends Area2D
## 直线飞行的子弹。撞到任何碰撞体就消失，命中目标时造成伤害。
## 打谁由场景里的 collision_mask 决定（玩家子弹打 world+enemy，敌人子弹打 world+player）。

@export var speed := 260.0
@export var lifetime := 1.2
@export var damage := 1

var direction := Vector2.RIGHT

var _age := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position)
	queue_free()
