class_name Player
extends CharacterBody2D
## 方块玩家：左右移动、跳跃、射击，有生命值和受伤无敌帧。

signal health_changed(health: int, max_health: int)
signal died

@export var bullet_scene: PackedScene

@export_group("Health")
@export var max_health := 3
## 受伤后的无敌时间，期间闪烁且不再受任何伤害。
@export var invincible_time := 1.0
## 受伤时被顶开的速度（水平方向背离伤害源）。
@export var hurt_knockback := Vector2(70, -120)

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
var health := 0

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _fire_timer := 0.0
var _invincible_timer := 0.0
var _dead := false

@onready var _visual: Node2D = $Visual
@onready var _muzzle: Marker2D = $Visual/Muzzle
@onready var _hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if _dead:
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		move_and_slide()
		return

	_apply_gravity(delta)
	_handle_jump(delta)
	_handle_horizontal(delta)
	move_and_slide()
	_handle_shoot(delta)
	_update_invincibility(delta)
	_check_contact_damage()


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


func _update_invincibility(delta: float) -> void:
	if _invincible_timer <= 0.0:
		return
	_invincible_timer -= delta
	if _invincible_timer <= 0.0:
		_visual.modulate.a = 1.0
	else:
		# 每 0.05 秒切换一次显隐，做出闪烁效果。
		_visual.modulate.a = 0.3 if int(_invincible_timer / 0.05) % 2 == 0 else 1.0


## 站在/贴着敌人身上时持续判定，无敌帧结束后会再次受伤。
func _check_contact_damage() -> void:
	if _invincible_timer > 0.0:
		return
	for body in _hurtbox.get_overlapping_bodies():
		if body is Enemy:
			take_damage((body as Enemy).contact_damage, body.global_position)
			return


## 被敌人子弹或接触伤害调用。`source_position` 用来决定击退方向。
func take_damage(amount: int, source_position := Vector2.INF) -> void:
	if _dead or _invincible_timer > 0.0:
		return
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()
		return
	_invincible_timer = invincible_time
	var away := 1.0 if source_position == Vector2.INF else signf(global_position.x - source_position.x)
	if away == 0.0:
		away = 1.0
	velocity = Vector2(hurt_knockback.x * away, hurt_knockback.y)


func _die() -> void:
	_dead = true
	health = 0
	_visual.modulate = Color(0.5, 0.5, 0.5, 1.0)
	died.emit()
