class_name EnemyTurret
extends Enemy
## 站桩敌人：玩家进入射程且高度接近时，转向玩家并定时开火。

@export var bullet_scene: PackedScene
@export var fire_interval := 1.4
@export var detect_range := 150.0
## 玩家与炮台的高度差在这个范围内才会开火（子弹只走水平方向）。
@export var vertical_tolerance := 20.0

var facing := -1

var _fire_timer := 0.0

@onready var _muzzle: Marker2D = $Visual/Muzzle


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()

	_fire_timer -= delta
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return

	var offset := player.global_position - global_position
	if absf(offset.x) > detect_range or absf(offset.y) > vertical_tolerance:
		return

	facing = signi(offset.x) if offset.x != 0.0 else facing
	_visual.scale.x = facing
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_shoot()


func _shoot() -> void:
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.direction = Vector2(facing, 0)
	get_parent().add_child(bullet)
	bullet.global_position = _muzzle.global_position
