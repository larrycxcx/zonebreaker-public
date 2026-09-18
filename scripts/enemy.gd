class_name Enemy
extends CharacterBody2D
## 敌人基类：生命值、受击闪白、死亡、重力，以及共用的射击逻辑。具体行为见子类。

signal died

@export var max_health := 2
## 碰到玩家时对玩家造成的伤害。
@export var contact_damage := 1
@export var gravity := 900.0
@export var max_fall_speed := 400.0

@export_group("Shooting")
## 留空表示这个敌人不会射击。
@export var bullet_scene: PackedScene
@export var fire_interval := 1.4
@export var detect_range := 150.0
## 和玩家的高度差在这个范围内才会开火（子弹只走水平方向）。
@export var vertical_tolerance := 20.0

var health := 0
## 面朝方向，同时决定子弹飞行方向：-1 向左，1 向右。
var facing := -1

var _fire_timer := 0.0

@onready var _visual: Node2D = $Visual
## 每个敌人场景都必须有 `Visual/Muzzle`，且本地 y 坐标为 0。
## 各种敌人的碰撞体底边都贴着自己的原点下方 7px，所以本地 y=0 能保证
## 站在同一地面上的不同敌人出膛高度完全一致。
@onready var _muzzle: Marker2D = $Visual/Muzzle


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


## 射程和高度容差内的玩家，够不着就返回 null。
func find_target() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return null
	var offset := player.global_position - global_position
	if absf(offset.x) > detect_range or absf(offset.y) > vertical_tolerance:
		return null
	return player


## 冷却好了就朝 `facing` 方向打一发。`target` 传 null 表示这一帧不该开火。
## 子弹挂在敌人的父节点下，这样敌人死了子弹还能继续飞。
func try_shoot(delta: float, target: Node2D) -> void:
	_fire_timer -= delta
	if target == null or bullet_scene == null or _fire_timer > 0.0:
		return
	_fire_timer = fire_interval
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.direction = Vector2(facing, 0)
	get_parent().add_child(bullet)
	bullet.global_position = _muzzle.global_position


func _flash() -> void:
	_visual.modulate = Color(2.0, 2.0, 2.0)
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color.WHITE, 0.12)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
