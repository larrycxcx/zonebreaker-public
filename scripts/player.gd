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

@export_group("Crouch")
## 蹲下时的移动速度倍率。
@export var crouch_speed_scale := 0.45

@export_group("Shooting")
@export var fire_cooldown := 0.15

## 站立/蹲下的碰撞体高度。脚底位置不变，只压低头顶。
const STAND_HEIGHT := 16.0
const CROUCH_HEIGHT := 10.0
const HURTBOX_STAND_HEIGHT := 18.0

var facing := 1
var health := 0
var is_crouching := false

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _fire_timer := 0.0
var _invincible_timer := 0.0
var _dead := false

@onready var _visual: Node2D = $Visual
@onready var _muzzle: Marker2D = $Visual/Muzzle
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var _head_check: ShapeCast2D = $HeadCheck


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
	_update_crouch()
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

	var can_jump := _jump_buffer_timer > 0.0 and _coyote_timer > 0.0
	if can_jump and is_crouching:
		# 蹲着也能跳，但得先站得起来：头顶被挡住就跳不了。
		if _head_blocked():
			can_jump = false
		else:
			_set_crouching(false)

	if can_jump:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut


func _handle_horizontal(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	var control := 1.0 if is_on_floor() else air_control
	var speed := move_speed * (crouch_speed_scale if is_crouching else 1.0)
	if direction != 0.0:
		facing = signi(direction)
		_visual.scale.x = facing
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * control * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * control * delta)


func _update_crouch() -> void:
	# 只能在地面上主动蹲；空中松开蹲键会自动站起来。
	var wants := Input.is_action_pressed("crouch") and is_on_floor()
	if wants == is_crouching:
		return
	if wants:
		_set_crouching(true)
	elif not _head_blocked():
		_set_crouching(false)


func _set_crouching(value: bool) -> void:
	is_crouching = value
	var height := CROUCH_HEIGHT if value else STAND_HEIGHT
	var lowered := (STAND_HEIGHT - height) / 2.0
	# 碰撞体和受击框同时压低，并整体下移，保证脚底位置不变。
	(_shape.shape as RectangleShape2D).size.y = height
	_shape.position.y = lowered
	(_hurtbox_shape.shape as RectangleShape2D).size.y = HURTBOX_STAND_HEIGHT - (STAND_HEIGHT - height)
	_hurtbox_shape.position.y = lowered
	# 占位美术直接纵向压扁；第 4 步换成精灵图后这里改成切换动画。
	_visual.scale.y = height / STAND_HEIGHT
	_visual.position.y = lowered


## 头顶上方是否有东西挡着，挡着就站不起来。
func _head_blocked() -> bool:
	_head_check.force_shapecast_update()
	for i in _head_check.get_collision_count():
		var collider := _head_check.get_collider(i)
		# 单向平台可以从下面穿过去，不算挡头。
		if collider is Platform and (collider as Platform).one_way:
			continue
		return true
	return false


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
