class_name Player
extends CharacterBody2D
## 方块玩家：左右移动、跳跃、射击，有生命值和受伤无敌帧。

signal health_changed(health: int, max_health: int)
signal died
signal stamina_changed(stamina: float, max_stamina: float)


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
## 趴下时的移动速度倍率。
@export var crouch_speed_scale := 0.6

@export_group("Sprint")
## 奔跑时的移动速度倍率。
@export var sprint_speed_scale := 1.5
@export var max_stamina := 100.0
## 奔跑时每秒消耗的体力。满体力大约能连续跑 max_stamina / stamina_drain 秒。
@export var stamina_drain := 35.0
## 停止奔跑后每秒恢复的体力。
@export var stamina_regen := 25.0
## 停止奔跑后隔多久才开始恢复。
@export var stamina_regen_delay := 0.5
## 体力耗尽后，要恢复到这个比例才能再次奔跑。
## 否则一直按着奔跑键时，体力会在 0 附近刚回一点就被用掉，人物一顿一顿地时快时慢。
@export_range(0.0, 1.0) var stamina_recover_ratio := 0.25

@export_group("Weapons")
## 主武器（J 开火，跟着 8 方向瞄准）。换武器 = 换这里的资源文件（weapons/*.tres）。
@export var primary_weapon: Weapon

## 瞄准方向（魂斗罗式）。W + 左右 = 边走边斜上，只按 W = 原地正上；
## S + 左右 = 边走边斜下，只按 S：地面上朝前斜下、空中朝正下；W、S 同时按互相抵消；趴下时一律水平。
enum Aim { FORWARD, UP, DIAGONAL_UP, DIAGONAL_DOWN, DOWN }

## 斜向和正下方的出膛点，相对身体中心（朝右时；朝左时 x 取反）。按约定由代码算、不挂在 Visual 下，和外观无关。
## 斜下的枪口不能太低：子弹转 45° 后半高约 3px，站在地面上（脚底在 +8）时出膛点要在 +5 以上，否则一出膛就嵌进地里。
const DIAGONAL_UP_MUZZLE := Vector2(9, -9)
const DIAGONAL_DOWN_MUZZLE := Vector2(9, 4)
const DOWN_MUZZLE := Vector2(0, 11)

## 站立/蹲下的碰撞体高度。脚底位置不变，只压低头顶。
const STAND_HEIGHT := 16.0
## 敌人子弹离地面只有 6~8px（枪口在敌人身体中线），趴下后必须矮于 6px 才躲得开，取 4px 留 2px 余量。
const CROUCH_HEIGHT := 4.0
const HURTBOX_STAND_HEIGHT := 18.0

var facing := 1
var health := 0
var is_crouching := false
var is_sprinting := false
var aim := Aim.FORWARD
var stamina := 0.0

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
## 主武器槽：冷却和弹药都在里面。
var _primary: WeaponSlot
var _invincible_timer := 0.0
var _dead := false
var _exhausted := false
var _stamina_regen_timer := 0.0

@onready var _visual: Node2D = $Visual
@onready var _muzzle: Marker2D = $Visual/Muzzle
@onready var _muzzle_up: Marker2D = $Visual/MuzzleUp
@onready var _gun: ColorRect = $Visual/Gun
@onready var _gun_up: ColorRect = $Visual/GunUp
@onready var _gun_diagonal_up: ColorRect = $Visual/GunDiagonalUp
@onready var _gun_diagonal_down: ColorRect = $Visual/GunDiagonalDown
@onready var _gun_down: ColorRect = $Visual/GunDown
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var _head_check: ShapeCast2D = $HeadCheck


func _ready() -> void:
	_primary = WeaponSlot.new(primary_weapon)
	health = max_health
	health_changed.emit(health, max_health)
	stamina = max_stamina
	stamina_changed.emit(stamina, max_stamina)
	# HeadCheck 正好覆盖「站起来需要多出来的那段空间」：从站立头顶到趴下后的头顶。
	# 按常量算而不是写死在场景里，改下蹲高度时不会不同步。
	var headroom := STAND_HEIGHT - CROUCH_HEIGHT
	(_head_check.shape as RectangleShape2D).size.y = headroom
	_head_check.position.y = -STAND_HEIGHT / 2.0 + headroom / 2.0


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
		GameEvents.report(&"jump", self)

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut


func _handle_horizontal(delta: float) -> void:
	# 手柄摇杆推过死区（0.3）就按全速走，不按推的幅度调速——像素风横版的习惯；键盘本来就只有 0 和 1。
	var direction := signf(Input.get_axis("move_left", "move_right"))
	_update_sprint(delta, direction)
	var control := 1.0 if is_on_floor() else air_control
	var speed := move_speed * _speed_scale()
	if direction != 0.0:
		facing = signi(direction)
		_visual.scale.x = facing
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * control * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * control * delta)


