class_name Enemy
extends CharacterBody2D
## 敌人基类：生命值、受击闪白、死亡、重力。具体行为见子类。

signal died

@export var max_health := 2
## 碰到玩家时对玩家造成的伤害。
@export var contact_damage := 1
@export var gravity := 900.0
@export var max_fall_speed := 400.0

var health := 0

@onready var _visual: Node2D = $Visual


func _ready() -> void:
	health = max_health


## 被子弹调用（Bullet 通过 has_method("take_damage") 找到它）。
## `_source_position` 目前用不到，只为和 Player.take_damage 保持同样的签名。
func take_damage(amount: int, _source_position := Vector2.INF) -> void:
	if health <= 0:
		return
	health -= amount
	if health <= 0:
		die()
	else:
		_flash()


func die() -> void:
	died.emit()
	queue_free()


func _flash() -> void:
	_visual.modulate = Color(2.0, 2.0, 2.0)
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color.WHITE, 0.12)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
