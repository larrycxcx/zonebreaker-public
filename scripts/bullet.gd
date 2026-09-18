class_name Bullet
extends Area2D
## 直线飞行的子弹。撞到任何碰撞体就消失，命中目标时造成伤害。
## 打谁由场景里的 collision_mask 决定（玩家子弹打 world+enemy，敌人子弹打 world+player）。
## 单向平台不挡子弹：玩家能从下面穿过去，子弹也一样，否则站在平台上的敌人从下面永远打不到。

@export var speed := 260.0
@export var lifetime := 1.2
@export var damage := 1

var direction := Vector2.RIGHT

var _age := 0.0


func _ready() -> void:
	# 外形是横着的细条，按飞行方向转过去（向上打时变成竖条）。
	# direction 在 add_child 之前就设好了，所以这里读到的是最终值。
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_age += delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Platform and (body as Platform).one_way:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position)
	queue_free()