func _speed_scale() -> float:
	if is_crouching:
		return crouch_speed_scale
	if is_sprinting:
		return sprint_speed_scale
	return 1.0


## 按住奔跑键且正在移动时加速并消耗体力；不跑的时候隔一小段时间开始回体力。
## 原地按着奔跑键不算奔跑，也不耗体力；趴着不能奔跑。
func _update_sprint(delta: float, direction: float) -> void:
	var wants := Input.is_action_pressed("sprint") and direction != 0.0 and not is_crouching
	is_sprinting = wants and not _exhausted and stamina > 0.0

	# 先更新 _exhausted 再改体力：stamina_changed 发出时状态已经是最新的，HUD 据此变色。
	if is_sprinting:
		var drained := stamina - stamina_drain * delta
		if drained <= 0.0:
			_exhausted = true
			GameEvents.report(&"stamina_exhausted", self)
		_set_stamina(drained)
		_stamina_regen_timer = stamina_regen_delay
	elif _stamina_regen_timer > 0.0:
		_stamina_regen_timer -= delta
	else:
		var regained := stamina + stamina_regen * delta
		if _exhausted and regained >= max_stamina * stamina_recover_ratio:
			_exhausted = false
		_set_stamina(regained)


## 体力耗尽、还没恢复到能重新起跑的程度。
func is_exhausted() -> bool:
	return _exhausted


func _set_stamina(value: float) -> void:
	var clamped := clampf(value, 0.0, max_stamina)
	if clamped == stamina:
		return
	stamina = clamped
	stamina_changed.emit(stamina, max_stamina)


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


## 碰撞体中心的世界坐标。趴下时比 global_position 低 6px，敌人的视线要瞄这里。
func body_center() -> Vector2:
	return _shape.global_position


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


## J 用主武器朝当前瞄准方向开火（瞄准规则见 Aim）。趴着不动只能水平开枪（子弹贴地飞），趴着爬行时不能开枪。
func _handle_shoot(delta: float) -> void:
	_primary.tick(delta)
	var moving := Input.get_axis("move_left", "move_right") != 0.0
	_update_aim(moving)
	var crawling := is_crouching and moving
	var pressed := Input.is_action_pressed("shoot") if primary_weapon.automatic else Input.is_action_just_pressed("shoot")
	if crawling or not pressed or not _primary.is_ready():
		return
	_shoot(aim_vector())


func _update_aim(moving: bool) -> void:
	var up := Input.is_action_pressed("aim_up")
	var down := Input.is_action_pressed("aim_down")
	if is_crouching or up == down:
		aim = Aim.FORWARD
	elif up:
		aim = Aim.DIAGONAL_UP if moving else Aim.UP
	elif moving or is_on_floor():
		aim = Aim.DIAGONAL_DOWN
	else:
		aim = Aim.DOWN
	# 占位美术：按瞄准方向显示对应的那根枪。
	_gun.visible = aim == Aim.FORWARD
	_gun_up.visible = aim == Aim.UP
	_gun_diagonal_up.visible = aim == Aim.DIAGONAL_UP
	_gun_diagonal_down.visible = aim == Aim.DIAGONAL_DOWN
	_gun_down.visible = aim == Aim.DOWN


## 当前瞄准方向对应的子弹方向（单位向量）。
func aim_vector() -> Vector2:
	match aim:
		Aim.UP:
			return Vector2.UP
		Aim.DIAGONAL_UP:
			return Vector2(facing, -1).normalized()
		Aim.DIAGONAL_DOWN:
			return Vector2(facing, 1).normalized()
		Aim.DOWN:
			return Vector2.DOWN
	return Vector2(facing, 0)


## 换主武器（以后拾取武器升级就调这个）：冷却清零、弹药补满。
func equip_primary(weapon: Weapon) -> void:
	primary_weapon = weapon
	_primary.equip(weapon)


## 用主武器朝 direction 开一次火（不看冷却；_handle_shoot 先检查过了，测试也直接调它）。
func _shoot(direction: Vector2) -> void:
	_primary.fire(get_parent(), _muzzle_position(direction), direction, self)


## 出膛点。水平和正上方还用 Visual 下的老 Marker（水平枪口趴下时跟着压低，是现有高度规则的一部分，第 4 步统一迁移）；
## 斜向和正下方按新约定由代码算。
func _muzzle_position(direction: Vector2) -> Vector2:
	if direction == Vector2.UP:
		return _muzzle_up.global_position
	if direction.y == 0.0:
		return _muzzle.global_position
	if direction == Vector2.DOWN:
		return global_position + DOWN_MUZZLE
	var offset := DIAGONAL_UP_MUZZLE if direction.y < 0.0 else DIAGONAL_DOWN_MUZZLE
	return global_position + Vector2(offset.x * facing, offset.y)


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
	GameEvents.report(&"player_hurt", self)
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
	GameEvents.report(&"player_death", self)
