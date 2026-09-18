class_name Player
extends CharacterBody2D
## 方块玩家：左右移动、跳跃、射击。

@export var bullet_scene: PackedScene

@export_group("Movement")
@export var move_speed := 90.0
@export var acceleration := 700.0
@export var friction := 900.0
@export var air_control := 0.7

@export_group("Jump")
@export var jump_velocity := -280.0
@export var gravity := 900.0
@export var max_fall_speed := 400.0
## 松开跳跃键时，上升速度乘以这个系数，实现可变跳跃高度。
@export var jump_cut := 0.5
## 离开平台边缘后仍可起跳的时间（土狼时间）。
@export var coyote_time := 0.1
## 落地前提前按下跳跃键仍然有效的时间（跳跃缓冲）。
@export var jump_buffer_time := 0.1

@export_group("Shooting")
@export var fire_cooldown := 0.15

var facing := 1

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _fire_timer := 0.0

@onready var _visual: Node2D = $Visual
@onready var _muzzle: Marker2D = $Visual/Muzzle


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump(delta)
	_handle_horizontal(delta)
	move_and_slide()
	_handle_shoot(delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _handle_jump(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut


func _handle_horizontal(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	var control := 1.0 if is_on_floor() else air_control
	if direction != 0.0:
		facing = signi(direction)
		_visual.scale.x = facing
		velocity.x = move_toward(velocity.x, direction * move_speed, acceleration * control * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * control * delta)


func _handle_shoot(delta: float) -> void:
	_fire_timer -= delta
	if Input.is_action_pressed("shoot") and _fire_timer <= 0.0:
		_fire_timer = fire_cooldown
		_shoot()


func _shoot() -> void:
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.direction = Vector2(facing, 0)
	get_parent().add_child(bullet)
	bullet.global_position = _muzzle.global_position
